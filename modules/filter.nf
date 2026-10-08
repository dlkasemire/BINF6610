// Stage 7 · analyze — hard-filter the cohort VCF, and write variants.tsv.
process FILTER {
    tag "cohort"
    container params.containers.gatk

    input:
    tuple path(vcf), path(tbi)
    path ref
    path ref_index
    path ref_dict

    output:
    path "cohort.filtered.vcf.gz*", emit: vcf      // the VCF and its .tbi
    path "variants.tsv",            emit: table

    script:
    """
    # Filtering LABELS variants in the FILTER column; it does not remove them.
    gatk VariantFiltration -R ${ref} -V ${vcf} -O cohort.filtered.vcf.gz \\
         --filter-expression "QD < 2.0"    --filter-name QD2 \\
         --filter-expression "QUAL < 30.0" --filter-name QUAL30 \\
         --filter-expression "FS > 60.0"   --filter-name FS60 \\
         --filter-expression "SOR > 3.0"   --filter-name SOR3 \\
         --filter-expression "MQ < 40.0"   --filter-name MQ40 \\
         > variantfiltration.log 2>&1

    # Filtering only labels, so the record count must not change.
    n_in=\$(bcftools view -H ${vcf} | wc -l)
    n_out=\$(bcftools view -H cohort.filtered.vcf.gz | wc -l)
    [ "\$n_in" -eq "\$n_out" ] \\
        || { echo "filtering changed the record count: \$n_in in, \$n_out out" >&2; exit 1; }

    printf 'chrom\\tpos\\tref\\talt\\tqual\\tfilter\\n' > variants.tsv
    bcftools query -f '%CHROM\\t%POS\\t%REF\\t%ALT\\t%QUAL\\t%FILTER\\n' cohort.filtered.vcf.gz >> variants.tsv
    """
}
