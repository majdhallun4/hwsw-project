#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

./collect_system_info.sh
"$ROOT/.venv/bin/python3" "$ROOT/validate.py" \
    2>&1 | tee "$ROOT/results/validation.txt"
./run_official_reference.sh
./script_nbody.sh benchmark
./script_nbody.sh profile
./script_pyflate.sh benchmark
./script_pyflate.sh profile
"$ROOT/.venv/bin/python3" "$ROOT/summarize_results.py"
./hardware/run_tests.sh 2>&1 | tee "$ROOT/results/hardware_tests.txt"

echo "All runs completed. Return the results/ directory for report finalization."
