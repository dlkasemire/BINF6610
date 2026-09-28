#!/usr/bin/env bash
# run_pipeline.sh: Ten-stage variant-calling pipeline
# usage: ./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# All messages go to stderr (>&2), so stdout stays clean for data
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# ---------- arguments ----------
[[ $# -ge 2 ]] || die "usage: $0 <samplesheet.csv> <outdir> [last-stage]"
SHEET=$1
OUTDIR=$2
LAST=${3:-publish}      # no third argument which means run everything

log "samplesheet=${SHEET} outdir=${OUTDIR} last=${LAST}"

# ---------- configuration ----------
# Find the folder this script lives in, so conf/ is found from anywhere
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/conf/pipeline.env"

log "REF=${REF} REGION=${REGION} THREADS=${THREADS}"

# ---------- output folders ----------
# Everything the run makes lives under OUTDIR
QC="${OUTDIR}/qc_raw"; TRIM="${OUTDIR}/trim"; ALN="${OUTDIR}/align"
GVCF="${OUTDIR}/gvcf"; LOG="${OUTDIR}/logs"; RES="${OUTDIR}/results"
mkdir -p "$QC" "$TRIM" "$ALN" "$GVCF" "$LOG" "$RES"

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
# 1 · qc_raw — FastQC on the reads as they arrived
#=============================================================================
stage_qc_raw() {
    local id cond rep lt r1 r2 base
    while IFS=, read -r id cond rep lt r1 r2; do
        fastqc -q -o "$QC" "$r1" > "${LOG}/${id}.fastqc.log" 2>&1
        [[ "$lt" != paired ]] || fastqc -q -o "$QC" "$r2" >> "${LOG}/${id}.fastqc.log" 2>&1

        # fastqc can exit 0 and write nothing. Ask the disk.
        base=$(basename "$r1" .fastq.gz)
        [[ -s "${QC}/${base}_fastqc.zip" ]] || die "$id: fastqc produced no report for R1"
        # Check R2's report too, when there is one
        if [[ "$lt" == paired ]]; then
            base=$(basename "$r2" .fastq.gz)
            [[ -s "${QC}/${base}_fastqc.zip" ]] || die "$id: fastqc produced no report for R2"
        fi
        log "$id: qc done"
    done < <(tail -n +2 "$SHEET")
}

#=============================================================================
# 2 · trim — adapters and low-quality tails
#=============================================================================
stage_trim() {
    local id cond rep lt r1 r2 n
    while IFS=, read -r id cond rep lt r1 r2; do
        if [[ "$lt" == paired ]]; then
            fastp -i "$r1" -I "$r2" \
                  -o "${TRIM}/${id}_R1.fastq.gz" -O "${TRIM}/${id}_R2.fastq.gz" \
                  -j "${LOG}/${id}.fastp.json" -h "${LOG}/${id}.fastp.html" \
                  2> "${LOG}/${id}.fastp.log"
        else
            fastp -i "$r1" -o "${TRIM}/${id}_R1.fastq.gz" \
                  -j "${LOG}/${id}.fastp.json" -h "${LOG}/${id}.fastp.html" \
                  2> "${LOG}/${id}.fastp.log"
        fi

        # trimming can only remove reads. Zero left means something is wrong.
        n=$(gzip -dc "${TRIM}/${id}_R1.fastq.gz" | wc -l)
        (( n > 0 )) || die "$id: nothing survived trimming"
        log "$id: trimmed to $(( n / 4 )) reads"
    done < <(tail -n +2 "$SHEET")
}

#=============================================================================
# 3 · align — BWA-MEM straight into a sorted BAM
#=============================================================================
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
        fi | samtools sort -@ 2 -o "$bam" 2> "${LOG}/${id}.sort.log"

        [[ -s "$bam" ]] || die "$id: no BAM written"
        total=$(samtools view -c "$bam")
        mapped=$(samtools view -c -F 4 "$bam")
        (( total > 0 )) || die "$id: BAM has no reads"
        rate=$(awk -v m="$mapped" -v t="$total" 'BEGIN { printf "%.1f", 100 * m / t }')
        log "$id: ${rate}% of ${total} reads aligned"
        awk -v r="$rate" 'BEGIN { exit !(r > 50) }' \
            || die "$id: alignment rate ${rate}% — wrong reference, or the mates are mixed up"
    done < <(tail -n +2 "$SHEET")
}

#=============================================================================
# 4 · postprocess — mark duplicates, index, flagstat
#=============================================================================
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
    done < <(tail -n +2 "$SHEET")
}

#=============================================================================
# 5 · quantify — per-sample variant calling into a GVCF
#=============================================================================
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
    done < <(tail -n +2 "$SHEET")
}

#=============================================================================
# 6 · merge — joint genotyping across every sample
#
# Needs every sample's GVCF
#=============================================================================
stage_merge() {
    local id cond rep lt r1 r2
    local db="${OUTDIR}/genomicsdb"
    local vcf="${RES}/cohort.vcf.gz"
    local inputs=()

    # one -V per sample, read from the samplesheet -- no sample named in the code
    while IFS=, read -r id cond rep lt r1 r2; do
        [[ -s "${GVCF}/${id}.g.vcf.gz" ]] || die "$id: no GVCF from stage 5"
        inputs+=(-V "${GVCF}/${id}.g.vcf.gz")
    done < <(tail -n +2 "$SHEET")

    # GenomicsDBImport refuses to write into a folder that already exists,
    # so clear the one from any earlier run first
    rm -rf "$db"
    gatk GenomicsDBImport "${inputs[@]}" --genomicsdb-workspace-path "$db" -L "$REGION" \
         > "${LOG}/genomicsdbimport.log" 2>&1 \
         || die "GenomicsDBImport failed — see ${LOG}/genomicsdbimport.log"

    gatk GenotypeGVCFs -R "$REF" -V "gendb://${db}" -O "$vcf" \
         > "${LOG}/genotypegvcfs.log" 2>&1 \
         || die "GenotypeGVCFs failed — see ${LOG}/genotypegvcfs.log"

    [[ -s "$vcf" ]]       || die "joint genotyping wrote no VCF"
    [[ -s "${vcf}.tbi" ]] || die "cohort VCF has no index"

    # The column count must equal the sample count. If it does not, a sample
    # was dropped somewhere above and nothing has said so.
    local n_cols n_samples n_vars
    n_cols=$(gzip -dc "$vcf" | awk -F'\t' '/^#CHROM/ { n = NF - 9 } END { print n + 0 }')
    n_samples=$(awk -F, 'NR>1' "$SHEET" | wc -l)
    (( n_cols == n_samples )) || die "cohort VCF has ${n_cols} sample columns for ${n_samples} samples"

    n_vars=$(gzip -dc "$vcf" | awk '!/^#/ { n++ } END { print n + 0 }')
    (( n_vars > 0 )) || die "cohort VCF has no variants"
    log "joint genotyping: ${n_vars} variants x ${n_cols} samples"
}

#=============================================================================
# 7 · analyze — hard-filter the cohort VCF
#=============================================================================
stage_analyze() {
    local vcf="${RES}/cohort.vcf.gz"
    local filtered="${RES}/cohort.filtered.vcf.gz"

    # Filtering LABELS variants in the FILTER column; it does not remove them.
    # Thresholds are GATK's recommended hard-filter starting points.
    gatk VariantFiltration -R "$REF" -V "$vcf" -O "$filtered" \
         --filter-expression "QD < 2.0"   --filter-name QD2 \
         --filter-expression "QUAL < 30.0" --filter-name QUAL30 \
         --filter-expression "FS > 60.0"  --filter-name FS60 \
         --filter-expression "SOR > 3.0"  --filter-name SOR3 \
         --filter-expression "MQ < 40.0"  --filter-name MQ40 \
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

#=============================================================================
# 8 · qc_report — MultiQC over every log this run produced
#=============================================================================
stage_qc_report() {
    multiqc -q -f -o "$RES" "$QC" "$LOG" > "${LOG}/multiqc.log" 2>&1 \
        || die "MultiQC failed — see ${LOG}/multiqc.log"
    [[ -s "${RES}/multiqc_report.html" ]] || die "multiqc produced no report"
    log "QC report written"
}

#=============================================================================
# 9 · publish — the contract boundary: tidy TSVs + run_info.tsv
#=============================================================================
stage_publish() {
    local id cond rep lt r1 r2
    local filtered="${RES}/cohort.filtered.vcf.gz"
    [[ -s "$filtered" ]] || die "no filtered VCF from stage 7"

    # --- samples.tsv: who is in which group, with the synthetic label marked ---
    printf 'sample_id\tcondition\tcondition_is_synthetic\treplicate\tlibrary_type\n' > "${RES}/samples.tsv"
    while IFS=, read -r id cond rep lt r1 r2; do
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$cond" "$CONDITION_IS_SYNTHETIC" "$rep" "$lt" >> "${RES}/samples.tsv"
    done < <(tail -n +2 "$SHEET")

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

    # --- how many samples the samplesheet lists (every line except the header) ---
    local n_samples
    n_samples=$(awk -F, 'NR > 1' "$SHEET" | wc -l)
    n_samples=$(( n_samples ))     # strip the spaces a Mac's wc puts in front

    # --- which code produced this: the commit, plus -dirty if files changed since ---
    local sha
    if sha=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null); then
        git -C "$SCRIPT_DIR" diff --quiet HEAD 2>/dev/null || sha="${sha}-dirty"
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

    # manifest.json; written by the course's script, from everything in results/
    bash "${HERE}/lib/write_manifest.sh" "${RES}" "${SHEET}" "${REF}" "${REGION}"
    [[ -s "${RES}/manifest.json" ]] || die "no manifest.json written"

    log "published: ${n_vcf} variants (${n_pass} PASS), ${n_samples} samples, git ${sha}"
    log "results in ${RES}:"
    ls -1 "$RES" >&2
}

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
