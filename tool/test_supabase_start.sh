#!/usr/bin/env bash
# tool/test_supabase_start.sh
# Boots local Supabase for Ring 2 integration tests.
# Idempotent: succeeds if already running.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v supabase >/dev/null 2>&1; then
  echo "ERROR: supabase CLI not on PATH. Install: brew install supabase/tap/supabase" >&2
  exit 1
fi

if supabase status >/dev/null 2>&1; then
  echo "Supabase already running."
else
  echo "Starting Supabase..."
  supabase start
fi

STATUS_JSON="$(supabase status -o json)"
API_URL="$(echo "$STATUS_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["API_URL"])')"
ANON_KEY="$(echo "$STATUS_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')"
SERVICE_ROLE_KEY="$(echo "$STATUS_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["SERVICE_ROLE_KEY"])')"
DB_URL="$(echo "$STATUS_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["DB_URL"])')"

ENV_FILE="$REPO_ROOT/.env.test.supabase"
# Race-safe: subshell with umask 077 means the file is born 0600.
(
  umask 077
  cat >"$ENV_FILE" <<EOF
SUPABASE_TEST_API_URL=$API_URL
SUPABASE_TEST_ANON_KEY=$ANON_KEY
SUPABASE_TEST_SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SUPABASE_TEST_DB_URL=$DB_URL
EOF
)

echo "Supabase ready."
echo "  API:   $API_URL"
echo "  Wrote: $ENV_FILE"
