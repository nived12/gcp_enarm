#!/usr/bin/env bash
# Loads the local corpus and question bank into the Railway database, in the order
# DEPLOY.md requires. Run from gpc_enarm/ on the machine that holds the corpus.
#
#   script/load_production.sh            # corpus + figures + bank (first load)
#   script/load_production.sh --bank     # only a new question-bank export
#   script/load_production.sh --resume   # corpus already uploaded: redo the Railway steps and the bank
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

mode="${1:-}"

if [[ "$mode" == "" ]]; then
  echo "==> Exporting the local corpus to $corpus"
  env -u DATABASE_URL bin/rails "gpc:export[$corpus]"

  echo "==> Loading the corpus into production"
  bin/rails "gpc:import[$corpus]"
fi

if [[ "$mode" != "--bank" ]]; then
  # Rebuilding recommendations writes tens of thousands of rows; from this machine each
  # is a round trip to Railway's region and the step crawls. Inside the container the
  # database is next door. Figures are files, so they must be fetched there anyway, onto
  # its volume. Every one of these is safe to rerun if the connection drops.
  echo "==> Rebuilding recommendations and fetching figures on Railway (several minutes)"
  # Railway closes long SSH sessions (one dropped at figure 426 of 870). Each task skips
  # what is already done, so a dropped attempt is simply run again.
  for attempt in 1 2 3 4 5; do
    railway ssh --service web -- bin/rails gpc:reparse gpc:images taxonomy:seed gpc:link && break
    [[ $attempt == 5 ]] && { echo "The Railway steps kept dropping; run --resume later." >&2; exit 1; }
    echo "==> The connection dropped; trying again ($((attempt + 1)) of 5)"
  done
fi

echo "==> Loading the question bank into production"
# A case whose citation cannot be found in production's own parse is refused and named
# (the rest still import), so a refusal must not hide the totals below.
bin/rails "questions:import[$bank]" || echo "==> Some cases were refused; they are named above."

bin/rails runner 'puts "Production: #{Guideline.count} guías, #{ClinicalCase.status_published.count} casos publicados, #{Question.count} preguntas"'
