#!/usr/bin/env bash
# Idle check: launches the app, waits 30 s, prints CPU and physical footprint,
# fails if footprint > 15 MB or CPU > 1.0 %. Footprint (phys_footprint) is used rather
# than RSS because RSS counts shared system framework pages.
set -euo pipefail

cd "$(dirname "$0")/.."

LIMIT_KB=15360
CPU_LIMIT="1.0"

if pgrep -x trrek >/dev/null; then
    echo "a trrek process is already running; quit it first so the measurement is of a fresh launch" >&2
    exit 1
fi

APP="$HOME/Applications/trrek.app"
[[ -d "$APP" ]] || APP="dist/trrek.app"
if [[ ! -d "$APP" ]]; then
    echo "no trrek.app found (run 'make install' or 'make app' first)" >&2
    exit 1
fi

open -g "$APP"
sleep 30

PID="$(pgrep -x trrek | head -n 1 || true)"
if [[ -z "$PID" ]]; then
    echo "trrek process not found after launch" >&2
    exit 1
fi

CPU="$(ps -o %cpu= -p "$PID" | tr -d ' ')"
if [[ -z "$CPU" ]]; then
    echo "could not read CPU usage of pid $PID" >&2
    exit 1
fi

# Prints the physical footprint in KB, or nothing if it cannot be determined. vmmap reports
# a fractional value ("13.5M"); footprint rounds to whole MB, so it is only the fallback.
footprint_kb() {
    local line=""
    if command -v vmmap >/dev/null; then
        line="$(vmmap --summary "$1" 2>/dev/null | grep -i 'Physical footprint:' | head -n 1 || true)"
    fi
    if [[ -z "$line" ]] && command -v footprint >/dev/null; then
        line="$(footprint -p "$1" 2>/dev/null | grep -Ei 'phys_footprint|Footprint:' | head -n 1 || true)"
    fi
    [[ -n "$line" ]] || return 0
    echo "$line" | sed -nE 's/.*[^0-9.]([0-9.]+) ?(B|K|KB|M|MB|G|GB)([^A-Za-z].*)?$/\1 \2/p' | awk '{
        v = $1; u = $2
        if (u ~ /^G/) v *= 1048576; else if (u ~ /^M/) v *= 1024; else if (u == "B") v /= 1024
        printf "%d\n", v
    }'
}

FOOTPRINT_KB="$(footprint_kb "$PID")"

osascript -e 'quit app "trrek"' >/dev/null 2>&1 || kill "$PID" 2>/dev/null || true

if [[ -z "$FOOTPRINT_KB" ]]; then
    echo "could not read the physical footprint of pid $PID" >&2
    exit 1
fi

echo "pid=$PID cpu=${CPU}% footprint=${FOOTPRINT_KB}KB (limits: ${LIMIT_KB}KB, ${CPU_LIMIT}%)"

FAIL=0
if (( FOOTPRINT_KB > LIMIT_KB )); then
    echo "footprint ${FOOTPRINT_KB}KB exceeds ${LIMIT_KB}KB" >&2
    FAIL=1
fi
if awk -v c="$CPU" -v l="$CPU_LIMIT" 'BEGIN { exit !(c > l) }'; then
    echo "CPU ${CPU}% exceeds ${CPU_LIMIT}%" >&2
    FAIL=1
fi
exit "$FAIL"
