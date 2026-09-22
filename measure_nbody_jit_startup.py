#!/usr/bin/env python3
"""Measure Numba import and first-compilation latency in a fresh process."""

from __future__ import annotations

import importlib.util
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "benchmarks" / "nbody_optimized.py"


start = time.perf_counter()
spec = importlib.util.spec_from_file_location("nbody_optimized_cold", SOURCE)
if spec is None or spec.loader is None:
    raise RuntimeError(f"cannot load {SOURCE}")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
after_import = time.perf_counter()
module.run_nbody_kernel(
    0,
    module.DEFAULT_ITERATIONS,
    0.01,
    module.POSITIONS,
    module.VELOCITIES,
    module.MASSES,
)
after_compile = time.perf_counter()

print(f"import_seconds={after_import - start:.9f}")
print(f"first_compile_seconds={after_compile - after_import:.9f}")
print(f"cold_start_total_seconds={after_compile - start:.9f}")
