-- schema.sql: the database of variant-call runs (weeks 4-6).
-- Build an empty database with:  sqlite3 runs.db < db/schema.sql

-- A pipeline version: one row for each name + version + implementation.
CREATE TABLE pipelines (
    pipeline_id     INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    version         TEXT NOT NULL,
    implementation  TEXT NOT NULL,          -- nextflow or snakemake
    UNIQUE (name, version, implementation)
) STRICT;

-- One row for each run: the facts in its manifest.json, and its folder.
CREATE TABLE runs (
    run_id       TEXT PRIMARY KEY,           -- the manifest's pipeline.run_id
    pipeline_id  INTEGER NOT NULL REFERENCES pipelines (pipeline_id),
    started_at   TEXT,
    finished_at  TEXT,
    exit_status  TEXT,
    platform     TEXT,                       -- platform.kind
    executor     TEXT,
    engine       TEXT,
    git_sha      TEXT,
    samplesheet  TEXT,
    reference    TEXT,
    region       TEXT,
    folder       TEXT                        -- absolute path of the run's folder
) STRICT;

-- One row for each sample: the metadata file's columns, as written there.
-- A sample the metadata does not list (the smoke samples) has only its sample_id.
CREATE TABLE samples (
    sample_id               TEXT PRIMARY KEY,
    sex                     TEXT,
    population              TEXT,
    family                  TEXT,
    father                  TEXT,
    mother                  TEXT,
    phenotype               TEXT,
    is_synthetic_phenotype  TEXT
) STRICT;

-- Which samples each run used, as that run described them.
CREATE TABLE run_samples (
    run_id        TEXT NOT NULL REFERENCES runs (run_id),
    sample_id     TEXT NOT NULL REFERENCES samples (sample_id),
    condition     TEXT,
    library_type  TEXT,
    PRIMARY KEY (run_id, sample_id)          -- the same sample twice in one run is refused
) STRICT;

-- One row for each line of a run's variants.tsv.
CREATE TABLE variants (
    run_id      TEXT NOT NULL REFERENCES runs (run_id),
    chrom       TEXT NOT NULL,
    pos         INTEGER NOT NULL,
    ref         TEXT NOT NULL,
    alt         TEXT NOT NULL,
    qual        REAL,
    filter      TEXT
) STRICT;

-- One row for each file in the manifest's outputs.
CREATE TABLE outputs (
    run_id  TEXT NOT NULL REFERENCES runs (run_id),
    path    TEXT NOT NULL,
    sha256  TEXT NOT NULL,                   -- the 64 characters after "sha256:"
    PRIMARY KEY (run_id, path)
) STRICT;
