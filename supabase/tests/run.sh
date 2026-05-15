#!/usr/bin/env bash
# pgTAP test runner — pipes all *_test.sql files through pg_prove.
# Usage: ./supabase/tests/run.sh [--db-url <url>]
# Requires pg_prove (sudo cpan TAP::Parser::SourceHandler::pgTAP)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:54322/postgres}"

if [[ "$#" -gt 0 && "$1" == "--db-url" ]]; then
  DB_URL="$2"
fi

echo "Running pgTAP tests against: $DB_URL"

test_files=("$SCRIPT_DIR"/*_test.sql)
if [[ ${#test_files[@]} -eq 0 ]]; then
  echo "No *_test.sql files found in $SCRIPT_DIR"
  exit 0
fi

pg_prove --verbose --dbname "$DB_URL" "${test_files[@]}"
