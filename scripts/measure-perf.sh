#!/bin/zsh
# Builds the app and measures its CPU and memory in each notch state (closed, live, expanded).
# Writes the table to perf.txt in the output folder (default /tmp/notch-perf).
set -euo pipefail

ROOT="${0:A:h:h}"
OUT="${1:-/tmp/notch-perf}"
mkdir -p "$OUT"
"$ROOT/scripts/build-app.sh" >/dev/null
APP=$(ls -d "$ROOT"/*.app | head -1)
EXE="$APP/Contents/MacOS/$(defaults read "$APP/Contents/Info" CFBundleExecutable)"
"$EXE" --perf "$OUT/perf.txt"
cat "$OUT/perf.txt"
