#!/bin/bash
#SBATCH -A binf6610.202710 -p courses
#SBATCH -c 4 --mem=16G -t 00:30:00
#SBATCH -o pull-%j.out
#
# Fetch the image onto Explorer as a .sif, by its digest, as a job: the
# conversion peaks near 8 GiB of memory, more than the login node allows.
# The download cache goes on /scratch, not the home directory, whose quota is fixed.
set -euo pipefail
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache
mkdir -p /scratch/${USER}/containers
apptainer pull --force /scratch/${USER}/containers/variant-call.sif \
    docker://dlkasemire/variant-call@sha256:d8e0045f18a138ebbca4ed7564068949a125224c005fa6cd12e0c582e683fdf0
