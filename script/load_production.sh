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

# The database has no public address. `railway connect --tunnel-only` opens an encrypted
# SSH tunnel to it on a local port for as long as this script runs; nothing is exposed
# and there is no public-traffic charge.
port=55432
railway connect Postgres --tunnel-only --port "$port" >/tmp/gpcenarm-tunnel.log 2>&1 &
tunnel=$!
trap 'kill "$tunnel" 2>/dev/null' EXIT
for _ in $(seq 1 30); do
  nc -z localhost "$port" 2>/dev/null && break
  sleep 1
done
nc -z localhost "$port" || { echo "The tunnel did not open:" >&2; cat /tmp/gpcenarm-tunnel.log >&2; exit 1; }

DATABASE_URL=$(railway variable list --service Postgres --json | ruby -rjson -e '
  v = JSON.parse($stdin.read)
  print "postgresql://#{v.fetch("PGUSER")}:#{v.fetch("PGPASSWORD")}@localhost:'"$port"'/#{v.fetch("PGDATABASE")}"')
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
