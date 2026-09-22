# HWSW Project: N-body and Pyflate Optimization

## submitters
Majd Hallun - 326310174
Marwan Sariya - 213769284

This project analyzes and optimizes two approved `pyperformance` workloads:

- **N-body:** gravitational simulation of five solar-system bodies.
- **Pyflate:** pure-Python BZip2/DEFLATE decoding, exercised with the upstream
  `interpreter.tar.bz2` data set.

The repository contains the upstream baseline workloads, optimized versions,
correctness checks, repeatable `pyperf` measurements, Linux `perf` profiling,
flame-graph generation, and two SystemVerilog accelerator demonstrations.
An additional `python -m pyperformance run` captures the unmodified official
N-body and Pyflate benchmarks as a provenance cross-check. Vendored sources are
used for the controlled baseline/optimized comparison because the optimized
code must coexist with an unchanged, version-pinned reference.

## Optimization summary

### N-body

The baseline repeatedly executes the pairwise force and integration loops in
the CPython interpreter. The optimized version stores positions, velocities,
and masses in separate dense NumPy arrays and compiles the full time-step kernel
with Numba in nopython mode. Compilation is warmed before the timed region.
Fast-math transformations are deliberately disabled. Validation compares every
position and velocity and the final system energy against the baseline.

### Pyflate

The baseline reads compressed input one byte at a time, repeatedly constructs
bit masks, scans Huffman entries linearly, and rebuilds move-to-front lists by
slicing. The optimized version:

1. buffers the compressed input with one bulk read;
2. indexes bytes directly from the buffer;
3. uses precomputed bit masks;
4. groups canonical Huffman symbols by code length and performs dictionary
   lookup instead of a linear symbol scan; and
5. implements move-to-front with `pop` and `insert`.

Validation requires byte-for-byte equality and the upstream MD5 digest
`afa004a630fe072901b1d9628b960974`.

## Measured results

Measurements were collected inside the course QEMU VM on one pinned Intel Xeon
E5-2630 v3 vCPU using CPython 3.10.12 and 120 pyperf values per implementation.

| Benchmark | Baseline | Optimized | Speedup | Time reduction |
|---|---:|---:|---:|---:|
| N-body | 229.964 ms | 9.943 ms | 23.13x | 95.68% |
| Pyflate | 1.121246 s | 0.781945 s | 1.43x | 30.26% |

Both exceed the required 7% improvement. N-body state and energy match the
baseline; Pyflate output is byte-identical. Both RTL self-checking simulations
pass. See `report_nbody.txt`, `report_pyflate.txt`, and `results/` for the
analysis and raw evidence.

## Repository structure

```text
benchmarks/                 Baseline and optimized Python workloads
benchmarks/data/            Upstream Pyflate compressed input
hardware/                   Synthesizable RTL, testbenches, and design notes
diagrams/                   Hardware/software block diagrams
presentation/               Presentation source
results/                    Generated JSON, perf reports, and flame graphs
collect_system_info.sh      Captures the experimental environment
generate_flamegraph.sh      Converts perf samples to folded stacks and SVG
profile_workload.py         Deterministic long-running profiling workload
script_nbody.sh             N-body validation, benchmarking, and profiling
script_pyflate.sh           Pyflate validation, benchmarking, and profiling
setup_vm.sh                 Installs VM tools and Python dependencies
validate.py                 Cross-implementation correctness tests
prompt.txt                  AI-use disclosure
```

## Reproduce on the course VM

Run all commands **inside the QEMU guest**, not on the `naranja10` host.

```bash
cd /root/hwsw_final_project
chmod +x *.sh hardware/run_tests.sh
./setup_vm.sh
./run_all.sh
```

`run_all.sh` can take several minutes because it uses rigorous `pyperf`
settings and captures four sampling profiles. Individual stages are:

```bash
./script_nbody.sh validate
./script_nbody.sh benchmark
./script_nbody.sh profile
./script_pyflate.sh validate
./script_pyflate.sh benchmark
./script_pyflate.sh profile
./run_official_reference.sh
./hardware/run_tests.sh
```

The benchmark scripts pin execution to CPU 0 by default. Override this only if
that CPU is unavailable:

```bash
CPU_CORE=1 ./script_nbody.sh benchmark
```

## Generated evidence

After a complete run, `results/` contains:

- baseline and optimized `pyperf` JSON files;
- plain-text comparison tables;
- baseline and optimized `perf report --stdio` files;
- folded stack files and SVG flame graphs; and
- OS, CPU, Python, dependency, and perf metadata.

The raw JSON and `perf.data` files are evidence; do not hand-edit them.
The submission archive retains timing JSON, text profiler reports, concise
result logs, and SVG flame graphs. It omits raw `perf.data`, folded-stack
intermediates, and redundant setup/run logs; those remain available in the
original VM result archive.

## Measurement rules

- Use the same VM boot, Python environment, CPU affinity, and workload for each
  baseline/optimized pair.
- Run no unrelated workloads during measurement.
- Keep Numba compilation outside the timed region, but report cold compilation
  latency separately when discussing deployment trade-offs.
- Treat virtualized hardware counters cautiously. Wall-clock values and sampled
  call stacks are primary evidence if PMU counters are unavailable or invalid.
- Do not report a speedup until `pyperf compare_to` confirms it on the course VM.

## Hardware integration

The RTL is an executable design model, not a taped-out device. `hardware/HARDWARE.md`
defines the data formats, ready/valid protocols, latency assumptions, host API,
DMA/MMIO integration, fallback behavior, and performance/area/power trade-offs.
The block diagrams under `diagrams/` show the software-visible integration.
The 16-slide presentation is supplied as both PPTX and PDF under
`presentation/`.

## Attribution

See `THIRD_PARTY_NOTICES.md`. The baseline benchmark sources and Pyflate data
come from `python/pyperformance` 1.14.0.
