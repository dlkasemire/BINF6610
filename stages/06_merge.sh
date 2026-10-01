# shellcheck shell=bash
set -euo pipefail   # already set by the driver that sources this; stated here so the file says so itself
# 6 · merge — joint genotyping across every sample.
#
# THIS IS THE BARRIER. It needs every sample's GVCF, so it reads the whole
# samplesheet, never one sample. On the cluster, the scheduler's afterok
# dependency is what guarantees every array task has finished first.
stage_merge() {
    local id cond rep lt r1 r2
    
    # The workspace is written by GenomicsDBImport and read back by GenotypeGVCFs.
    local db="${TMPDIR:-/tmp}/genomicsdb"	
    local vcf="${RES}/cohort.vcf.gz"
    local inputs=()

    # one -V per sample, read from the samplesheet -- no sample named in the code
    while IFS=, read -r id cond rep lt r1 r2; do
        [[ -s "${GVCF}/${id}.g.vcf.gz" ]] || die "$id: no GVCF from stage 5"
        inputs+=(-V "${GVCF}/${id}.g.vcf.gz")
    done < <(rows "$SHEET")

    # GenomicsDBImport refuses to write into a folder that already exists,
    # so clear the one from any earlier run first
    rm -rf "$db"
    gatk GenomicsDBImport "${inputs[@]}" --genomicsdb-workspace-path "$db" -L "$REGION" \
         > "${LOG}/genomicsdbimport.log" 2>&1 \
         || die "GenomicsDBImport failed — see ${LOG}/genomicsdbimport.log"

    gatk GenotypeGVCFs -R "$REF" -V "gendb://${db}" -L "$REGION" -O "$vcf" \
         > "${LOG}/genotypegvcfs.log" 2>&1 \
         || die "GenotypeGVCFs failed — see ${LOG}/genotypegvcfs.log"

    [[ -s "$vcf" ]]       || die "joint genotyping wrote no VCF"
    [[ -s "${vcf}.tbi" ]] || die "cohort VCF has no index"

    # The column count must equal the sample count. If it does not, a sample
    # was dropped somewhere above and nothing has said so.
    local n_cols n_samples n_vars
    n_cols=$(gzip -dc "$vcf" | awk -F'\t' '/^#CHROM/ { n = NF - 9 } END { print n + 0 }')
    n_samples=$(rows "$SHEET" | wc -l)
    (( n_cols == n_samples )) || die "cohort VCF has ${n_cols} sample columns for ${n_samples} samples"

    n_vars=$(gzip -dc "$vcf" | awk '!/^#/ { n++ } END { print n + 0 }')
    (( n_vars > 0 )) || die "cohort VCF has no variants"
    log "joint genotyping: ${n_vars} variants x ${n_cols} samples"
}
