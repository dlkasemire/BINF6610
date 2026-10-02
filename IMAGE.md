# IMAGE.md — the image the week-3 cohort ran in

## Base image
mambaorg/micromamba:2.0.5-ubuntu24.04
mambaorg/micromamba@sha256:1c62a28916ad7a4533555a542a5410e55ea2ed2c1e29f00c8fc3f1c8add111d5

## Versions pinned
bwa=0.7.19 samtools=1.24 bcftools=1.24 gatk4=4.6.2.0 fastqc=0.12.1 fastp=1.3.7 multiqc=1.35 git=2.47.1

Built from `containers/Dockerfile` with
`docker build --platform linux/amd64 -t dlkasemire/variant-call:1.0 containers/`
(architecture amd64, checked with `docker image inspect`).

## The pushed image
docker.io/dlkasemire/variant-call@sha256:d8e0045f18a138ebbca4ed7564068949a125224c005fa6cd12e0c582e683fdf0

To rerun this in a year, the heading that matters is **The pushed image**: its
digest names one exact image on Docker Hub that cannot change, so
`apptainer pull docker://dlkasemire/variant-call@sha256:d8e0...83fdf0` gets back
the same software even after /scratch has been emptied and the .sif is gone.
With it you need this repository at commit f7f06db (the commit the run's
manifest records), the course samplesheet, and the GRCh38 reference. The tag
`1.0` alone is not enough, because a tag can be moved to a different image.
If the pushed image were ever deleted, **Base image** and **Versions pinned**
say how to rebuild it, but a rebuild would not be byte-identical: packages the
recipe does not pin, such as htslib, are resolved on the day of the build.
