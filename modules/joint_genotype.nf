// Stage 6 · merge — joint genotyping across every sample.
// It receives every sample's GVCF at once (collect() in main.nf), so it cannot
// start until the last sample's HaplotypeCaller has finished.
process JOINT_GENOTYPE {
    tag "cohort"
    container params.containers.gatk

    input:
    path gvcfs                // every sample's .g.vcf.gz
    path tbis                 // and its .tbi: GATK reads a GVCF only with its index beside it
    path ref
    path ref_index
    path ref_dict

    output:
    tuple path("cohort.vcf.gz"), path("cohort.vcf.gz.tbi"), emit: vcf

    script:
    def files = gvcfs instanceof List ? gvcfs : [gvcfs]
    def vs    = files.collect { "-V ${it}" }.join(' ')
    """
    # The GenomicsDB workspace goes on the node's own disk, as in week 2,
    # and the trap removes it however the task ends.
    tmp=\$(mktemp -d)
    trap 'rm -rf "\$tmp"' EXIT

    gatk GenomicsDBImport ${vs} --genomicsdb-workspace-path "\$tmp/genomicsdb" \\
        -L ${params.region} > genomicsdbimport.log 2>&1
    gatk GenotypeGVCFs -R ${ref} -V "gendb://\$tmp/genomicsdb" -L ${params.region} \\
        -O cohort.vcf.gz > genotypegvcfs.log 2>&1

    # One column per sample, or a sample was dropped and nothing said so.
    n_cols=\$(bcftools query -l cohort.vcf.gz | wc -l)
    [ "\$n_cols" -eq ${files.size()} ] \\
        || { echo "cohort VCF has \$n_cols sample columns for ${files.size()} samples" >&2; exit 1; }
    """
}
