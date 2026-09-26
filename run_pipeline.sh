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
