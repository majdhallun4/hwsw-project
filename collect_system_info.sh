#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/results/system_info.txt"
mkdir -p "$ROOT/results"

{
    date --iso-8601=seconds
    uname -a
    lscpu
    echo
    "$ROOT/.venv/bin/python3" --version
    "$ROOT/.venv/bin/python3" -m pyperformance --version
    "$ROOT/.venv/bin/python3" -m pip freeze
    echo
    perf --version
    sysctl kernel.perf_event_paranoid 2>/dev/null || true
    cat /proc/sys/kernel/kptr_restrict 2>/dev/null || true
} > "$OUT"

echo "Created $OUT"
