# Troubleshooting log

## THREADS: unbound variable

**Symptom:** running `./run_pipeline.sh samplesheet.csv out validate` stopped with
`line 23: THREADS: unbound variable`.

**Evidence:** the error came from the line that logs the config values. REF and
REGION on the same line expanded fine, so `conf/pipeline.env` was being found
and loaded; only THREADS was missing.

**Cause:** the `THREADS` line was missing from `conf/pipeline.env`. `set -u`
stopped the script instead of letting `$THREADS` silently become an empty string.

**Fix:** added `: "${THREADS:=4}"` to `conf/pipeline.env`. The run then printed
`REF=... REGION=smoke_1mb THREADS=4`.

## FastQC printed stray lines to stdout

**Symptom:** after adding stage 1, each run printed `application/gzip` lines
between my log messages. They had no timestamp, so they were not coming from
my `log` function.

**Evidence:** I reran with `2>/dev/null` to discard stderr. My own log lines
disappeared, but the `application/gzip` lines were still there, so they were
on stdout. After a first fix they still appeared once for each paired sample
and never for the single-end one, which pointed at the line that only runs
for paired samples: the R2 FastQC call.

**Cause:** this FastQC version prints the detected file type to stdout, even
with `-q`. The demo's `2>` only redirected stderr, and my first fix had only
been applied to the R1 line.

**Fix:** sent both channels into the per-sample log on both FastQC lines:
`> "${LOG}/${id}.fastqc.log" 2>&1` (and `>>` for R2). A rerun with
`2>/dev/null` then printed nothing.

## My terminal closed itself after a failed command

**Symptom:** running the driver with no arguments printed the expected usage
error, and then the terminal window printed `Saving session...` and
`-bash: HISTTIMEFORMAT: unbound variable` and closed.

**Evidence:** the usage error was correct and came from my script; the next
two lines came from the terminal shutting down, not from my code.

**Cause:** earlier I had run `source conf/pipeline.env` directly in the
terminal to check REF. That ran its `set -euo pipefail` in my interactive
shell, so the shell itself exited on the next failed command, and `-u`
tripped over one of the shell's own variables while exiting.

**Fix:** opened a new terminal. I now only check the config in a throwaway
shell: `bash -c 'source conf/pipeline.env && ls -l "$REF"'`.

## Checking the smoke run against the truth files

Before submitting I compared my filtered VCF with each sample's
`smoke_0N.truth.txt`, counting a planted SNV as found when that sample's
genotype is not `0/0` at its position:

| sample   | found     |
|----------|-----------|
| smoke_01 | 850 / 850 (100.0 %) |
| smoke_02 | 828 / 829 (99.9 %)  |
| smoke_03 | 798 / 866 (92.1 %)  |

smoke_03 is single-end at about 9x depth, so some positions have too few
reads for a confident heterozygous call; this matches the 92–100 % range the
assignment gives for a complete pipeline.



# Assignment 2 — four deliberate failures on Explorer

### 1 · The TIMEOUT (--time=00:02:00)

    JobID                     State    Elapsed ExitCode
    10750177_1              TIMEOUT   00:02:18      0:0
    10750177_1.batch      CANCELLED   00:02:21     0:15

The log reached stage 3 (`===== NA12878 · stage 3 : align =====`) and then
Slurm wrote `CANCELLED AT 2026-10-01T19:24:33 DUE TO TIME LIMIT`; the 15 in
the batch step's exit code is SIGTERM. Stages 0–2 had finished: qc_raw/ held
both FastQC reports and trim/ both trimmed FASTQs at full size (87 MB and
91 MB). bwa.log existed, but align/ was empty: samtools sort was still
collecting reads in its temporary files under ${TMPDIR} on the node, and it
only writes the final BAM when it finishes, so no half-written BAM was left
in the run directory. The temporary files were in /tmp/10750177, which the
EXIT trap removes.

### 2 · The failed task under afterok (task 2 made to exit 1)

    JobID                     State               Reason
    10750290              CANCELLED           Dependency
    10750288_1           CANCELLED+                 None
    10750288_2               FAILED                 None

With a temporary line making task 2 `exit 1`, I submitted `bash submit.sh 1-2`.
Task 2 failed at once, but the cohort job 10750290 was not cancelled straight
away: squeue still showed it PENDING with reason (Dependency) while task 1 was
running, because Slurm cannot decide whether the whole array succeeded until
every task has ended. When I cancelled task 1, the array was finished with a
failed task, afterok could never be satisfied, and the cohort job ended
CANCELLED with Reason=Dependency, without ever starting. Stages 6–9 never ran
on an incomplete set of samples. With afterany it would have started and
genotyped only the samples whose GVCFs existed.

### 3 · The out-of-range task (--array=9 against an eight-row samplesheet)

    JobID                     State    Elapsed ExitCode
    10750121_9               FAILED   00:00:09     64:0
    10750121_9.batch         FAILED   00:00:09     64:0

Task 9 looked for row 9 below the header, found none, and the guard in
`01_persample.sbatch` stopped it before anything ran. Its log says only
`task 9: no row 9 in /courses/BINF6610.202710/data/samplesheet-variant8.csv`.
Without that guard SAMPLE would be empty. `run_sample.sh` would still refuse
it (`${3:?}` rejects an empty sample_id), but with neither guard,
`rows "$SHEET" ""` returns every row, so task 9 would have run stages 0–5 on
all eight samples inside one task and finished COMPLETED: the one failure
this week that is silent.

### 4 · scancel mid-write, then resubmit: the partial file

    JobID                     State    Elapsed ExitCode
    10750576_1           CANCELLED+   00:04:59      0:0
    10750576_1.batch      CANCELLED   00:05:02     0:15
    10750663_1            COMPLETED   00:08:38      0:0

My first attempt (10750484) finished before I cancelled it, so nothing was
cut off; the second time I scripted it to cancel 60 s into stage 5. That left
a partial file under its real name: gvcf/NA12878.g.vcf.gz at 4.2 MB, with no
.tbi beside it, and `gzip -t` reported `unexpected end of file`. A check like
`[[ -s file ]]` would have called it done. The rerun (10750663) did not trust
it: its log shows all six stage headers, 0 to 5, and it rewrote the GVCF in
full (22.7 MB) with its .tbi. That is safe only because my stages never skip
work, which also means the rerun repeated stages 0–4 that had been fine;
adding a skip would need write-to-.tmp-then-rename first, or it would trust
the broken file.


# Assignment 3: four deliberate failures with the container

### 1 · An unpinned recipe, rebuilt a day later

In a scratch folder outside the repository I built this recipe on the evening
of 2026-10-01, and rebuilt it the next evening with `--pull --no-cache`:

    FROM ubuntu
    RUN apt-get update && apt-get install -y curl

    $ docker build --platform linux/amd64 -t unpinned:day1 .
    $ docker run --rm --platform linux/amd64 unpinned:day1 dpkg -l > day1-packages.txt
    ... a day later ...
    $ docker build --pull --no-cache --platform linux/amd64 -t unpinned:day2 .
    $ docker run --rm --platform linux/amd64 unpinned:day2 dpkg -l > day2-packages.txt
    $ diff day1-packages.txt day2-packages.txt
    115c115
    < ii  rust-coreutils   0.8.0-0ubuntu3            amd64  Universal coreutils utils, written in Rust
    ---
    > ii  rust-coreutils   0.10.0-1ubuntu2~26.04.1   amd64  Universal coreutils utils, written in Rust

    $ docker image inspect --format '{{.Id}}' unpinned:day1 unpinned:day2
    sha256:019ac2be2e0310dc8bc81ed1a24ac2f40d966f45d76c659c23c4c231fd4d647d
    sha256:de9b1fe77caaf1e78f0726e032b75cd706e6ab3c98d2671e47bb062c0f8844ed

Both lists have 122 lines and the same packages, but one changed version:
rust-coreutils, which provides ls, cp, cat, sort and wc, went from 0.8.0 to
0.10.0, an update Ubuntu published to 26.04 between my two builds. The build
log showed `FROM ubuntu` resolving to `ubuntu:latest@sha256:3595d7fc...`, and
the two images have different IDs. Nothing in the recipe changed, yet the
commands inside the image did, and I never asked for that package. Fix: pin
everything, as containers/Dockerfile does: a tagged base image
(`mambaorg/micromamba:2.0.5-ubuntu24.04`), `=version` on every tool, and the
pushed image recorded by its digest, so a later rebuild cannot silently
change what runs.

### 2 · No --bind: the container could not see /courses

I deleted the `--bind /courses/BINF6610.202710,/scratch/${USER}` line from
01_persample.sbatch and ran task 1 (`sbatch --array=1 01_persample.sbatch`).

    JobID                     State    Elapsed ExitCode
    10753223_1               FAILED   00:00:05      1:0

    task 1: NA12878 on c3014, 4 cores, image /scratch/kasemire.d/containers/variant-call.sif
    [23:24:25] ERROR: samplesheet not found: /courses/BINF6610.202710/data/samplesheet-variant8.csv

It stopped in 5 seconds with exit 1, at run_sample.sh's first check. The path
the container could not see was /courses/BINF6610.202710/data/samplesheet-variant8.csv:
the job script, outside the container, had just read that same file to pick
NA12878, but inside, without --bind, only my home directory, /tmp and the
submit directory exist. Fix: put the --bind line back (`git restore`), which
adds /courses (the samplesheet, FASTQs and reference) and /scratch/${USER}
(the run directory).

### 3 · No --env THREADS: the job held 8 cores and used 4

I deleted the `--env THREADS="${THREADS}"` line from 01_persample.sbatch and ran
task 1 with `sbatch --array=1 --cpus-per-task=8` (job 10753125). I asked for 8
rather than my usual 4 because the pipeline's own default is THREADS=4, which
would have hidden the difference.

    JobID                     State    Elapsed  AllocCPUS
    10753125_1           CANCELLED+   00:03:44          8

    task 1: NA12878 on c3014, 8 cores, image /scratch/kasemire.d/containers/variant-call.sif
    [23:18:50] REF=... REGION=chr20:1-10000000 THREADS=4
    [main] CMD: bwa mem -t 4 -R @RG\tID:NA12878\tSM:NA12878\tLB:NA12878\tPL:ILLUMINA ...

The job script set THREADS=8 from SLURM_CPUS_PER_TASK, but `--cleanenv` stopped
it at the container, so lib/common.sh fell back to `THREADS=${THREADS:-4}` and
bwa ran with `-t 4` on 8 allocated cores. Nothing failed and nothing warned;
only the log shows it. (I cancelled the job myself once bwa had written its
[main] CMD line; stages 4–5 were not needed.) Fix: put the line back
(`git restore`), so every variable the job script exports and the pipeline
reads is carried in by name.

### 4 · An arm64 image on Explorer

    $ apptainer pull --arch arm64 arm.sif docker://ubuntu:24.04; echo "pull exit: $?"
    INFO:    Creating SIF file...
    pull exit: 0
    $ apptainer exec arm.sif uname -m; echo "run exit: $?"
    FATAL:   While checking container encryption: could not open image /scratch/kasemire.d/arm.sif: the image's architecture (arm64) could not run on the host's (amd64)
    run exit: 255

On a compute node (c3014) the pull succeeded without a warning, and the image
only failed when something tried to run in it, with exit 255. This is what an
image built on an Apple-silicon laptop without `--platform` would do.
Fix: build with `docker build --platform linux/amd64 ...` and check
`docker image inspect --format '{{.Architecture}}'` prints amd64 before pushing,
as I did for dlkasemire/variant-call:1.0.
