// Stage 3 · align — BWA-MEM straight into a sorted BAM.
process BWA_MEM {
    tag "${meta.id}"
    container params.containers.bwa

    input:
    tuple val(meta), path(reads)
    path ref                  // the FASTA
    path ref_index            // its .fai and the BWA index files

    output:
    tuple val(meta), path("${meta.id}.bam"), emit: bam

    script:
    // SM becomes the sample's column name in the VCF, so it must be the sample id.
    // ${reads} is every file of the sample: one for single-end, two for paired.
    """
    bwa mem -t ${task.cpus} \\
        -R '@RG\\tID:${meta.id}\\tSM:${meta.id}\\tLB:${meta.id}\\tPL:ILLUMINA' \\
        ${ref} ${reads} 2> ${meta.id}.bwa.log \\
      | samtools sort -@ ${task.cpus} -T ./sort.${meta.id} -o ${meta.id}.bam 2> ${meta.id}.sort.log

    # BWA prints no alignment rate, so count it from the BAM.
    total=\$(samtools view -c ${meta.id}.bam)
    mapped=\$(samtools view -c -F 4 ${meta.id}.bam)
    [ "\$total" -gt 0 ] || { echo "${meta.id}: BAM has no reads" >&2; exit 1; }
    awk -v m="\$mapped" -v t="\$total" 'BEGIN { exit !(100 * m / t > 50) }' \\
        || { echo "${meta.id}: under 50% aligned — wrong reference, or the mates are mixed up" >&2; exit 1; }
    """
}
