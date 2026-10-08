#!/usr/bin/env bash
# validate_samplesheet.sh — stage 0, inside the VALIDATE task.
# usage: validate_samplesheet.sh <samplesheet.csv> <reference.fa>
#
# Week 1's checks, with one change: Nextflow links every FASTQ and every
# reference file into this task's folder, so each file is opened by its
# file name, $(basename "$r1"), not by the path the samplesheet gives.
# Every problem is reported before it fails, once, at the end.
set -euo pipefail

sheet=$1
ref=$2
problems=0
log() { printf '[validate] %s\n' "$*" >&2; }

[[ -s "$sheet" ]] || { log "samplesheet not found: $sheet"; exit 1; }

# Read the columns by name, so the 6-column smoke sheet and the 10-column
# course sheet both work: prints sample_id,library_type,r1,r2 per row.
rows=$(awk -F, '
    NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i
              split("sample_id library_type r1_fastq r2_fastq", need, " ")
              for (k in need) if (!(need[k] in col)) {
                  print "samplesheet has no column named " need[k] > "/dev/stderr"; exit 65 }
              next }
    { print $col["sample_id"] "," $col["library_type"] "," $col["r1_fastq"] "," $col["r2_fastq"] }
' "$sheet") || { log "cannot read the columns of $sheet"; exit 1; }

while IFS=, read -r id lt r1 r2; do
    [[ -n "$id" ]] || { log "a row has no sample_id"; problems=$(( problems + 1 )); continue; }

    [[ "$lt" == paired || "$lt" == single ]] \
        || { log "$id: library_type is '$lt', must be paired or single"; problems=$(( problems + 1 )); }
    if [[ -z "$r2" && "$lt" == paired ]]; then
        log "$id: r2_fastq is empty but library_type says paired"; problems=$(( problems + 1 ))
    fi
    if [[ -n "$r2" && "$lt" == single ]]; then
        log "$id: r2_fastq is filled in but library_type says single"; problems=$(( problems + 1 ))
    fi

    # the files, by their names in this folder
    f1=$(basename "$r1")
    f2=""; [[ -z "$r2" ]] || f2=$(basename "$r2")

    r1_ok=0
    if [[ ! -s "$f1" ]]; then
        log "$id: R1 missing or empty: $f1"; problems=$(( problems + 1 ))
    elif ! gzip -t "$f1" 2>/dev/null; then
        log "$id: R1 is not a valid gzip file: $f1"; problems=$(( problems + 1 ))
    else
        r1_ok=1
    fi
    r2_ok=0
    if [[ "$lt" == paired && -n "$f2" ]]; then
        if [[ ! -s "$f2" ]]; then
            log "$id: R2 missing or empty: $f2"; problems=$(( problems + 1 ))
        elif ! gzip -t "$f2" 2>/dev/null; then
            log "$id: R2 is not a valid gzip file: $f2"; problems=$(( problems + 1 ))
        else
            r2_ok=1
        fi
    fi

    # whole records, and mates that agree -- only on files that passed gzip -t
    if (( r1_ok )); then
        n1=$(gzip -dc "$f1" | wc -l); n1=$(( n1 ))
        (( n1 % 4 == 0 )) || { log "$id: R1 has $n1 lines, not a whole number of records"; problems=$(( problems + 1 )); }
        if (( r2_ok )); then
            n2=$(gzip -dc "$f2" | wc -l); n2=$(( n2 ))
            (( n1 == n2 )) || { log "$id: R1 has $(( n1 / 4 )) reads, R2 has $(( n2 / 4 ))"; problems=$(( problems + 1 )); }
        fi
    fi
done <<< "$rows"

# duplicate sample ids
dupes=$(printf '%s\n' "$rows" | cut -d, -f1 | sort | uniq -d)
[[ -z "$dupes" ]] || { log "duplicate sample_id: $dupes"; problems=$(( problems + 1 )); }

# the reference, with everything BWA and GATK need beside it
[[ -s "$ref" ]]            || { log "no reference: $ref";        problems=$(( problems + 1 )); }
[[ -s "${ref}.fai" ]]      || { log "no ${ref}.fai";             problems=$(( problems + 1 )); }
[[ -s "${ref%.fa}.dict" ]] || { log "no ${ref%.fa}.dict";        problems=$(( problems + 1 )); }
[[ -s "${ref}.bwt" ]]      || { log "no BWA index ${ref}.bwt";   problems=$(( problems + 1 )); }

(( problems == 0 )) || { log "validation failed with ${problems} problem(s)"; exit 1; }
log "validation passed: $(printf '%s\n' "$rows" | wc -l | tr -d ' ') samples"
