// main.nf — the variant-calling pipeline: reads the samplesheet and connects
// the ten processes. Nextflow works out the order from what feeds what.
include { VALIDATE        } from './modules/validate'
include { FASTQC          } from './modules/fastqc'
include { FASTP           } from './modules/fastp'
include { BWA_MEM         } from './modules/bwa_mem'
include { MARKDUPLICATES  } from './modules/markduplicates'
include { HAPLOTYPECALLER } from './modules/haplotypecaller'
include { JOINT_GENOTYPE  } from './modules/joint_genotype'
include { FILTER          } from './modules/filter'
include { MULTIQC         } from './modules/multiqc'
include { PUBLISH         } from './modules/publish'

workflow {
    main:
    // The reference and its index files are VALUE channels (file / files):
    // every sample can use them. A queue channel would be used by one sample.
    ref       = file(params.ref)                                // the FASTA
    ref_index = files("${params.ref}.*")                        // its .fai and the BWA index
    ref_dict  = file("${ref.parent}/${ref.baseName}.dict")      // smoke.dict, not smoke.fa.dict

    // One item per sample, [meta, reads], with the columns read by name.
    sheet = file(params.samplesheet)
    ch_samples = channel.fromPath(sheet)
        .splitCsv(header: true)
        .map { row ->
            def meta  = [id: row.sample_id, single_end: row.library_type == 'single']
            def r1    = sheet.parent.resolve(row.r1_fastq)
            def reads = meta.single_end ? [r1] : [r1, sheet.parent.resolve(row.r2_fastq)]
            [meta, reads]
        }

    // Stage 0 gets every FASTQ, and every sample waits for it to pass.
    VALIDATE(sheet, ch_samples.map { _meta, reads -> reads }.collect(),
             ref, ref_index, ref_dict)
    ch_checked = ch_samples
        .combine(VALIDATE.out.sheet)
        .map { meta, reads, _validated -> [meta, reads] }

    // Stages 1-5: once per sample
    FASTQC(ch_checked)
    FASTP(ch_checked)
    BWA_MEM(FASTP.out.reads, ref, ref_index)
    MARKDUPLICATES(BWA_MEM.out.bam)
    HAPLOTYPECALLER(MARKDUPLICATES.out.bam, ref, ref_index, ref_dict)

    // Stages 6-9: once per run. collect() is the barrier: it waits for every sample.
    JOINT_GENOTYPE(HAPLOTYPECALLER.out.gvcf.collect(), HAPLOTYPECALLER.out.tbi.collect(),
                   ref, ref_index, ref_dict)
    FILTER(JOINT_GENOTYPE.out.vcf, ref, ref_index, ref_dict)
    MULTIQC(FASTQC.out.zip
                .mix(FASTP.out.json, MARKDUPLICATES.out.flagstat, MARKDUPLICATES.out.metrics)
                .collect())
    PUBLISH(VALIDATE.out.sheet, FILTER.out.vcf.mix(FILTER.out.table, MULTIQC.out).collect())

    publish:
    vcf      = FILTER.out.vcf
    variants = FILTER.out.table
    multiqc  = MULTIQC.out
    manifest = PUBLISH.out.manifest
    samples  = PUBLISH.out.samples
}

output {
    vcf {
        path '.'
    }
    variants {
        path '.'
    }
    multiqc {
        path '.'
    }
    manifest {
        path '.'
    }
    samples {
        path '.'
    }
}
