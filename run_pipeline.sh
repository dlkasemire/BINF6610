#!/usr/bin/env bash
# run_pipeline.sh ten stage variant-calling pipeline
# usage : ./run_pipeline.sh <samplesheet.csv> <uttdir> [last-stage]
set -euo pipefail

# All messages go to stderr (>&2), so stdout stays clean for data
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# ---------- arguments ----------
[[ $# -ge 2 ]] || die "usage: $0 <samplesheet.csv> <outdir> [last-stage]"
SHEET=$1
OUTDIR=$2
LAST=${3:-publish}      # no third argument means run everything

log "samplesheet=${SHEET} outdir=${OUTDIR} last=${LAST}"

# ---------- configuration ----------
# Find the folder this script lives in, so conf/ is found from anywhere
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/conf/pipeline.env"

log "REF=${REF} REGION=${REGION} THREADS=${THREADS}"

# ---------- stages (placeholders for now) ----------
stage_validate()    { log "validate: not written yet, skipping"; }
stage_qc_raw()      { die "stage qc_raw not implemented yet"; }
stage_trim()        { die "stage trim not implemented yet"; }
stage_align()       { die "stage align not implemented yet"; }
stage_postprocess() { die "stage postprocess not implemented yet"; }
stage_quantify()    { die "stage quantify not implemented yet"; }
stage_merge()       { die "stage merge not implemented yet"; }
stage_analyze()     { die "stage analyze not implemented yet"; }
stage_qc_report()   { die "stage qc_report not implemented yet"; }
stage_publish()     { die "stage publish not implemented yet"; }

# ---------- driver ----------
STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

known=0                       # catch a typo before anything runs
for stage in "${STAGES[@]}"; do
    [[ "$stage" == "$LAST" ]] && known=1
done
(( known )) || die "unknown stage: ${LAST} (choose from: ${STAGES[*]})"

n=0
for stage in "${STAGES[@]}"; do
    log "===== stage ${n} : ${stage} ====="
    "stage_${stage}"
    [[ "$stage" == "$LAST" ]] && break
    n=$(( n + 1 ))
done

log "done: stopped after ${LAST}"
