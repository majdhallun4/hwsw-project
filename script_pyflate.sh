#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${PYTHON:-$ROOT/.venv/bin/python3}"
RESULTS="$ROOT/results"
ACTION="${1:-all}"
CPU_CORE="${CPU_CORE:-0}"
mkdir -p "$RESULTS"

setup() {
    "$ROOT/setup_vm.sh"
}

ensure_environment() {
    if [[ ! -x "$PYTHON" ]]; then
        echo "Python environment missing; run $0 setup first." >&2
        exit 1
    fi
}

validate() {
    ensure_environment
    "$PYTHON" "$ROOT/validate.py" --only pyflate
}

benchmark() {
    ensure_environment
    rm -f "$RESULTS/pyflate_baseline.json" "$RESULTS/pyflate_optimized.json"
    taskset -c "$CPU_CORE" "$PYTHON" "$ROOT/benchmarks/pyflate_baseline.py" \
        --rigorous -o "$RESULTS/pyflate_baseline.json"
    taskset -c "$CPU_CORE" "$PYTHON" "$ROOT/benchmarks/pyflate_optimized.py" \
        --rigorous -o "$RESULTS/pyflate_optimized.json"
    "$PYTHON" -m pyperf compare_to \
        "$RESULTS/pyflate_baseline.json" "$RESULTS/pyflate_optimized.json" \
        --table > "$RESULTS/pyflate_comparison.txt"
    cat "$RESULTS/pyflate_comparison.txt"
}

profile_variant() {
    local variant="$1"
    local data="$RESULTS/pyflate_${variant}.perf.data"
    local profile_python="$ROOT/.venv-dbg/bin/python3"
    ensure_environment
    if [[ ! -x "$profile_python" ]]; then
        echo "Debug Python missing; run $0 setup first." >&2
        exit 1
    fi
    perf record -e cpu-clock:u -F 999 -g -o "$data" -- \
        "$profile_python" "$ROOT/profile_workload.py" pyflate "$variant" \
        --repetitions 15
    perf report --stdio --no-children -i "$data" \
        > "$RESULTS/pyflate_${variant}_perf_report.txt"
    "$ROOT/generate_flamegraph.sh" "$data"
}

case "$ACTION" in
    setup) setup ;;
    validate) validate ;;
    benchmark) benchmark ;;
    profile)
        profile_variant baseline
        profile_variant optimized
        ;;
    all)
        validate
        benchmark
        profile_variant baseline
        profile_variant optimized
        ;;
    *)
        echo "usage: $0 [setup|validate|benchmark|profile|all]" >&2
        exit 2
        ;;
esac
