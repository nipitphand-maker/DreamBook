#!/usr/bin/env bash
# tool/test_supabase_stop.sh
# Tears down local Supabase. Always exits 0 (idempotent).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if command -v supabase >/dev/null 2>&1 && supabase status >/dev/null 2>&1; then
  supabase stop --no-backup || true
fi
rm -f "$REPO_ROOT/.env.test.supabase"
echo "Supabase stopped."
