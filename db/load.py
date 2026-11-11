#!/usr/bin/env python3
"""load.py: load runs of variant-call into the database that schema.sql built.

usage: python3 db/load.py <database> <sample metadata.tsv> <run folder> [<run folder> ...]

Each run goes in whole, or not at all. A run already in the database is skipped,
so loading the same runs twice changes nothing.
"""
import csv
import json
import os
import sqlite3
import sys

META_COLUMNS = ["sample_id", "sex", "population", "family", "father", "mother",
                "phenotype", "is_synthetic_phenotype"]


def read_tsv(path):
    """Rows of a tab-separated file as dictionaries, skipping lines that start with #."""
    with open(path, newline="") as fh:
        lines = [line for line in fh if not line.startswith("#")]
    return list(csv.DictReader(lines, delimiter="\t"))


def load_metadata(con, path):
    """The metadata file into samples. A sample already there is left as it is."""
    added = 0
    with con:
        for row in read_tsv(path):
            if con.execute("SELECT 1 FROM samples WHERE sample_id = ?",
                           (row["sample_id"],)).fetchone():
                continue
            con.execute(
                "INSERT INTO samples (" + ", ".join(META_COLUMNS) + ") "
                "VALUES (" + ", ".join("?" * len(META_COLUMNS)) + ")",
                [row.get(c) for c in META_COLUMNS])
            added += 1
    print(f"metadata: {added} sample(s) added")


def pipeline_id(con, name, version, implementation):
    """The pipeline version's id, inserting it if it is new."""
    found = con.execute(
        "SELECT pipeline_id FROM pipelines WHERE name = ? AND version = ? AND implementation = ?",
        (name, version, implementation)).fetchone()
    if found:
        return found[0]
    cur = con.execute(
        "INSERT INTO pipelines (name, version, implementation) VALUES (?, ?, ?)",
        (name, version, implementation))
    return cur.lastrowid


def to_float(value):
    return None if value in (None, "", ".") else float(value)


def load_run(con, folder):
    """One run folder, whole or not at all. Returns 'loaded' or 'skipped'."""
    with open(os.path.join(folder, "manifest.json")) as fh:
        manifest = json.load(fh)
    pipe = manifest["pipeline"]
    params = manifest.get("params", {})
    plat = manifest.get("platform", {})
    run_id = pipe["run_id"]

    if con.execute("SELECT 1 FROM runs WHERE run_id = ?", (run_id,)).fetchone():
        print(f"{folder}: run {run_id} is already loaded, skipped")
        return "skipped"

    # library_type is in the manifest's samples; condition is in samples.tsv
    library_type = {s["sample_id"]: s.get("library_type")
                    for s in manifest.get("samples", [])}
    samples = read_tsv(os.path.join(folder, "samples.tsv"))
    variants = read_tsv(os.path.join(folder, "variants.tsv"))

    with con:   # commits at the end, or undoes the whole run if anything fails
        pid = pipeline_id(con, pipe["name"], pipe["version"], pipe["implementation"])

        con.execute(
            "INSERT INTO runs (run_id, pipeline_id, started_at, finished_at, exit_status, "
            "platform, executor, engine, git_sha, samplesheet, reference, region, folder) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (run_id, pid, pipe.get("started_at"), pipe.get("finished_at"),
             pipe.get("exit_status"), plat.get("kind"), plat.get("executor"),
             plat.get("engine"), pipe.get("git_sha"), params.get("samplesheet"),
             params.get("ref"), params.get("region"), os.path.abspath(folder)))

        for s in samples:
            sid = s["sample_id"]
            # a sample the metadata does not list (the smoke samples): a row with only its id
            if not con.execute("SELECT 1 FROM samples WHERE sample_id = ?", (sid,)).fetchone():
                con.execute("INSERT INTO samples (sample_id) VALUES (?)", (sid,))
            # the same sample twice in one run: the key refuses it, and the whole run is undone
            con.execute(
                "INSERT INTO run_samples (run_id, sample_id, condition, library_type) "
                "VALUES (?, ?, ?, ?)",
                (run_id, sid, s.get("condition"), library_type.get(sid)))

        con.executemany(
            "INSERT INTO variants (run_id, chrom, pos, ref, alt, qual, filter) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            [(run_id, v["chrom"], int(v["pos"]), v["ref"], v["alt"],
              to_float(v["qual"]), v["filter"]) for v in variants])

        con.executemany(
            "INSERT INTO outputs (run_id, path, sha256) VALUES (?, ?, ?)",
            [(run_id, o["path"], o["checksum"].removeprefix("sha256:"))
             for o in manifest.get("outputs", [])])

    print(f"{folder}: run {run_id} loaded: {len(samples)} samples, {len(variants)} variants")
    return "loaded"


def main(argv):
    if len(argv) < 4:
        sys.exit("usage: python3 db/load.py <database> <metadata.tsv> <run folder> ...")
    database, metadata, folders = argv[1], argv[2], argv[3:]

    con = sqlite3.connect(database)
    con.execute("PRAGMA foreign_keys = ON")   # SQLite checks foreign keys only when asked

    load_metadata(con, metadata)

    refused = 0
    for folder in folders:
        try:
            load_run(con, folder)
        except (sqlite3.Error, KeyError, ValueError, OSError) as err:
            print(f"{folder}: refused, nothing of it was loaded: {err}", file=sys.stderr)
            refused += 1
    con.close()
    return 1 if refused else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
