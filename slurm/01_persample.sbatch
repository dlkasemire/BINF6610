#!/usr/bin/env bash
#SBATCH --job-name=w2-persample
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --export=NONE                          # start clean: take nothing from your login shell
#SBATCH --output=logs/persample_%A_%a.out      # submit.sh runs mkdir -p logs first; sbatch does not
#
# Stages 0-5 for ONE sample: task N runs the sample on row N of the samplesheet.
# This script picks the sample and the resources; run_sample.sh does the work.
set -euo pipefail
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"    # the folder you ran sbatch from, which is slurm/

# The tools come from the course environment. Its activation scripts read
# variables that may be unset, so -u is switched off just around them.
set +u
module load miniconda3/25.9.1
source activate "${CONDA_ENV}"
set -u

# Cores: from Slurm, never typed as a number here
export THREADS="${SLURM_CPUS_PER_TASK}"

# Temporary files on the node's own disk, removed however the job ends
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

# Row N + 1 of the file, because row 1 is the header
SAMPLE=$(awk -F',' -v n="${SLURM_ARRAY_TASK_ID}" 'NR == n + 1 { print $1 }' "${SAMPLESHEET}")
[[ -n "${SAMPLE}" ]] || { echo "task ${SLURM_ARRAY_TASK_ID}: no row ${SLURM_ARRAY_TASK_ID} in ${SAMPLESHEET}" >&2; exit 64; }

echo "task ${SLURM_ARRAY_TASK_ID}: ${SAMPLE} on $(hostname), ${THREADS} cores, TMPDIR=${TMPDIR}" >&2
bash "${PIPELINE_DIR}/run_sample.sh" "${SAMPLESHEET}" "${RUN_ROOT}" "${SAMPLE}"

# The exact memory high-water mark, for RESOURCES.md
CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak bytes: $(cat "$CG/memory.peak" 2>/dev/null || echo unavailable)" >&2
