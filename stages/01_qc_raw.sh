# shellcheck shell=bash
set -euo pipefail   # already set by the driver that sources this; stated here so the file says so itself
# 1 · qc_raw — FastQC on the reads as they arrived.
stage_qc_raw() {
    local id cond rep lt r1 r2 base
    while IFS=, read -r id cond rep lt r1 r2; do
        fastqc -q -o "$QC" "$r1" > "${LOG}/${id}.fastqc.log" 2>&1
        [[ "$lt" != paired ]] || fastqc -q -o "$QC" "$r2" >> "${LOG}/${id}.fastqc.log" 2>&1

        # fastqc can exit 0 and write nothing. Ask the disk.
        base=$(basename "$r1" .fastq.gz)
        [[ -s "${QC}/${base}_fastqc.zip" ]] || die "$id: fastqc produced no report for R1"
        if [[ "$lt" == paired ]]; then
            base=$(basename "$r2" .fastq.gz)
            [[ -s "${QC}/${base}_fastqc.zip" ]] || die "$id: fastqc produced no report for R2"
        fi
        log "$id: qc done"
    done < <(rows "$SHEET" "$SAMPLE")
}
