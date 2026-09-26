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
