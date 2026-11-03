#!/usr/bin/env bash
# Idle-footprint check: launches the app, waits 30 s, prints CPU/RSS, fails if RSS > 15 MB.
set -euo pipefail

cd "$(dirname "$0")/.."

LIMIT_KB=15360
APP="$HOME/Applications/trrek.app"
[[ -d "$APP" ]] || APP="dist/trrek.app"
if [[ ! -d "$APP" ]]; then
    echo "no trrek.app found (run 'make app' first)" >&2
    exit 1
fi

open -g "$APP"
sleep 30

PID="$(pgrep -x trrek | head -n 1 || true)"
if [[ -z "$PID" ]]; then
    echo "trrek process not found after launch" >&2
    exit 1
fi

read -r CPU RSS < <(ps -o %cpu=,rss= -p "$PID")
echo "pid=$PID cpu=${CPU}% rss=${RSS}KB (limit ${LIMIT_KB}KB)"
if command -v footprint >/dev/null; then
    footprint "$PID" || true
fi

kill "$PID" || true

if (( RSS > LIMIT_KB )); then
    echo "RSS ${RSS}KB exceeds ${LIMIT_KB}KB" >&2
    exit 1
fi
