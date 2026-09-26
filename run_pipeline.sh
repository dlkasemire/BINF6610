#!/usr/bin/env bash
# run_pipeline.sh ten stage variant-calling pipeline
# usage : ./run_pipeline.sh <samplesheet.csv> <uttdir> [last-stage]
set -euo pipefail

# All messages go to stderr (>&2), so stdout stays clean for data
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

log "hello from the pipeline"
