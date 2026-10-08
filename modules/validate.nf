// Stage 0 · validate — check the samplesheet, every FASTQ and the reference
// before anything computes. Runs once per run; every sample waits for it.
process VALIDATE {
    tag "samplesheet"
    container params.containers.tools

    input:
    path samplesheet          // the samplesheet itself
    path fastqs               // every FASTQ, linked into this task's folder by name
    path ref                  // the FASTA
    path ref_index            // its .fai and the BWA index files
    path ref_dict             // its .dict

    output:
    path samplesheet, emit: sheet

    script:
    """
    validate_samplesheet.sh ${samplesheet} ${ref}
    """
}
