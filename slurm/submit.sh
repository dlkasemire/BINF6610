#!/usr/bin/env bash
# submit.sh — the array, then the cohort job after it. Run it from slurm/:
#   cd slurm && bash submit.sh          # tasks 1-8
#   cd slurm && bash submit.sh 1-2      # tasks 1 and 2 only (the cohort job still follows)
set -euo pipefail

# sbatch records the folder it was run from as SLURM_SUBMIT_DIR, and the job
# scripts find conf/ through it -- so this has to be run from slurm/.
[[ -f conf/slurm.env ]] || { echo "run this from the slurm/ folder: cd slurm && bash submit.sh" >&2; exit 64; }
source conf/slurm.env

mkdir -p logs                                 # Slurm will not create the log folder

TASKS=${1:-1-8}

ARRAY_ID=$(sbatch --parsable -p "$PARTITION" -A "$ACCOUNT" --array="${TASKS}" 01_persample.sbatch)
ARRAY_ID=${ARRAY_ID%%;*}                      # --parsable may append ";cluster"
echo "array ${ARRAY_ID}: tasks ${TASKS}"

COHORT_ID=$(sbatch --parsable -p "$PARTITION" -A "$ACCOUNT" \
            --dependency=afterok:${ARRAY_ID} --kill-on-invalid-dep=yes 02_cohort.sbatch)
COHORT_ID=${COHORT_ID%%;*}
echo "cohort ${COHORT_ID}: starts after every task of ${ARRAY_ID} succeeds"
echo "watch with: squeue -u ${USER}"
