#!/usr/bin/env python3
"""Summarize pyperf JSON results without altering the raw measurements."""

from __future__ import annotations

import statistics
from pathlib import Path

import pyperf


ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "results"


def load_values(path: Path) -> tuple[str, list[float]]:
    suite = pyperf.BenchmarkSuite.load(str(path))
    benchmarks = suite.get_benchmarks()
    if len(benchmarks) != 1:
        raise RuntimeError(f"expected one benchmark in {path}, found {len(benchmarks)}")
    benchmark = benchmarks[0]
    return benchmark.get_name(), list(benchmark.get_values())


def summarize(name: str) -> str:
    baseline_name, baseline = load_values(RESULTS / f"{name}_baseline.json")
    optimized_name, optimized = load_values(RESULTS / f"{name}_optimized.json")
    if baseline_name != optimized_name:
        raise RuntimeError(
            f"benchmark names differ: {baseline_name!r} and {optimized_name!r}"
        )
    baseline_mean = statistics.mean(baseline)
    optimized_mean = statistics.mean(optimized)
    baseline_stdev = statistics.stdev(baseline) if len(baseline) > 1 else 0.0
    optimized_stdev = statistics.stdev(optimized) if len(optimized) > 1 else 0.0
    speedup = baseline_mean / optimized_mean
    reduction = (baseline_mean - optimized_mean) / baseline_mean * 100.0
    return "\n".join(
        (
            f"[{name}]",
            f"baseline_mean_seconds={baseline_mean:.9f}",
            f"baseline_stdev_seconds={baseline_stdev:.9f}",
            f"optimized_mean_seconds={optimized_mean:.9f}",
            f"optimized_stdev_seconds={optimized_stdev:.9f}",
            f"speedup={speedup:.4f}x",
            f"time_reduction_percent={reduction:.2f}",
            f"requirement_met={'yes' if reduction >= 7.0 else 'no'}",
        )
    )


def main() -> None:
    sections = [summarize("nbody"), summarize("pyflate")]
    output = "\n\n".join(sections) + "\n"
    path = RESULTS / "summary.txt"
    path.write_text(output, encoding="utf-8")
    print(output, end="")


if __name__ == "__main__":
    main()
