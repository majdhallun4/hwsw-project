#!/usr/bin/env python3
"""Run a long, deterministic workload suitable for Linux perf sampling."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
from pathlib import Path
from types import ModuleType


ROOT = Path(__file__).resolve().parent
BENCHMARKS = ROOT / "benchmarks"


def load_module(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def profile_nbody(variant: str, repetitions: int) -> None:
    module = load_module(f"nbody_{variant}_profile", BENCHMARKS / f"nbody_{variant}.py")
    if variant == "baseline":
        bodies = copy.deepcopy(module.SYSTEM)
        pairs = module.combinations(bodies)
        module.offset_momentum(bodies[0], bodies)
        checksum = 0.0
        for _ in range(repetitions):
            checksum += module.report_energy(bodies, pairs)
            module.advance(0.01, module.DEFAULT_ITERATIONS, bodies, pairs)
            checksum += module.report_energy(bodies, pairs)
    else:
        import numpy as np

        positions = np.array([body[0] for body in module.SYSTEM], dtype=np.float64)
        velocities = np.array([body[1] for body in module.SYSTEM], dtype=np.float64)
        masses = np.array([body[2] for body in module.SYSTEM], dtype=np.float64)
        module.run_nbody_kernel(0, 0, 0.01, positions, velocities, masses)
        module.offset_momentum_array(0, velocities, masses)
        checksum = module.run_nbody_kernel(
            repetitions,
            module.DEFAULT_ITERATIONS,
            0.01,
            positions,
            velocities,
            masses,
        )
    print(f"nbody_{variant}_energy_checksum={checksum:.15f}")


def decode_pyflate(module: ModuleType) -> bytes:
    with (BENCHMARKS / "data" / "interpreter.tar.bz2").open("rb") as input_file:
        field = module.RBitfield(input_file)
        magic = field.readbits(16)
        if magic != 0x425A:
            raise RuntimeError(f"unexpected Pyflate input magic: {magic:#x}")
        return module.bzip2_main(field)


def profile_pyflate(variant: str, repetitions: int) -> None:
    module = load_module(f"pyflate_{variant}_profile", BENCHMARKS / f"pyflate_{variant}.py")
    output = b""
    for _ in range(repetitions):
        output = decode_pyflate(module)
    print(
        f"pyflate_{variant}_bytes={len(output)},"
        f"md5={hashlib.md5(output).hexdigest()}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("benchmark", choices=("nbody", "pyflate"))
    parser.add_argument("variant", choices=("baseline", "optimized"))
    parser.add_argument("--repetitions", type=int, default=10)
    args = parser.parse_args()
    if args.repetitions <= 0:
        parser.error("--repetitions must be positive")
    if args.benchmark == "nbody":
        profile_nbody(args.variant, args.repetitions)
    else:
        profile_pyflate(args.variant, args.repetitions)


if __name__ == "__main__":
    main()
