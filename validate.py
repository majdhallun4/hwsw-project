#!/usr/bin/env python3
"""Validate that both optimized workloads preserve their baseline results."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
from pathlib import Path
from types import ModuleType


ROOT = Path(__file__).resolve().parent
BENCHMARKS = ROOT / "benchmarks"
EXPECTED_PYFLATE_MD5 = "afa004a630fe072901b1d9628b960974"


def load_module(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_nbody() -> None:
    import numpy as np

    baseline = load_module("nbody_baseline_validation", BENCHMARKS / "nbody_baseline.py")
    optimized = load_module("nbody_optimized_validation", BENCHMARKS / "nbody_optimized.py")

    baseline_bodies = copy.deepcopy(baseline.SYSTEM)
    baseline_pairs = baseline.combinations(baseline_bodies)
    baseline.offset_momentum(baseline_bodies[0], baseline_bodies)
    baseline.advance(0.01, baseline.DEFAULT_ITERATIONS, baseline_bodies, baseline_pairs)
    baseline_energy = baseline.report_energy(baseline_bodies, baseline_pairs)

    positions = np.array([body[0] for body in optimized.SYSTEM], dtype=np.float64)
    velocities = np.array([body[1] for body in optimized.SYSTEM], dtype=np.float64)
    masses = np.array([body[2] for body in optimized.SYSTEM], dtype=np.float64)
    optimized.run_nbody_kernel(0, 0, 0.01, positions, velocities, masses)
    optimized.offset_momentum_array(0, velocities, masses)
    optimized.run_nbody_kernel(
        1,
        optimized.DEFAULT_ITERATIONS,
        0.01,
        positions,
        velocities,
        masses,
    )
    optimized_energy = optimized.report_energy_array(positions, velocities, masses)

    expected_positions = np.array([body[0] for body in baseline_bodies])
    expected_velocities = np.array([body[1] for body in baseline_bodies])
    np.testing.assert_allclose(positions, expected_positions, rtol=1e-12, atol=1e-12)
    np.testing.assert_allclose(velocities, expected_velocities, rtol=1e-12, atol=1e-12)
    np.testing.assert_allclose(optimized_energy, baseline_energy, rtol=1e-12, atol=1e-12)
    max_position_error = float(np.max(np.abs(positions - expected_positions)))
    max_velocity_error = float(np.max(np.abs(velocities - expected_velocities)))
    baseline_elapsed = baseline.bench_nbody(1, baseline.DEFAULT_REFERENCE, 100)
    optimized_elapsed = optimized.bench_nbody(1, optimized.DEFAULT_REFERENCE, 100)
    if baseline_elapsed <= 0.0 or optimized_elapsed <= 0.0:
        raise AssertionError("N-body benchmark entry point returned invalid timing")
    print(
        "PASS nbody: "
        f"energy={optimized_energy:.15f}, "
        f"max_position_error={max_position_error:.3e}, "
        f"max_velocity_error={max_velocity_error:.3e}"
    )


def decode_pyflate(module: ModuleType) -> bytes:
    input_path = BENCHMARKS / "data" / "interpreter.tar.bz2"
    with input_path.open("rb") as input_file:
        field = module.RBitfield(input_file)
        magic = field.readbits(16)
        if magic != 0x425A:
            raise RuntimeError(f"unexpected Pyflate input magic: {magic:#x}")
        return module.bzip2_main(field)


def validate_pyflate() -> None:
    baseline = load_module("pyflate_baseline_validation", BENCHMARKS / "pyflate_baseline.py")
    optimized = load_module("pyflate_optimized_validation", BENCHMARKS / "pyflate_optimized.py")
    baseline_output = decode_pyflate(baseline)
    optimized_output = decode_pyflate(optimized)
    if optimized_output != baseline_output:
        raise AssertionError("optimized Pyflate output differs from baseline")
    digest = hashlib.md5(optimized_output).hexdigest()
    if digest != EXPECTED_PYFLATE_MD5:
        raise AssertionError(f"unexpected Pyflate digest: {digest}")
    if len(optimized_output) != 399_360:
        raise AssertionError(f"unexpected Pyflate output length: {len(optimized_output)}")
    input_path = BENCHMARKS / "data" / "interpreter.tar.bz2"
    baseline_elapsed = baseline.bench_pyflake(1, input_path)
    optimized_elapsed = optimized.bench_pyflake(1, input_path)
    if baseline_elapsed <= 0.0 or optimized_elapsed <= 0.0:
        raise AssertionError("Pyflate benchmark entry point returned invalid timing")
    print(f"PASS pyflate: bytes={len(optimized_output)}, md5={digest}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--only",
        choices=("all", "nbody", "pyflate"),
        default="all",
        help="validate one benchmark or both",
    )
    args = parser.parse_args()
    if args.only in ("all", "nbody"):
        validate_nbody()
    if args.only in ("all", "pyflate"):
        validate_pyflate()


if __name__ == "__main__":
    main()
