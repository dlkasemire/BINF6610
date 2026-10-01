# shellcheck shell=bash
set -euo pipefail   # already set by the driver that sources this; stated here so the file says so itself
# 3 · align — BWA-MEM straight into a sorted BAM.
stage_align() {
    local id cond rep lt r1 r2 rg bam total mapped rate
    while IFS=, read -r id cond rep lt r1 r2; do
        bam="${ALN}/${id}.bam"

        # The read group labels every read with its sample. SM becomes the
        # sample's column name in the VCF, so it must be the sample_id.
        rg="@RG\tID:${id}\tSM:${id}\tLB:${id}\tPL:ILLUMINA"

        if [[ "$lt" == paired ]]; then
            bwa mem -t "$THREADS" -R "$rg" "$REF" \
                    "${TRIM}/${id}_R1.fastq.gz" "${TRIM}/${id}_R2.fastq.gz" \
                    2> "${LOG}/${id}.bwa.log"
        else
            bwa mem -t "$THREADS" -R "$rg" "$REF" \
                    "${TRIM}/${id}_R1.fastq.gz" \
                    2> "${LOG}/${id}.bwa.log"
        fi | samtools sort -@ "$THREADS" -T "${TMPDIR:-/tmp}/sort.${id}.$$" -o "$bam" 2> "${LOG}/${id}.sort.log"

        # BWA prints no alignment rate, so count it from the BAM.
        [[ -s "$bam" ]] || die "$id: no BAM written"
        total=$(samtools view -c "$bam")
        mapped=$(samtools view -c -F 4 "$bam")
        (( total > 0 )) || die "$id: BAM has no reads"
        rate=$(awk -v m="$mapped" -v t="$total" 'BEGIN { printf "%.1f", 100 * m / t }')
        log "$id: ${rate}% of ${total} reads aligned"
        awk -v r="$rate" 'BEGIN { exit !(r > 50) }' \
            || die "$id: alignment rate ${rate}% — wrong reference, or the mates are mixed up"
    done < <(rows "$SHEET" "$SAMPLE")
}
