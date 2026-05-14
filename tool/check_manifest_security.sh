#!/usr/bin/env bash
# Verifies AndroidManifest.xml ships with no exported components and no
# sharedUserId — both increase the local-attack surface (spec §6.1 item 11).
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"

if [[ ! -f "$MANIFEST" ]]; then
  echo "FAIL: $MANIFEST not found"
  exit 1
fi

if grep -E 'android:sharedUserId=' "$MANIFEST" > /dev/null; then
  echo "FAIL: android:sharedUserId is forbidden in $MANIFEST"
  exit 1
fi

# Look for exported components other than the LAUNCHER activity which
# legitimately must be exported.
exported_lines=$(grep -nE 'android:exported="true"' "$MANIFEST" || true)
if [[ -n "$exported_lines" ]]; then
  while IFS= read -r match; do
    line_no="${match%%:*}"
    start=$((line_no > 10 ? line_no - 10 : 1))
    end=$((line_no + 20))
    block=$(sed -n "${start},${end}p" "$MANIFEST")
    if ! grep -qE 'android.intent.action.MAIN' <<<"$block"; then
      echo "FAIL: exported component on line $line_no is not a LAUNCHER activity"
      echo "Context:"
      echo "$block"
      exit 1
    fi
  done <<<"$exported_lines"
fi

echo "OK: manifest security check passed"
