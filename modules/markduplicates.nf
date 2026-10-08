// Stage 4 · postprocess — mark duplicates, index, flagstat.
process MARKDUPLICATES {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.id}.dedup.bam"), path("${meta.id}.dedup.bam.bai"), emit: bam
    path "${meta.id}.flagstat.txt", emit: flagstat     // to MULTIQC
    path "${meta.id}.markdup.txt",  emit: metrics      // to MULTIQC

    script:
    """
    gatk MarkDuplicates -I ${bam} -O ${meta.id}.dedup.bam -M ${meta.id}.markdup.txt \\
        > ${meta.id}.markdup.log 2>&1
    samtools index ${meta.id}.dedup.bam
    samtools flagstat ${meta.id}.dedup.bam > ${meta.id}.flagstat.txt
    """
}
