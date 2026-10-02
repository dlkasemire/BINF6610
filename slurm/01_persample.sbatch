#!/usr/bin/env bash
#SBATCH --job-name=w2-persample
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=4
#SBATCH --mem=12G
#SBATCH --time=00:30:00
#SBATCH --export=NONE                          # start clean: take nothing from your login shell
#SBATCH --output=logs/persample_%A_%a.out      # submit.sh runs mkdir -p logs first; sbatch does not
#
# Stages 0-5 for ONE sample: task N runs the sample on row N of the samplesheet.
# This script picks the sample and the resources; run_sample.sh does the work,
# inside the image, so the tools come from the image.
set -euo pipefail
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"    # the folder you ran sbatch from, which is slurm/

# Cores: from Slurm, never typed as a number here
export THREADS="${SLURM_CPUS_PER_TASK}"

# Temporary files on the node's own disk, removed however the job ends
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

# Row N + 1 of the file, because row 1 is the header
SAMPLE=$(awk -F',' -v n="${SLURM_ARRAY_TASK_ID}" 'NR == n + 1 { print $1 }' "${SAMPLESHEET}")
[[ -n "${SAMPLE}" ]] || { echo "task ${SLURM_ARRAY_TASK_ID}: no row ${SLURM_ARRAY_TASK_ID} in ${SAMPLESHEET}" >&2; exit 64; }

echo "task ${SLURM_ARRAY_TASK_ID}: ${SAMPLE} on $(hostname), ${THREADS} cores, image ${SIF}" >&2

# --cleanenv: nothing from this shell crosses into the container unless named
#             with --env below.
# --bind:     the container sees home and /tmp already; the data (/courses) and
#             the run directory (/scratch) have to be added.
apptainer exec --cleanenv \
    --env THREADS="${THREADS}" \
    --env TMPDIR="${TMPDIR}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}" \
    --bind /courses/BINF6610.202710,/scratch/${USER} \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_sample.sh" "${SAMPLESHEET}" "${RUN_ROOT}" "${SAMPLE}"
