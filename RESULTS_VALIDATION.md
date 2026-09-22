# Results validation

The result archive was collected on 2026-09-14 inside the course QEMU VM and
checked before final packaging.

## Acceptance checks

| Check | Result |
|---|---|
| Archive integrity | Passed gzip/tar integrity check |
| N-body state and energy | Exact values matched for the validation workload |
| Pyflate output | Byte-identical, 399,360 bytes, expected MD5 |
| N-body improvement | 23.1288x; 95.68% less time |
| Pyflate improvement | 1.4339x; 30.26% less time |
| Required 7% threshold | Passed for both benchmarks |
| Perf sample loss | Zero for all four profiles |
| N-body RTL simulation | Passed |
| Huffman RTL simulation | Passed |

Each controlled benchmark contains 120 measured pyperf values. The official
pyperformance references (231 ms N-body and 1.11 s Pyflate) agree with the
vendored baselines (230 ms and 1.12 s), supporting baseline fidelity.

## Caveats

- Pyperf warns that the optimized N-body run cannot establish less than 1%
  variation with 95% confidence. Its coefficient of variation is 2.52%, but
  the slowest optimized value is still over 20 times faster than the fastest
  baseline value, so this does not affect the threshold conclusion.
- Perf could not resolve kernel symbols because `kptr_restrict` remained
  enabled. Profiles record user-space CPU clock only, report zero lost samples,
  and resolve the important CPython/libm symbols. Kernel frames are not used in
  the analysis.
- Icarus reports that constant selects in `always_*` are handled by including
  all bits in the sensitivity calculation. This is a simulator implementation
  notice, not a compile or functional failure; both self-checking simulations
  pass.
- Hardware throughput, frequency, area, and power are analytical design
  assumptions. No synthesis or physical accelerator measurement is claimed.
