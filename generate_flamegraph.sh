#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "usage: $0 <perf-data-file>" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERF_DATA="$(realpath "$1")"
NAME="$(basename "$PERF_DATA" .perf.data)"
FOLDED="$ROOT/results/$NAME.folded"
SVG="$ROOT/results/$NAME.svg"

if [[ ! -x "$ROOT/FlameGraph/stackcollapse-perf.pl" ]]; then
    echo "FlameGraph tools are missing; run ./setup_vm.sh first." >&2
    exit 1
fi

perf script -i "$PERF_DATA" \
    | "$ROOT/FlameGraph/stackcollapse-perf.pl" > "$FOLDED"
"$ROOT/FlameGraph/flamegraph.pl" \
    --title "$NAME" \
    --subtitle "pyperformance HWSW project" \
    "$FOLDED" > "$SVG"
echo "Created $SVG"
