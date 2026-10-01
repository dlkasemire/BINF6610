# shellcheck shell=bash
set -euo pipefail   # already set by the driver that sources this; stated here so the file says so itself
# 7 · analyze — hard-filter the cohort VCF.
stage_analyze() {
    local vcf="${RES}/cohort.vcf.gz"
    local filtered="${RES}/cohort.filtered.vcf.gz"

    # Filtering LABELS variants in the FILTER column; it does not remove them.
    # Thresholds are GATK's recommended hard-filter starting points.
    gatk VariantFiltration -R "$REF" -V "$vcf" -O "$filtered" \
         --filter-expression "QD < 2.0"    --filter-name QD2 \
         --filter-expression "QUAL < 30.0" --filter-name QUAL30 \
         --filter-expression "FS > 60.0"   --filter-name FS60 \
         --filter-expression "SOR > 3.0"   --filter-name SOR3 \
         --filter-expression "MQ < 40.0"   --filter-name MQ40 \
         > "${LOG}/variantfiltration.log" 2>&1 \
         || die "VariantFiltration failed — see ${LOG}/variantfiltration.log"

    [[ -s "$filtered" ]]       || die "filtering wrote no VCF"
    [[ -s "${filtered}.tbi" ]] || die "filtered VCF has no index"

    # Filtering only labels, so the record count must not change.
    local n_in n_out n_pass
    n_in=$(gzip -dc "$vcf" | awk '!/^#/ { n++ } END { print n + 0 }')
    n_out=$(gzip -dc "$filtered" | awk '!/^#/ { n++ } END { print n + 0 }')
    (( n_in == n_out )) || die "filtering changed the record count: ${n_in} in, ${n_out} out"

    n_pass=$(gzip -dc "$filtered" | awk -F'\t' '!/^#/ && $7 == "PASS" { n++ } END { print n + 0 }')
    log "filtering: ${n_pass} of ${n_out} variants PASS"
}
