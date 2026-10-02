#!/usr/bin/env bash
#SBATCH --job-name=w2-cohort
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=01:00:00
#SBATCH --export=NONE                          # start clean: take nothing from your login shell
#SBATCH --output=logs/cohort_%j.out            # submit.sh runs mkdir -p logs first; sbatch does not
#
# Stages 6-9, once, for the whole cohort, inside the image. submit.sh starts
# this only after every array task has SUCCEEDED (afterok).
set -euo pipefail
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"    # the folder you ran sbatch from, which is slurm/

export THREADS="${SLURM_CPUS_PER_TASK}"

export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "cohort job on $(hostname), ${THREADS} cores, image ${SIF}" >&2

# last stage publish, first stage merge: stages 0-5 were done by the array
apptainer exec --cleanenv \
    --env THREADS="${THREADS}" \
    --env TMPDIR="${TMPDIR}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}" \
    --bind /courses/BINF6610.202710,/scratch/${USER} \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_pipeline.sh" "${SAMPLESHEET}" "${RUN_ROOT}" publish merge
