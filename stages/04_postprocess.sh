# shellcheck shell=bash
set -euo pipefail   # already set by the driver that sources this; stated here so the file says so itself
# 4 · postprocess — mark duplicates, index, flagstat.
stage_postprocess() {
    local id cond rep lt r1 r2 bam dedup
    while IFS=, read -r id cond rep lt r1 r2; do
        bam="${ALN}/${id}.bam"
        dedup="${ALN}/${id}.dedup.bam"

        # GATK writes a lot to both channels, so all of it goes to the log.
        # Because nothing reaches the screen, a failure needs its own message.
        gatk MarkDuplicates -I "$bam" -O "$dedup" -M "${LOG}/${id}.markdup.txt" \
             > "${LOG}/${id}.markdup.log" 2>&1 \
             || die "$id: MarkDuplicates failed — see ${LOG}/${id}.markdup.log"
        [[ -s "$dedup" ]] || die "$id: MarkDuplicates wrote no BAM"

        samtools index "$dedup"
        [[ -s "${dedup}.bai" ]] || die "$id: no index for ${dedup}"

        samtools flagstat "$dedup" > "${LOG}/${id}.flagstat.txt"
        [[ -s "${LOG}/${id}.flagstat.txt" ]] || die "$id: flagstat wrote nothing"

        log "$id: duplicates marked, indexed"
    done < <(rows "$SHEET" "$SAMPLE")
}
