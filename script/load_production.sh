#!/usr/bin/env bash
# Loads the local corpus and question bank into the Railway database, in the order
# DEPLOY.md requires. Run from gpc_enarm/ on the machine that holds the corpus.
#
#   script/load_production.sh            # corpus + figures + bank (first load)
#   script/load_production.sh --bank     # only a new question-bank export
#
# Every step is idempotent: the corpus keys on catalog_key and the bank on export_key,
# so a rerun updates rather than duplicates. Note that a bank import overwrites the
# status of cases that already exist in production (see DEPLOY.md) — after launch,
# review happens in production and only new batches should be imported.
set -euo pipefail

project=gpcenarm
corpus=tmp/gpc-corpus.jsonl.gz
bank=tmp/question-bank.jsonl.gz

railway status --json | grep -q "\"name\": *\"$project\"" || {
  echo "This folder is not linked to the Railway project '$project'. Stopping." >&2
  exit 1
}

# Railway's public TCP proxy (Postgres → Settings → Public Access). An SSH tunnel from
# `railway connect --tunnel-only` was tried first and dropped its channel mid-import.
# The proxy's traffic is billed as egress — cents for a load — and it can be removed
# again afterwards; the script then stops here and says so.
DATABASE_URL=$(railway variable list --service Postgres --json |
  ruby -rjson -e 'print JSON.parse($stdin.read)["DATABASE_PUBLIC_URL"].to_s')
if [[ -z "$DATABASE_URL" ]]; then
  echo "Postgres has no public access. Railway → Postgres → Settings → Add Public Access." >&2
  exit 1
fi
export DATABASE_URL

echo "==> Exporting the local bank to $bank"
env -u DATABASE_URL bin/rails "questions:export[$bank]"

if [[ "${1:-}" != "--bank" ]]; then
  echo "==> Exporting the local corpus to $corpus"
  env -u DATABASE_URL bin/rails "gpc:export[$corpus]"

  echo "==> Loading the corpus into production"
  bin/rails "gpc:import[$corpus]"
  bin/rails gpc:reparse

  # Figures are files, so they are fetched inside the container, onto its volume.
  echo "==> Fetching guideline figures on Railway (this takes a while)"
  railway ssh --service web -- bin/rails gpc:images

  bin/rails taxonomy:seed gpc:link
fi

echo "==> Loading the question bank into production"
bin/rails "questions:import[$bank]"

bin/rails runner 'puts "Production: #{Guideline.count} guías, #{ClinicalCase.status_published.count} casos publicados, #{Question.count} preguntas"'
