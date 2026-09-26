#!/usr/bin/env bash
# run_pipeline.sh — ten-stage variant-calling pipeline
# usage: ./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]
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

#=============================================================================
# 0 · validate — check everything before computing anything
#=============================================================================
stage_validate() {
    local id cond rep lt r1 r2 problems=0 n1 n2

    # the samplesheet has to exist before any row can be read
    [[ -f "$SHEET" ]] || die "samplesheet not found: ${SHEET}"

    while IFS=, read -r id cond rep lt r1 r2; do
        [[ -n "$id" ]] || { log "a row has no sample_id"; problems=$(( problems + 1 )); continue; }

        # library_type must be one of the two values the stages branch on
        [[ "$lt" == paired || "$lt" == single ]] \
            || { log "$id: library_type is '$lt', must be paired or single"; problems=$(( problems + 1 )); }

        # the files exist and are not empty
        [[ -s "$r1" ]] || { log "$id: R1 missing or empty: $r1"; problems=$(( problems + 1 )); }
        if [[ "$lt" == paired ]]; then
            [[ -s "$r2" ]] || { log "$id: declared paired but R2 is missing"; problems=$(( problems + 1 )); }
        fi

        # the r2 column and the declared layout agree, in both directions
        if [[ -z "$r2" && "$lt" == paired ]]; then
            log "$id: r2_fastq is empty but library_type says paired"
            problems=$(( problems + 1 ))
        fi
        if [[ -n "$r2" && "$lt" == single ]]; then
            log "$id: r2_fastq is filled in but library_type says single"
            problems=$(( problems + 1 ))
        fi

        # the gzip streams are whole
        [[ ! -s "$r1" ]] || gzip -t "$r1" 2>/dev/null \
            || { log "$id: R1 is not a valid gzip file"; problems=$(( problems + 1 )); }
        [[ ! -s "$r2" ]] || gzip -t "$r2" 2>/dev/null \
            || { log "$id: R2 is not a valid gzip file"; problems=$(( problems + 1 )); }

        # the records are whole, and the mates agree.
        # Only count a file that passed gzip -t: under pipefail, unzipping a
        # truncated file kills the script and every later problem goes unreported.
        if [[ -s "$r1" ]] && gzip -t "$r1" 2>/dev/null; then
            n1=$(gzip -dc "$r1" | wc -l)
            (( n1 % 4 == 0 )) || { log "$id: R1 has $n1 lines, not a whole number of records"
                                   problems=$(( problems + 1 )); }
            if [[ "$lt" == paired && -s "$r2" ]] && gzip -t "$r2" 2>/dev/null; then
                n2=$(gzip -dc "$r2" | wc -l)
                (( n1 == n2 )) || { log "$id: R1 has $(( n1 / 4 )) reads, R2 has $(( n2 / 4 ))"
                                    problems=$(( problems + 1 )); }
            fi
        fi
    done < <(tail -n +2 "$SHEET")

    # duplicate sample ids. sort | uniq -d prints only the repeats.
    local dupes
    dupes=$(awk -F, 'NR>1 { print $1 }' "$SHEET" | sort | uniq -d)
    [[ -z "$dupes" ]] || { log "duplicate sample_id: $dupes"; problems=$(( problems + 1 )); }

    # the reference is where the config says, with everything BWA and GATK need
    [[ -s "$REF" ]]            || { log "no reference at ${REF}";      problems=$(( problems + 1 )); }
    [[ -s "${REF}.fai" ]]      || { log "no .fai index beside ${REF}"; problems=$(( problems + 1 )); }
    [[ -s "${REF%.fa}.dict" ]] || { log "no .dict beside ${REF}";      problems=$(( problems + 1 )); }
    [[ -s "${REF}.bwt" ]]      || { log "no BWA index beside ${REF}";  problems=$(( problems + 1 )); }

    (( problems == 0 )) || die "validation failed with ${problems} problem(s)"
    log "validation passed"
}

#=============================================================================
# 1-9 · placeholders — each is replaced as it is written
#=============================================================================
stage_qc_raw()      { die "stage qc_raw not implemented yet"; }
stage_trim()        { die "stage trim not implemented yet"; }
stage_align()       { die "stage align not implemented yet"; }
stage_postprocess() { die "stage postprocess not implemented yet"; }
stage_quantify()    { die "stage quantify not implemented yet"; }
stage_merge()       { die "stage merge not implemented yet"; }
stage_analyze()     { die "stage analyze not implemented yet"; }
stage_qc_report()   { die "stage qc_report not implemented yet"; }
stage_publish()     { die "stage publish not implemented yet"; }

#=============================================================================
# the driver — ten stages, in order, one after another
#=============================================================================
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
