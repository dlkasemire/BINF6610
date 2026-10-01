#!/usr/bin/env bash
# run_sample.sh — stages 0 to 5, for ONE sample.
# usage: ./run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]
#
# This is what a Slurm array task runs: the scheduler picks the sample, this
# runs the pipeline on it, with the same stage functions as run_pipeline.sh.
#
# It refuses to go past stage 5 on purpose. Stages 6 to 9 need every sample,
# and one task cannot know whether the others have finished. Deciding that is
# the scheduler's job (afterok), not this script's.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

source "${HERE}/lib/common.sh"

# ---------- arguments ----------
# ${3:?...} also refuses an EMPTY sample_id, not just a missing one
SHEET=${1:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}
OUTDIR=${2:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}
SAMPLE=${3:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}
LAST=${4:-quantify}

# ---------- the stages ----------
for f in "${HERE}"/stages/*.sh; do source "$f"; done

PER_SAMPLE=(validate qc_raw trim align postprocess quantify)

known=0
for stage in "${PER_SAMPLE[@]}"; do
    [[ "$stage" == "$LAST" ]] && known=1
done
(( known )) || die "run_sample.sh stops at quantify; '${LAST}' needs the whole cohort"

# The sample has to be in the sheet. Without this, a typo runs zero samples
# through every stage and exits 0 -- a task that did nothing and reported success.
[[ -f "$SHEET" ]] || die "samplesheet not found: ${SHEET}"
[[ -n "$(rows "$SHEET" "$SAMPLE")" ]] || die "no sample '${SAMPLE}' in ${SHEET}"

log "sample=${SAMPLE} samplesheet=${SHEET} outdir=${OUTDIR} last=${LAST}"
log "REF=${REF} REGION=${REGION} THREADS=${THREADS}"
setup_dirs

# ---------- the driver ----------
n=0
for stage in "${PER_SAMPLE[@]}"; do
    log "===== ${SAMPLE} · stage ${n} : ${stage} ====="
    "stage_${stage}"
    [[ "$stage" == "$LAST" ]] && break
    n=$(( n + 1 ))
done

log "${SAMPLE}: done, stopped after ${LAST}"
