// Stage 5 · quantify — per-sample variant calling into a GVCF.
process HAPLOTYPECALLER {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam), path(bai)
    path ref
    path ref_index
    path ref_dict

    output:
    // plain paths: both go only to JOINT_GENOTYPE, through collect()
    path "${meta.id}.g.vcf.gz",     emit: gvcf
    path "${meta.id}.g.vcf.gz.tbi", emit: tbi

    script:
    """
    gatk HaplotypeCaller -R ${ref} -I ${bam} -O ${meta.id}.g.vcf.gz \\
        -ERC GVCF -L ${params.region} \\
        --native-pair-hmm-threads ${task.cpus} \\
        > ${meta.id}.haplotypecaller.log 2>&1
    """
}
