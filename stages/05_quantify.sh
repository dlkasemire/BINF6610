# shellcheck shell=bash
set -euo pipefail   # already set by the driver that sources this; stated here so the file says so itself
# 5 · quantify — per-sample variant calling into a GVCF.
stage_quantify() {
    local id cond rep lt r1 r2 dedup gvcf n
    while IFS=, read -r id cond rep lt r1 r2; do
        dedup="${ALN}/${id}.dedup.bam"
        gvcf="${GVCF}/${id}.g.vcf.gz"

        gatk HaplotypeCaller -R "$REF" -I "$dedup" -O "$gvcf" \
             -ERC GVCF -L "$REGION" \
             > "${LOG}/${id}.haplotypecaller.log" 2>&1 \
             || die "$id: HaplotypeCaller failed — see ${LOG}/${id}.haplotypecaller.log"

        [[ -s "$gvcf" ]]       || die "$id: no GVCF written"
        [[ -s "${gvcf}.tbi" ]] || die "$id: GVCF has no index"

        # count the records (lines not starting with #). A GVCF with none is empty.
        n=$(gzip -dc "$gvcf" | awk '!/^#/ { n++ } END { print n + 0 }')
        (( n > 0 )) || die "$id: GVCF has no records"
        log "$id: GVCF written, ${n} records"
    done < <(rows "$SHEET" "$SAMPLE")
}
