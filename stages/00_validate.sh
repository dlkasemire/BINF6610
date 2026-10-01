# shellcheck shell=bash
set -euo pipefail   # already set by the driver that sources this; stated here so the file says so itself
# 0 · validate — check everything before computing anything.
stage_validate() {
    local id cond rep lt r1 r2 problems=0 n1 n2

    # the samplesheet has to exist, and have the columns rows() looks for by name
    [[ -f "$SHEET" ]] || die "samplesheet not found: ${SHEET}"
    rows "$SHEET" > /dev/null || die "cannot read the columns of ${SHEET}"

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
    done < <(rows "$SHEET" "$SAMPLE")

    # duplicate sample ids, over the whole sheet. sort | uniq -d prints only the repeats.
    local dupes
    dupes=$(rows "$SHEET" | cut -d, -f1 | sort | uniq -d)
    [[ -z "$dupes" ]] || { log "duplicate sample_id: $dupes"; problems=$(( problems + 1 )); }

    # the reference is where the config says, with everything BWA and GATK need
    [[ -s "$REF" ]]            || { log "no reference at ${REF}";      problems=$(( problems + 1 )); }
    [[ -s "${REF}.fai" ]]      || { log "no .fai index beside ${REF}"; problems=$(( problems + 1 )); }
    [[ -s "${REF%.fa}.dict" ]] || { log "no .dict beside ${REF}";      problems=$(( problems + 1 )); }
    [[ -s "${REF}.bwt" ]]      || { log "no BWA index beside ${REF}";  problems=$(( problems + 1 )); }

    (( problems == 0 )) || die "validation failed with ${problems} problem(s)"
    log "validation passed"
}
