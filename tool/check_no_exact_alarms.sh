#!/usr/bin/env bash
# Fail if any forbidden exact-alarm permission or API leaks in.
set -euo pipefail

if grep -rnE 'SCHEDULE_EXACT_ALARM|USE_EXACT_ALARM' android/ 2>/dev/null; then
  echo "ERROR: Exact alarm permissions are forbidden by project policy." >&2
  exit 1
fi
if grep -rnE 'AndroidScheduleMode\.exactAllowWhileIdle|AndroidScheduleMode\.alarmClock|AndroidScheduleMode\.exact[^a-zA-Z]' lib/ 2>/dev/null; then
  echo "ERROR: Exact-alarm schedule modes are forbidden by project policy." >&2
  exit 1
fi
echo "OK: no exact alarm usage detected."
