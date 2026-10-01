# shellcheck shell=bash
set -euo pipefail   # already set by the driver that sources this; stated here so the file says so itself
# lib/common.sh — what every stage needs. Sourced by run_pipeline.sh and
# run_sample.sh, never run on its own.

PIPE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# All messages go to stderr (>&2), so stdout stays clean for data
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# ---------- configuration ----------
# Explorer values after :-, because a Slurm job starts the pipeline with
# nothing set. On the laptop, override them on the command line:
#   REF=$PWD/smoke.fa REGION=smoke_1mb bash run_pipeline.sh ...
REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
THREADS=${THREADS:-4}

# The condition column in this cohort is synthetic; published outputs say so.
CONDITION_IS_SYNTHETIC=${CONDITION_IS_SYNTHETIC:-true}

# A relative FASTQ path in the samplesheet is read from here. The default is
# the folder you ran from, which is how week 1's smoke samplesheet works.
FASTQ_ROOT=${FASTQ_ROOT:-$PWD}

# ---------- output folders, under OUTDIR, which the driver sets ----------
setup_dirs() {
    QC="${OUTDIR}/qc_raw"; TRIM="${OUTDIR}/trim"; ALN="${OUTDIR}/align"
    GVCF="${OUTDIR}/gvcf"; LOG="${OUTDIR}/logs"; RES="${OUTDIR}/results"
    mkdir -p "$QC" "$TRIM" "$ALN" "$GVCF" "$LOG" "$RES"
}

# ---------- rows <sheet> [sample_id] ----------
# Prints six fields per row -- sample_id,condition,replicate,library_type,r1,r2
# -- whatever shape the samplesheet is, picking the columns BY NAME from its
# header. Given a sample_id, prints only that sample's row.
rows() {
    local sheet=$1 only=${2:-}
    awk -F, -v want="$only" -v root="$FASTQ_ROOT" '
        BEGIN { n = split("sample_id condition replicate library_type r1_fastq r2_fastq", need, " ") }
        NR == 1 {
            for (i = 1; i <= NF; i++) col[$i] = i
            for (i = 1; i <= n; i++)
                if (!(need[i] in col)) {
                    print "samplesheet has no column named " need[i] > "/dev/stderr"
                    exit 65
                }
            next
        }
        want != "" && $col["sample_id"] != want { next }
        {
            r1 = $col["r1_fastq"]; r2 = $col["r2_fastq"]
            if (r1 != "" && r1 !~ /^\//) r1 = root "/" r1
            if (r2 != "" && r2 !~ /^\//) r2 = root "/" r2
            print $col["sample_id"] "," $col["condition"] "," $col["replicate"] \
                  "," $col["library_type"] "," r1 "," r2
        }
    ' "$sheet"
}
