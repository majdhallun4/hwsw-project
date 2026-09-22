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
    "$PYTHON" "$ROOT/validate.py" --only nbody
}

benchmark() {
    ensure_environment
    rm -f "$RESULTS/nbody_baseline.json" "$RESULTS/nbody_optimized.json"
    "$PYTHON" "$ROOT/measure_nbody_jit_startup.py" \
        > "$RESULTS/nbody_jit_cold_start.txt"
    taskset -c "$CPU_CORE" "$PYTHON" "$ROOT/benchmarks/nbody_baseline.py" \
        --rigorous -o "$RESULTS/nbody_baseline.json"
    taskset -c "$CPU_CORE" "$PYTHON" "$ROOT/benchmarks/nbody_optimized.py" \
        --rigorous -o "$RESULTS/nbody_optimized.json"
    "$PYTHON" -m pyperf compare_to \
        "$RESULTS/nbody_baseline.json" "$RESULTS/nbody_optimized.json" \
        --table > "$RESULTS/nbody_comparison.txt"
    cat "$RESULTS/nbody_comparison.txt"
}

profile_variant() {
    local variant="$1"
    local data="$RESULTS/nbody_${variant}.perf.data"
    local profile_python="$ROOT/.venv-dbg/bin/python3"
    local repetitions=60
    local perf_delay=()
    ensure_environment
    if [[ "$variant" == "optimized" ]]; then
        profile_python="$PYTHON"
        repetitions=1500
        perf_delay=(--delay 2000)
    elif [[ ! -x "$profile_python" ]]; then
        echo "Debug Python missing; run $0 setup first." >&2
        exit 1
    fi
    perf record -e cpu-clock:u -F 999 -g "${perf_delay[@]}" -o "$data" -- \
        "$profile_python" "$ROOT/profile_workload.py" nbody "$variant" \
        --repetitions "$repetitions"
    perf report --stdio --no-children -i "$data" \
        > "$RESULTS/nbody_${variant}_perf_report.txt"
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
