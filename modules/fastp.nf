// Stage 2 · trim — adapters and low-quality tails.
process FASTP {
    tag "${meta.id}"
    container params.containers.fastp

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path('*.trim.fastq.gz'), emit: reads   // to BWA_MEM
    path "${meta.id}.fastp.json",             emit: json    // to MULTIQC

    script:
    // meta.single_end chooses fastp's single-end or paired command
    def inputs  = meta.single_end ? "-i ${reads}" : "-i ${reads[0]} -I ${reads[1]}"
    def outputs = meta.single_end ? "-o ${meta.id}_R1.trim.fastq.gz"
                                  : "-o ${meta.id}_R1.trim.fastq.gz -O ${meta.id}_R2.trim.fastq.gz"
    """
    fastp ${inputs} ${outputs} \\
          -j ${meta.id}.fastp.json -h ${meta.id}.fastp.html \\
          2> ${meta.id}.fastp.log

    # trimming can only remove reads. Zero left means something is wrong.
    n=\$(gzip -dc ${meta.id}_R1.trim.fastq.gz | wc -l)
    [ "\$n" -gt 0 ] || { echo "${meta.id}: nothing survived trimming" >&2; exit 1; }
    """
}
