# Snakefile: the ten-stage variant-calling pipeline, in Snakemake.
import csv
import os
import re

configfile: "config.yaml"

# A mistyped --config key (regoin=) would be added without a word. Refuse it.
KNOWN = {"samplesheet", "ref", "region", "outdir", "platform", "executor", "containers"}
unknown = sorted(set(config) - KNOWN)
if unknown:
    raise ValueError(f"unknown config key(s): {', '.join(unknown)}")

PIPELINE = {"name": "variant-call", "version": "1.0.0"}
OUT = config["outdir"]
BIN = os.path.join(workflow.basedir, "bin")       # bin/ is not on the PATH: call scripts by their path
IMAGES = {name: f"docker://{image}" for name, image in config["containers"].items()}

REF = config["ref"]                                                       # the FASTA
REF_FAI = REF + ".fai"
REF_BWA = [REF + ext for ext in (".amb", ".ann", ".bwt", ".pac", ".sa")]  # bwa's index
REF_DICT = os.path.splitext(REF)[0] + ".dict"                             # smoke.dict, not smoke.fa.dict

SHEET = config["samplesheet"]
with open(SHEET) as fh:
    ROWS = list(csv.DictReader(fh))
SAMPLES = [row["sample_id"] for row in ROWS]
PAIRED = [row["sample_id"] for row in ROWS if row["library_type"] == "paired"]
SINGLE = [row["sample_id"] for row in ROWS if row["library_type"] == "single"]


def resolve(path):
    return path if os.path.isabs(path) else os.path.join(os.path.dirname(SHEET), path)


READS = {
    row["sample_id"]: [resolve(row["r1_fastq"])]
    + ([resolve(row["r2_fastq"])] if row["library_type"] == "paired" else [])
    for row in ROWS
}


def one_of(names):
    """A wildcard pattern matching exactly
    these sample names, or nothing at all."""
    return "|".join(map(re.escape, names)) \
        if names else "(?!)"


# ---------- the files the run must end with ----------
rule all:
    input:
        f"{OUT}/cohort.filtered.vcf.gz",
        f"{OUT}/variants.tsv",
        f"{OUT}/multiqc_report.html",
        f"{OUT}/samples.tsv",
        f"{OUT}/manifest.json",


# ---------- 0 · validate: once per run; every sample waits for its file ----------
rule validate:
    input:
        sheet=SHEET,
        fastqs=[fq for reads in READS.values() for fq in reads],
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
        ref_dict=REF_DICT,
    output:
        "work/validate/samplesheet.csv",
    log:
        "logs/validate.log",
    container: IMAGES["tools"]
    shell:
        "({BIN}/validate_samplesheet.sh {input.sheet} {input.ref} && cp {input.sheet} {output}) 2> {log}"


# ---------- 1 · qc_raw: FastQC on the raw reads, per sample ----------
rule fastqc:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output,
    output:
        directory("work/fastqc/{sample}"),
    log:
        "logs/fastqc/{sample}.log",
    container: IMAGES["fastqc"]
    shell:
        "(mkdir -p {output} && fastqc -q -o {output} {input.reads}) > {log} 2>&1"


# ---------- 2 · trim: fastp, two rules with the same output names ----------
# A paired sample makes two trimmed files and a single-end one makes one.
# wildcard_constraints send each sample to exactly one of the two rules.
rule fastp_paired:
    input:
        r1=lambda wc: READS[wc.sample][0],
        r2=lambda wc: READS[wc.sample][1],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        r2="work/trim/{sample}_R2.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(PAIRED),
    log:
        "logs/fastp/{sample}.log",
    container: IMAGES["fastp"]
    shell:
        "(fastp -i {input.r1} -I {input.r2} -o {output.r1} -O {output.r2}"
        " -j {output.json} -h {output.html}"
        " && n=$(gzip -dc {output.r1} | wc -l) && [ $n -gt 0 ]) 2> {log}"


rule fastp_single:
    input:
        r1=lambda wc: READS[wc.sample][0],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(SINGLE),
    log:
        "logs/fastp/{sample}.log",
    container: IMAGES["fastp"]
    shell:
        "(fastp -i {input.r1} -o {output.r1}"
        " -j {output.json} -h {output.html}"
        " && n=$(gzip -dc {output.r1} | wc -l) && [ $n -gt 0 ]) 2> {log}"


# ---------- 3 · align: BWA-MEM straight into a sorted BAM ----------
def trimmed(wildcards):
    s = wildcards.sample
    if s in PAIRED:
        return [f"work/trim/{s}_R1.trim.fastq.gz", f"work/trim/{s}_R2.trim.fastq.gz"]
    return [f"work/trim/{s}_R1.trim.fastq.gz"]


rule bwa_mem:
    input:
        reads=trimmed,
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
    output:
        bam="work/align/{sample}.bam",
    params:
        # SM becomes the sample's column name in the VCF
        rg=lambda wc: f"@RG\\tID:{wc.sample}\\tSM:{wc.sample}\\tLB:{wc.sample}\\tPL:ILLUMINA",
    threads: 8
    log:
        "logs/bwa_mem/{sample}.log",
    container: IMAGES["bwa"]
    shell:
        r"""
        (bwa mem -t {threads} -R '{params.rg}' {input.ref} {input.reads} \
            | samtools sort -T work/align/{wildcards.sample}.sorttmp -o {output.bam} -
        total=$(samtools view -c {output.bam})
        mapped=$(samtools view -c -F 4 {output.bam})
        echo "{wildcards.sample}: $mapped of $total reads aligned"
        awk -v m=$mapped -v t=$total 'BEGIN {{ exit !(t > 0 && 100 * m / t > 50) }}') > {log} 2>&1
        """


# ---------- 4 · postprocess: mark duplicates, index, flagstat ----------
rule markduplicates:
    input:
        bam="work/align/{sample}.bam",
    output:
        bam="work/dedup/{sample}.dedup.bam",
        bai="work/dedup/{sample}.dedup.bam.bai",
        metrics="work/dedup/{sample}.markdup.txt",
        flagstat="work/dedup/{sample}.flagstat.txt",
    log:
        "logs/markduplicates/{sample}.log",
    container: IMAGES["gatk"]
    shell:
        "(gatk MarkDuplicates -I {input.bam} -O {output.bam} -M {output.metrics}"
        " && samtools index {output.bam}"
        " && samtools flagstat {output.bam} > {output.flagstat}) > {log} 2>&1"


# ---------- 5 · quantify: HaplotypeCaller into a GVCF, per sample ----------
rule haplotypecaller:
    input:
        bam="work/dedup/{sample}.dedup.bam",
        bai="work/dedup/{sample}.dedup.bam.bai",
        ref=REF,
        ref_fai=REF_FAI,
        ref_dict=REF_DICT,
    output:
        gvcf="work/gvcf/{sample}.g.vcf.gz",
        tbi="work/gvcf/{sample}.g.vcf.gz.tbi",
    params:
        region=config["region"],
    threads: 8
    log:
        "logs/haplotypecaller/{sample}.log",
    container: IMAGES["gatk"]
    shell:
        "gatk HaplotypeCaller -R {input.ref} -I {input.bam} -O {output.gvcf}"
        " -ERC GVCF -L {params.region} --native-pair-hmm-threads {threads} > {log} 2>&1"


# ---------- 6 · merge: joint genotyping, once, after every sample ----------
rule joint_genotype:
    input:
        gvcfs=expand("work/gvcf/{sample}.g.vcf.gz", sample=SAMPLES),
        tbis=expand("work/gvcf/{sample}.g.vcf.gz.tbi", sample=SAMPLES),
        ref=REF,
        ref_fai=REF_FAI,
        ref_dict=REF_DICT,
    output:
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
    params:
        variants=lambda wc, input: " ".join(f"-V {g}" for g in input.gvcfs),
        region=config["region"],
        n=len(SAMPLES),
    log:
        "logs/joint_genotype.log",
    container: IMAGES["gatk"]
    shell:
        r"""
        # GenomicsDB writes many small files: keep it on the node's own disk (mktemp -d),
        # not in work/, which on Explorer is the network home folder.
        (tmp=$(mktemp -d)
        trap 'rm -rf $tmp' EXIT
        gatk GenomicsDBImport {params.variants} --genomicsdb-workspace-path $tmp/genomicsdb -L {params.region}
        gatk GenotypeGVCFs -R {input.ref} -V gendb://$tmp/genomicsdb -O {output.vcf}
        n_cols=$(gzip -dc {output.vcf} | awk -F'\t' '/^#CHROM/ {{ n = NF - 9 }} END {{ print n + 0 }}')
        echo "cohort VCF has $n_cols sample columns for {params.n} samples"
        [ $n_cols -eq {params.n} ]) > {log} 2>&1
        """


# ---------- 7 · analyze: hard filters; labels records, removes none ----------
rule filter:
    input:
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
        ref=REF,
        ref_fai=REF_FAI,
        ref_dict=REF_DICT,
    output:
        vcf=f"{OUT}/cohort.filtered.vcf.gz",
        tbi=f"{OUT}/cohort.filtered.vcf.gz.tbi",
        table=f"{OUT}/variants.tsv",
    log:
        "logs/filter.log",
    container: IMAGES["gatk"]
    shell:
        r"""
        (gatk VariantFiltration -R {input.ref} -V {input.vcf} -O {output.vcf} \
            --filter-expression "QD < 2.0"    --filter-name QD2 \
            --filter-expression "QUAL < 30.0" --filter-name QUAL30 \
            --filter-expression "FS > 60.0"   --filter-name FS60 \
            --filter-expression "SOR > 3.0"   --filter-name SOR3 \
            --filter-expression "MQ < 40.0"   --filter-name MQ40
        n_in=$(gzip -dc {input.vcf} | awk '!/^#/ {{ n++ }} END {{ print n + 0 }}')
        n_out=$(gzip -dc {output.vcf} | awk '!/^#/ {{ n++ }} END {{ print n + 0 }}')
        echo "filtering: $n_in records in, $n_out out"
        [ $n_in -eq $n_out ]
        printf 'chrom\tpos\tref\talt\tqual\tfilter\n' > {output.table}
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\n' {output.vcf} >> {output.table}) > {log} 2>&1
        """


# ---------- 8 · qc_report: MultiQC over the reports, not over . ----------
rule multiqc:
    input:
        expand("work/fastqc/{sample}", sample=SAMPLES),
        expand("work/trim/{sample}.fastp.json", sample=SAMPLES),
        expand("work/dedup/{sample}.flagstat.txt", sample=SAMPLES),
        expand("work/dedup/{sample}.markdup.txt", sample=SAMPLES),
    output:
        f"{OUT}/multiqc_report.html",
    log:
        "logs/multiqc.log",
    container: IMAGES["multiqc"]
    shell:
        "(multiqc -q -f -o work/multiqc {input}"
        " && cp work/multiqc/multiqc_report.html {output}) > {log} 2>&1"


# ---------- 9 · publish: the course's rule ----------
PUBLISH_SHEET = rules.validate.output
PUBLISH_RESULTS = [*rules.filter.output, *rules.multiqc.output]
include: "rules/publish.smk"
