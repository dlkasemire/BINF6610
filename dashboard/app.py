#!/usr/bin/env python3
"""app.py: a results page for the runs in the week-9 database.

usage: python3 dashboard/app.py <database> [port]     # then open http://127.0.0.1:<port>

Two pages:
  /                         every run (db/queries/q1.sql), with a link to each run's results
  /results?run=<run_id>     one run: its samples, five plots and its sites
A click on a bar of a count plot leaves in the sites table only that bar's sites.
"""
import os
import sqlite3
import sys
from urllib.parse import parse_qs

import dash_ag_grid as dag
import pandas as pd
import plotly.graph_objects as go
from dash import Dash, Input, Output, State, ctx, dcc, html

DB = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8050
HERE = os.path.dirname(os.path.abspath(__file__))

SITE_COLUMNS = ["chrom", "pos", "ref", "alt", "qual", "filter"]
TRANSITIONS = {("A", "G"), ("G", "A"), ("C", "T"), ("T", "C")}


# ---------- reading the database ----------
def query(sql, params=()):
    """Run one query on the database named on the command line.
    A new connection each time: Dash runs each callback in a thread of its own."""
    con = sqlite3.connect(DB)
    try:
        return pd.read_sql_query(sql, con, params=params)
    finally:
        con.close()


def run_list():
    """The answer of db/queries/q1.sql: run_id, implementation, platform, n_samples, minutes."""
    with open(os.path.join(HERE, "..", "db", "queries", "q1.sql")) as fh:
        return query(fh.read())


def run_samples(run_id):
    return query(
        "SELECT rs.sample_id, rs.condition, s.phenotype, s.is_synthetic_phenotype "
        "FROM run_samples rs JOIN samples s ON s.sample_id = rs.sample_id "
        "WHERE rs.run_id = ? ORDER BY rs.sample_id",
        params=(run_id,))


def run_sites(run_id):
    """Every site of the run, with its type (SNP, indel, multiallelic) and, for a SNP,
    transition or transversion."""
    sites = query(
        "SELECT chrom, pos, ref, alt, qual, filter FROM variants "
        "WHERE run_id = ? ORDER BY chrom, pos",
        params=(run_id,))
    sites["type"] = [site_type(r, a) for r, a in zip(sites["ref"], sites["alt"])]
    sites["titv"] = [titv(r, a, t) for r, a, t in zip(sites["ref"], sites["alt"], sites["type"])]
    return sites


def site_type(ref, alt):
    if "," in alt:
        return "multiallelic"
    if len(ref) == 1 and len(alt) == 1:
        return "SNP"
    return "indel"


def titv(ref, alt, kind):
    if kind != "SNP":
        return None
    return "transition" if (ref.upper(), alt.upper()) in TRANSITIONS else "transversion"


# ---------- the plots ----------
def count_bar(series, title, xlabel):
    """A bar chart: one bar for each value of series, its height the number of sites."""
    counts = series.dropna().value_counts().sort_index()
    fig = go.Figure(go.Bar(x=list(counts.index), y=[int(n) for n in counts.values]))
    fig.update_layout(title=title, xaxis_title=xlabel, yaxis_title="sites")
    return fig


def value_histogram(series, title, xlabel):
    """A histogram drawn from the raw values themselves."""
    fig = go.Figure(go.Histogram(x=series.dropna().tolist()))
    fig.update_layout(title=title, xaxis_title=xlabel, yaxis_title="sites")
    return fig


# ---------- the pages ----------
def runs_page():
    runs = run_list()
    links = html.Ul([
        html.Li(dcc.Link(run_id, href=f"/results?run={run_id}"))
        for run_id in runs["run_id"]
    ])
    return html.Div([
        html.H1("Runs of variant-call"),
        html.P("Open a run to see its results:"),
        links,
        dag.AgGrid(id="runs-table",
                   rowData=runs.to_dict("records"),
                   columnDefs=[{"field": c} for c in runs.columns],
                   columnSize="sizeToFit"),
    ])


def results_page(run_id):
    samples = run_samples(run_id)
    sites = run_sites(run_id)
    return html.Div([
        dcc.Link("← all runs", href="/"),
        html.H1(f"Run {run_id}"),
        dcc.Store(id="run-id", data=run_id),

        html.H2("Samples"),
        html.P("The phenotypes of this course's cohort are made up for teaching "
               "(is_synthetic_phenotype = true): they describe no real person."),
        dag.AgGrid(id="samples-table",
                   rowData=samples.to_dict("records"),
                   columnDefs=[{"field": c} for c in samples.columns],
                   columnSize="sizeToFit"),

        html.H2("Plots"),
        html.P("Click a bar of the filter, type or Ti/Tv plot to show only its sites below."),
        dcc.Graph(id="plot-filter",
                  figure=count_bar(sites["filter"],
                                   "How many sites passed, and why did the others fail?",
                                   "filter")),
        dcc.Graph(id="plot-type",
                  figure=count_bar(sites["type"],
                                   "How many SNPs, indels and multiallelic sites?",
                                   "type")),
        dcc.Graph(id="plot-titv",
                  figure=count_bar(sites["titv"],
                                   "Among SNPs, how many transitions and transversions?",
                                   "change")),
        dcc.Graph(id="plot-qual",
                  figure=value_histogram(sites["qual"],
                                         "How confident are the calls?", "qual")),
        dcc.Graph(id="plot-position",
                  figure=value_histogram(sites["pos"],
                                         "Where along the region are the sites?", "pos")),

        html.H2("Sites"),
        html.Div(id="sites-note", children="All sites of the run."),
        dag.AgGrid(id="sites-table",
                   rowData=sites[SITE_COLUMNS].to_dict("records"),
                   columnDefs=[{"field": c} for c in SITE_COLUMNS],
                   columnSize="sizeToFit"),
    ])


# ---------- the app ----------
app = Dash(__name__, suppress_callback_exceptions=True)
app.layout = html.Div([dcc.Location(id="url"), html.Div(id="page")])


@app.callback(Output("page", "children"),
              Input("url", "pathname"), Input("url", "search"))
def draw_page(pathname, search):
    if pathname == "/results":
        run = parse_qs((search or "").lstrip("?")).get("run")
        if not run:
            return html.Div([html.P("No run named."), dcc.Link("All runs", href="/")])
        return results_page(run[0])
    return runs_page()


@app.callback(Output("sites-table", "rowData"), Output("sites-note", "children"),
              Input("plot-filter", "clickData"),
              Input("plot-type", "clickData"),
              Input("plot-titv", "clickData"),
              State("run-id", "data"))
def narrow_sites(filter_click, type_click, titv_click, run_id):
    """A click on a bar leaves only that bar's sites; no click shows them all."""
    sites = run_sites(run_id)
    column = {"plot-filter": "filter", "plot-type": "type", "plot-titv": "titv"}
    click = {"plot-filter": filter_click, "plot-type": type_click,
             "plot-titv": titv_click}.get(ctx.triggered_id)
    if not click:
        return sites[SITE_COLUMNS].to_dict("records"), "All sites of the run."
    point = click["points"][0]
    label = point.get("label", point.get("x"))
    chosen = sites[sites[column[ctx.triggered_id]] == label]
    return (chosen[SITE_COLUMNS].to_dict("records"),
            f"Only the sites where {column[ctx.triggered_id]} is {label}: {len(chosen)} of {len(sites)}.")


if __name__ == "__main__":
    app.run(port=PORT, debug=True)
