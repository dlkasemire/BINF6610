# Troubleshooting — Assignment 4: four failures caused on purpose

The weeks 1–3 entries are in the Git history and in the tags assignment1 to assignment3.

### 1 · Ctrl-C halfway through a smoke run, then -resume

    $ nextflow run main.nf -profile docker --samplesheet .../smoke/samplesheet.csv \
          --ref .../smoke/smoke.fa --region smoke_1mb
    [b1/2a9cf2] VALIDATE (samplesheet) | 1 of 1 ✔
    [64/79532b] FASTQC (smoke_02)      | 1 of 3
    [7b/9f227e] FASTP (smoke_03)       | 3 of 3 ✔
    [a5/1c35a9] BWA_MEM (smoke_03)     | 0 of 3
    ^C
    WARN: Killing running tasks (5)

    $ nextflow run main.nf -profile docker -resume ... (same parameters)
    [b1/2a9cf2] VALIDATE (samplesheet)     | 1 of 1, cached: 1 ✔
    [61/0f9205] FASTQC (smoke_01)          | 3 of 3, cached: 1 ✔
    [7b/9f227e] FASTP (smoke_03)           | 3 of 3, cached: 3 ✔
    [f4/083e54] BWA_MEM (smoke_01)         | 3 of 3 ✔
    Succeeded   : 15
    Cached      : 5

Cached: the 5 tasks that had finished before Ctrl-C — VALIDATE, all three FASTP
and one FASTQC (same work folders, b1/2a9cf2 and 7b/9f227e). Ran again: the two
FASTQC and three BWA_MEM tasks that were killed mid-run, and everything
downstream of them. -resume reuses only tasks that finished successfully.
My first attempt finished all 20 tasks in 1 m 55 s before I pressed Ctrl-C, so
on the second I stopped it as soon as FASTP had finished.

### 2 · The reference as a queue channel (smoke data)

I changed one line of main.nf to give BWA_MEM the reference as a queue channel:

    -    BWA_MEM(FASTP.out.reads, ref, ref_index)
    +    BWA_MEM(FASTP.out.reads, channel.fromPath(params.ref), ref_index)

    [8c/1fc84b] FASTP (smoke_03)           | 3 of 3 ✔
    [d3/548678] BWA_MEM (smoke_02)         | 1 of 1 ✔
    [06/a59c3f] MARKDUPLICATES (smoke_02)  | 1 of 1 ✔
    [1b/5e2e0e] HAPLOTYPECALLER (smoke_02) | 1 of 1 ✔
    Succeeded   : 14

    $ gzip -dc results/cohort.filtered.vcf.gz | grep '^#CHROM'
    #CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	smoke_02

Nothing stopped the run. FASTP trimmed all three samples, but BWA_MEM ran for one
sample only: channel.fromPath made a queue channel holding one item, the
reference, and the first sample to arrive consumed it, so BWA_MEM never got a
reference for the other two. The run reported Succeeded and published a
"cohort" VCF with one sample column. Stage 6's column check did not catch it,
because it compares the columns with the GVCFs it received, which was one.
Fix: give the reference as a value, `ref = file(params.ref)`, which every
sample can read (`git restore main.nf`).

### 3 · A missing backslash: $( instead of \$( in FASTP's script block

In modules/fastp.nf I took the backslash off one command substitution:

    -    n=\$(gzip -dc ${meta.id}_R1.trim.fastq.gz | wc -l)
    +    n=$(gzip -dc ${meta.id}_R1.trim.fastq.gz | wc -l)

    ERROR ~ Error executing process > 'FASTP (smoke_01)'
      Process `FASTP (smoke_01)` terminated with an error exit status (2)

In the task's work folder (work/39/109dd96d...), .command.sh shows what bash
was actually given — Nextflow had taken the $ for itself and garbled the line,
and the next line's ${meta.id} came out empty:

    $ cat .command.sh
    n=smoke_01gzip -dc smoke_01_R1.trim.fastq.gz | wc -l)
    [ "$n" -gt 0 ] || { echo ": nothing survived trimming" >&2; exit 1; }

    $ cat .command.err
    .../.command.sh: line 7: syntax error near unexpected token `)'

`bash .command.run` in the same folder reran the task in its container and
printed nothing: the wrapper writes the task's output to its own files. It
reproduced the same error in .command.log and recorded exit code 255 in
.exitcode (Nextflow had reported 2; I did not establish why the two differ).
Fix: every $ meant for bash is written \$ inside a script block
(`git restore modules/fastp.nf`).

### 4 · A two-minute time limit on HaplotypeCaller (Explorer, first run)

I set `withName: 'HAPLOTYPECALLER' { time = '2m' }` in the explorer profile and
submitted the head job (10920391). Stages 0–4 finished; HaplotypeCaller did not:

    ERROR ~ Error executing process > 'HAPLOTYPECALLER (NA12878)'
      Process `HAPLOTYPECALLER (NA12878)` terminated with an error exit status (140)

    JobID       JobName                       State       Elapsed   Timelimit  ExitCode
    10920490    nf-HAPLOTYPECALLER_(NA12003)  FAILED      00:01:16  00:02:00   12:0
    10920491    nf-HAPLOTYPECALLER_(NA12892)  FAILED      00:01:14  00:02:00   12:0
    10920492    nf-HAPLOTYPECALLER_(NA12878)  FAILED      00:01:11  00:02:00   12:0
    10920493    nf-HAPLOTYPECALLER_(NA07357)  FAILED      00:01:04  00:02:00   12:0
    10920494    nf-HAPLOTYPECALLER_(NA10851)  FAILED      00:01:01  00:02:00   12:0
    10920495    nf-HAPLOTYPECALLER_(NA12891)  CANCELLED+  00:01:00  00:02:00   0:0
    10920500    nf-HAPLOTYPECALLER_(NA12873)  CANCELLED+  00:00:33  00:02:00   0:0

The State is FAILED, not TIMEOUT, and no job reached its 00:02:00 Timelimit:
Nextflow asks Slurm for a warning signal before the limit and stops the task
when it arrives, after about a minute here. sacct's exit code 12 is that
signal, SIGUSR2, and Nextflow reports a task killed by signal 12 as
128 + 12 = 140. Once one task failed, Nextflow cancelled the HaplotypeCaller
jobs still running (CANCELLED+); NA12813 had not reached HaplotypeCaller yet.
Fix: put `time = '1h'` back (`git restore nextflow.config`) and resubmit. On
the resubmission (head job 10920960), -resume reused 32 tasks — VALIDATE, and
FASTQC, FASTP and BWA_MEM for all eight samples, and MARKDUPLICATES for seven —
and ran only NA12813's MarkDuplicates, the eight HaplotypeCallers and the
cohort stages.
