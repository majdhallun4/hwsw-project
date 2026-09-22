#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${PYTHON:-$ROOT/.venv/bin/python3}"
CPU_CORE="${CPU_CORE:-0}"
OUTPUT="$ROOT/results/pyperformance_official_reference.json"

rm -f "$OUTPUT"
"$PYTHON" -m pyperformance run \
    --benchmarks nbody,pyflate \
    --rigorous \
    --affinity "$CPU_CORE" \
    --output "$OUTPUT"
