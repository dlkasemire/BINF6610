# containers/Dockerfile — the tools the variant-calling pipeline runs,
# pinned to the versions in the course conda environment.
FROM mambaorg/micromamba:2.0.5-ubuntu24.04

# One RUN: install, then clean in the same layer, so the 1.5 GB of package
# cache never becomes part of the image.
RUN micromamba install -y -n base \
      -c conda-forge -c bioconda --override-channels \
      bwa=0.7.19 samtools=1.24 bcftools=1.24 gatk4=4.6.2.0 \
      fastqc=0.12.1 fastp=1.3.7 multiqc=1.35 \
      git=2.47.1 \
 && micromamba clean --all --yes

ENV PATH=/opt/conda/bin:$PATH
USER mambauser
