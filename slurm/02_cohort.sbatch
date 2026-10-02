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
# Stages 6-9, once, for the whole cohort. submit.sh starts this only after
# every array task has SUCCEEDED (afterok), so every sample's GVCF exists.
set -euo pipefail
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"    # the folder you ran sbatch from, which is slurm/

set +u
module load miniconda3/25.9.1
source activate "${CONDA_ENV}"
set -u

export THREADS="${SLURM_CPUS_PER_TASK}"

export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "cohort job on $(hostname), ${THREADS} cores, TMPDIR=${TMPDIR}" >&2
# last stage publish, first stage merge: stages 0-5 were done by the array
bash "${PIPELINE_DIR}/run_pipeline.sh" "${SAMPLESHEET}" "${RUN_ROOT}" publish merge

CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak bytes: $(cat "$CG/memory.peak" 2>/dev/null || echo unavailable)" >&2
