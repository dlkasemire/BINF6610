// Stage 1 · qc_raw — FastQC on the reads as they arrived.
process FASTQC {
    tag "${meta.id}"
    container params.containers.fastqc

    input:
    tuple val(meta), path(reads)

    output:
    path "*_fastqc.zip", emit: zip      // a plain path: it goes only to MULTIQC, through collect()

    script:
    """
    fastqc -q -t ${task.cpus} -o . ${reads} > ${meta.id}.fastqc.log 2>&1
    """
}
