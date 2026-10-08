// Stage 8 · qc_report — MultiQC over every report the run produced.
process MULTIQC {
    tag "cohort"
    container params.containers.multiqc

    input:
    path reports              // FastQC zips, fastp JSONs, flagstat and MarkDuplicates metrics

    output:
    path "multiqc_report.html"

    script:
    """
    multiqc -f . > multiqc.log 2>&1
    """
}
