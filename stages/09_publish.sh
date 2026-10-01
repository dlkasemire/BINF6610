# shellcheck shell=bash
set -euo pipefail   # already set by the driver that sources this; stated here so the file says so itself
# 9 · publish — the contract boundary: tidy TSVs, run_info.tsv, manifest.json.
stage_publish() {
    local id cond rep lt r1 r2
    local filtered="${RES}/cohort.filtered.vcf.gz"
    [[ -s "$filtered" ]] || die "no filtered VCF from stage 7"

    # --- samples.tsv: who is in which group, with the synthetic label marked ---
    printf 'sample_id\tcondition\tcondition_is_synthetic\treplicate\tlibrary_type\n' > "${RES}/samples.tsv"
    while IFS=, read -r id cond rep lt r1 r2; do
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$cond" "$CONDITION_IS_SYNTHETIC" "$rep" "$lt" >> "${RES}/samples.tsv"
    done < <(rows "$SHEET")

    # --- variants.tsv: one row per variant, one genotype column per sample ---
    gzip -dc "$filtered" | awk -F'\t' '
        /^##/     { next }
        /^#CHROM/ { printf "chrom\tpos\tref\talt\tqual\tfilter"
                    for (i = 10; i <= NF; i++) printf "\t%s", $i
                    printf "\n"; next }
                  { printf "%s\t%s\t%s\t%s\t%s\t%s", $1, $2, $4, $5, $6, $7
                    for (i = 10; i <= NF; i++) { split($i, f, ":"); printf "\t%s", f[1] }
                    printf "\n" }
    ' > "${RES}/variants.tsv"

    local n_vcf n_tsv n_pass
    n_vcf=$(gzip -dc "$filtered" | awk '!/^#/ { n++ } END { print n + 0 }')
    n_tsv=$(awk 'NR > 1 { n++ } END { print n + 0 }' "${RES}/variants.tsv")
    (( n_vcf == n_tsv )) || die "variants.tsv has ${n_tsv} rows for ${n_vcf} VCF records"
    n_pass=$(awk -F'\t' 'NR > 1 && $6 == "PASS" { n++ } END { print n + 0 }' "${RES}/variants.tsv")

    # --- how many samples the samplesheet lists ---
    local n_samples
    n_samples=$(rows "$SHEET" | wc -l)
    n_samples=$(( n_samples ))     # strip the spaces a Mac's wc puts in front

    # --- which code produced this: the commit, plus -dirty if files changed since ---
    local sha
    if sha=$(git -C "$PIPE_DIR" rev-parse --short HEAD 2>/dev/null); then
        git -C "$PIPE_DIR" diff --quiet HEAD 2>/dev/null || sha="${sha}-dirty"
    else
        sha="unknown"
    fi

    # --- tool versions: record what each tool says about itself ---
    local v_fastqc v_fastp v_bwa v_samtools v_gatk v_multiqc
    v_fastqc=$(fastqc --version 2>&1 | awk 'NR == 1')
    v_fastp=$(fastp --version 2>&1 | awk 'NR == 1')
    v_bwa=$( { bwa 2>&1 || true; } | awk '/^Version/ { print $2 }')
    v_samtools=$(samtools --version 2>&1 | awk 'NR == 1')
    v_gatk=$(gatk --version 2>&1 | awk '/Genome Analysis Toolkit/ { v = $NF } END { print v }')
    v_multiqc=$(multiqc --version 2>&1 | awk 'NR == 1')

    # --- run_info.tsv: what produced this, in the demo's name<tab>value format ---
    {
        printf 'run_finished\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'git_commit\t%s\n'   "$sha"
        printf 'samplesheet\t%s\n'  "$SHEET"
        printf 'reference\t%s\n'    "$REF"
        printf 'region\t%s\n'       "$REGION"
        printf 'n_samples\t%d\n'    "$n_samples"
        printf 'n_variants\t%d\n'   "$n_vcf"
        printf 'n_pass\t%d\n'       "$n_pass"
        printf 'condition_is_synthetic\t%s\n' "$CONDITION_IS_SYNTHETIC"
        printf 'fastqc\t%s\n'   "$v_fastqc"
        printf 'fastp\t%s\n'    "$v_fastp"
        printf 'bwa\t%s\n'      "$v_bwa"
        printf 'samtools\t%s\n' "$v_samtools"
        printf 'gatk\t%s\n'     "$v_gatk"
        printf 'multiqc\t%s\n'  "$v_multiqc"
    } > "${RES}/run_info.tsv"
    [[ -s "${RES}/run_info.tsv" ]] || die "no run_info.tsv written"

    # --- manifest.json: written by the course's script, from everything in results/ ---
    bash "${PIPE_DIR}/lib/write_manifest.sh" "${RES}" "${SHEET}" "${REF}" "${REGION}"
    [[ -s "${RES}/manifest.json" ]] || die "no manifest.json written"

    log "published: ${n_vcf} variants (${n_pass} PASS), ${n_samples} samples, git ${sha}"
    log "results in ${RES}:"
    ls -1 "$RES" >&2
}
