#!/usr/bin/env bash
# run_pipeline.sh — ten-stage variant-calling pipeline, for EVERY sample.
# usage: ./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage] [first-stage]
#
# first-stage is for the cluster's cohort job, which starts at merge because
# the array tasks have already run stages 0-5 for every sample.
#
# The stages live in stages/, one per file, and what they share lives in
# lib/common.sh. run_sample.sh calls the same stages for one sample.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

source "${HERE}/lib/common.sh"

# ---------- arguments ----------
[[ $# -ge 2 ]] || die "usage: $0 <samplesheet.csv> <outdir> [last-stage]"
SHEET=$1
OUTDIR=$2
LAST=${3:-publish}      # no third argument means run everything
FIRST=${4:-validate}    # no fourth argument means start at the beginning
SAMPLE=""               # empty: every stage works on every sample in the sheet

# ---------- the stages ----------
for f in "${HERE}"/stages/*.sh; do source "$f"; done

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

known=0                       # catch a typo before anything runs
for stage in "${STAGES[@]}"; do
    [[ "$stage" == "$LAST" ]] && known=1
done
(( known )) || die "unknown stage: ${LAST} (choose from: ${STAGES[*]})"

known=0
for stage in "${STAGES[@]}"; do
    [[ "$stage" == "$FIRST" ]] && known=1
done
(( known )) || die "unknown stage: ${FIRST} (choose from: ${STAGES[*]})"

log "samplesheet=${SHEET} outdir=${OUTDIR} first=${FIRST} last=${LAST}"
log "REF=${REF} REGION=${REGION} THREADS=${THREADS}"
setup_dirs

# ---------- the driver ----------
n=0
started=0
for stage in "${STAGES[@]}"; do
    [[ "$stage" == "$FIRST" ]] && started=1
    if (( started )); then
        log "===== stage ${n} : ${stage} ====="
        "stage_${stage}"
    fi
    [[ "$stage" == "$LAST" ]] && break
    n=$(( n + 1 ))
done

# A first stage that comes after the last one would run nothing and exit 0.
(( started )) || die "first stage ${FIRST} comes after last stage ${LAST}; nothing ran"

log "done: stopped after ${LAST}"
