# Troubleshooting — Assignment 5 (Snakemake)

Four failures caused on purpose. Each has the command, what Snakemake printed, and the fix.
Weeks 1–4's entries are in the Git history (tags assignment1 to assignment4).

## 1 · Ctrl-C halfway through a laptop run

**Command.** A fresh smoke run (`rm -rf results work logs`, then):

    snakemake --profile profiles/laptop \
        --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb

I pressed Ctrl-C at 9 of 21 steps, while `bwa_mem` was running for smoke_01.

**What Snakemake printed.**

    ^CTerminating processes on user request, this might take some time.
    RuleException:
    CalledProcessError in file ".../Snakefile", line 157:
    Command 'set -euo pipefail; (bwa mem -t 4 ... ) > logs/bwa_mem/smoke_01.log 2>&1' died with <Signals.SIGINT: 2>.
    Error in rule bwa_mem:
        jobid: 5
        output: work/align/smoke_01.bam
    WorkflowError:
    At least one job did not complete successfully.

**Then the same command again.** I expected Snakemake to refuse with
`IncompleteFilesException` and tell me to add `--rerun-incomplete`. It did not refuse.
It went straight on and finished:

    Job stats:
    bwa_mem 1, markduplicates 3, haplotypecaller 3, multiqc 1,
    joint_genotype 1, filter 1, publish 1, all 1 — total 12
    ...
    rule bwa_mem: reason: Missing output files: work/align/smoke_01.bam
    ...
    12 of 12 steps (100%) done

**Why.** Ctrl-C killed the running `bwa_mem` job, so that job counted as *failed*, and
Snakemake deletes the output of a failed job. So the second run found no cut-off BAM,
only a missing one, and simply made it again. `--rerun-incomplete` is for files that are
still there but marked incomplete in `.snakemake/` (for example after the computer or
the head process is killed so hard that Snakemake cannot clean up). Here there was
nothing to rerun as incomplete.

**How many jobs ran.** 12 of the 21. The 9 finished before Ctrl-C (validate, 3 fastqc,
3 fastp, 2 bwa_mem) were reused.

**Fix.** None needed. Run the same command again.

## 2 · A log without the output's wildcard

**Command.** In `rule bwa_mem` I changed `log: "logs/bwa_mem/{sample}.log"` to
`log: "logs/bwa_mem.log"`, then ran a dry run:

    snakemake --profile profiles/laptop -n \
        --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb

**What Snakemake printed.** It stopped before building the job graph:

    RuleException in file ".../Snakefile", line 142:
    Not all output, log and benchmark files of rule bwa_mem contain the same wildcards.
    This is crucial though, in order to avoid that two or more jobs write to the same file.

**Why it refuses.** `bwa_mem` runs once per sample: its output `work/align/{sample}.bam`
has the wildcard `{sample}`. A log without `{sample}` would be the same file for all
three jobs, so three jobs running at once would write over each other's log, and the
log of a failed sample could belong to another one. Snakemake checks this in the rule
itself, so it fails even with `-n`, before any job runs.

**Fix.** Put `{sample}` back: `log: "logs/bwa_mem/{sample}.log"` (`git restore Snakefile`).

## 3 · Both wildcard_constraints deleted from the fastp rules

**Command.** I deleted `wildcard_constraints:` and the `sample=one_of(...)` line under it
from both `fastp_paired` and `fastp_single`, then ran a dry run:

    sed -i '' '/wildcard_constraints:/{N;d;}' Snakefile
    snakemake --profile profiles/laptop -n \
        --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb

**What Snakemake printed.**

    Building DAG of jobs...
    AmbiguousRuleException:
    Rules fastp_single and fastp_paired are ambiguous for the file work/trim/smoke_01_R1.trim.fastq.gz.
    Consider starting rule output with a unique prefix, constrain your wildcards, or use the ruleorder directive.
    Wildcards:
        fastp_single: sample=smoke_01
        fastp_paired: sample=smoke_01

**Which rules and which file.** The two rules are `fastp_single` and `fastp_paired`; the
file is `work/trim/smoke_01_R1.trim.fastq.gz`. Both rules have that output name, on
purpose, so that `bwa_mem` can ask for `{sample}_R1.trim.fastq.gz` without knowing the
library type. Without the constraints `{sample}` matches any name in both rules, so
Snakemake has two ways to make smoke_01's R1 file and no reason to prefer one. It
stopped at the first file it met (smoke_01, a paired sample); the single-end smoke_03
would have been ambiguous too.

**Fix.** Put the constraints back (`git restore Snakefile`):
`sample=one_of(PAIRED)` on `fastp_paired`, `sample=one_of(SINGLE)` on `fastp_single`.
Each sample name now matches exactly one rule.

## 4 · The first Explorer run without Apptainer

**Command.** On Explorer only, I deleted `software-deployment-method: apptainer` from
`profiles/explorer/profile.yaml` (`sed -i '/software-deployment-method: apptainer/d' ...`)
and submitted the head job: `sbatch slurm/snakemake.sbatch`, job 11102529.

(Before that, job 11102364 printed `Nothing to be done (all requested files are present
and up to date).` I had not yet removed last week's Nextflow `results/`, which holds the
five files `rule all` asks for, so Snakemake saw nothing to make. `rm -rf results`, then
I submitted again.)

**Which rule failed.** `validate` ran and finished: it uses only bash, awk and gzip,
which every compute node has. Then the per-sample jobs started, and `fastqc` (NA12813,
Slurm job 11102617) and `fastp_single` (NA12892 and NA12003, jobs 11102619 and 11102618)
failed. The head job's log says only that a Slurm job failed:

    Error in rule fastqc:
        message: SLURM-job '11102617' failed, SLURM status is: 'FAILED'. Reason: Unknown.
        log: logs/fastqc/NA12813.log, .snakemake/slurm_logs/rule_fastqc/NA12813/11102617.log
    ...
    WorkflowError:
    At least one job did not complete successfully.

**The exit status.** In that job's own Slurm log,
`.snakemake/slurm_logs/rule_fastqc/NA12813/11102617.log`, line 76:

    Command 'set -euo pipefail; (mkdir -p work/fastqc/NA12813 && fastqc -q -o ...) > logs/fastqc/NA12813.log 2>&1'
    returned non-zero exit status 127.

127 is the shell's "command not found". `sacct -j 11102617` shows `FAILED 1:0`: inside
the Slurm job, Snakemake ran the command, saw 127, and then exited with 1 itself.

**What the rule's own log says.** `logs/fastqc/NA12813.log`:

    /usr/bin/bash: line 1: fastqc: command not found

Without `software-deployment-method: apptainer`, Snakemake ignores every rule's
`container:` and runs the command straight on the compute node, where only the
`binf6610-workflows` environment (Snakemake itself) is loaded. FastQC and fastp are
only in the images.

**Fix.** `git restore profiles/explorer/profile.yaml` puts the line back, then the same
head job again: `sbatch slurm/snakemake.sbatch`, job 11103070.

**Did validate run again?** Yes. Before resubmitting, `snakemake --profile profiles/explorer -n`
listed `rule validate` with:

    reason: Software environment definition has changed since last execution

Snakemake records how each job ran. `validate` had run without its image, the profile
now runs it in the `tools` image, so its finished output is not reused.
