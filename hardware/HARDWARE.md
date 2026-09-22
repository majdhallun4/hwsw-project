# HWSW Accelerator Examples

These examples isolate the inner operations that dominate the selected Python
benchmarks: all-pairs force evaluation in pyperformance N-body and repeated
variable-length code lookup in Pyflate. Both blocks use decoupled ready/valid
interfaces so a DMA front end can stop either side without losing data.

## 1. N-body pair interaction

`nbody_pair_accel.sv` evaluates one normalized pair force:

```text
F_a = m_a * m_b * inv_r3 * (position_b - position_a)
F_b = -F_a
```

The gravitational constant is normalized to `G = 1`. Software supplies
`inv_r3 = 1 / (distance^3)`, so the RTL does not claim to implement a square
root or reciprocal approximation. A production design could precede this block
with a piecewise-polynomial or lookup-table reciprocal-square-root pipeline.
Softening, `G`, and the integration time step can instead be folded into the
host-provided term.

### Numeric format and interface

| Signal group | Width and format | Meaning |
|---|---:|---|
| `in_pos_a_*`, `in_pos_b_*` | signed 32-bit Q16.16 | Two 3D positions |
| `in_mass_a`, `in_mass_b` | unsigned 32-bit Q16.16 | Non-negative masses |
| `in_inv_r3` | unsigned 32-bit Q2.30 | Host-computed reciprocal distance cubed |
| `out_force_a_*`, `out_force_b_*` | signed 32-bit Q16.16 | Saturated force or impulse components |

An input transfers when `in_valid && in_ready`; an output transfers when
`out_valid && out_ready`. The output register gives one-cycle latency when
unstalled and can accept one pair per cycle. Backpressure holds every output
bit stable. Saturation is symmetric at `+/-0x7fffffff`, which guarantees the two
reported vectors remain exactly equal and opposite.

The combinational implementation exposes three wide multiplier chains. For an
FPGA or a higher-frequency ASIC target, registers should be inserted between
mass multiplication, `inv_r3` multiplication, and the three component
multipliers. A reasonable architectural target is 100-200 MHz after that
pipelining, but this is an assumption, not a measured result.

### Software integration and tradeoffs

Software batches pair records into a DMA input ring and drains force records
from a DMA output ring. MMIO registers would hold ring addresses, lengths,
start/status, and interrupt control. CPU preprocessing computes softened
`inv_r3`; the accelerator replaces the repeated mass/delta/multiply portion of
the measured Python pair loop. Software accumulates each pair result into body
velocities and applies `dt`, preserving the benchmark's update order when
required.

This block deliberately does **not** offload the inverse-distance calculation,
which remains an important part of the measured kernel. A standalone PCIe
round-trip for ten pairs per time step would probably be slower than software.
The block is therefore a datapath study suitable only when integrated beside a
pair scheduler and reciprocal-square-root pipeline, or when many independent
pairs can be batched without a synchronization round-trip.

The design favors throughput and simple verification over area: three parallel
component multipliers avoid a three-cycle shared multiplier. Sharing that
multiplier reduces area and switching power but lowers pair throughput.
Fixed-point is much smaller than general floating point, but software must
range-check conversion. Overflow saturates; unsupported ranges, excessive
quantization error, or a requirement for bit-identical floating-point results
must fall back to the software kernel.

## 2. Canonical Huffman decoder

`huffman_decode_accel.sv` compares the next input bits against a programmable
table and returns a symbol plus the number of consumed bits. The default table
has 320 entries, enough for a DEFLATE literal/length alphabet with spare
entries. Codes may be 1 through 20 bits, covering DEFLATE's 15-bit maximum and
the longer lengths used conceptually by BZip2.

### Bit and table convention

The next stream bit is `in_bit_window[0]`. Each `cfg_code` is stored in
transmission order with its first bit in bit 0. The bit packer normalizes the
stream before lookup. DEFLATE bytes already expose the required least-significant
bit first ordering. For the exercised BZip2 path, which consumes each byte
most-significant bit first, the packer bit-reverses each input byte before
placing it in the window. This transformation is independent of code length:
for an input byte `abcdefgh`, it emits `a` into window bit 0, `b` into bit 1,
and so on. Software applies the same transmission-order conversion to each
known table code when programming `cfg_code`.

| Interface | Important fields | Behavior |
|---|---|---|
| Configuration | `cfg_index`, `cfg_enable`, `cfg_code`, `cfg_code_length`, `cfg_symbol` | One entry written on `cfg_valid && cfg_ready`; `cfg_error` pulses for an invalid index or enabled zero/out-of-range length |
| Decode input | 32-bit `in_bit_window`, 6-bit `in_bit_count` | One request on `in_valid && in_ready` |
| Decode output | 16-bit `out_symbol`, 5-bit `out_consumed_bits`, 3-bit `out_error` | One registered result, held under backpressure |

Error values are:

| Value | Name | Meaning |
|---:|---|---|
| 0 | `ERR_NONE` | Exactly one table entry matched |
| 1 | `ERR_NO_MATCH` | Available bits cannot match any entry |
| 2 | `ERR_NEED_MORE_BITS` | Available bits are a prefix of a longer entry |
| 3 | `ERR_TABLE` | Multiple entries matched; the programmed table is not prefix-free |
| 4 | `ERR_BIT_COUNT` | `in_bit_count` exceeds the physical bit-window width |

Configuration has priority over decode when both valid signals are asserted.
Reset discards a pending output and invalidates every table entry. The
un-pipelined reference has one-cycle response latency and accepts one window per
cycle when unstalled. Its parallel compare structure is intentionally clear for
presentation but is area-heavy. A synthesized implementation can bank entries
by code length, use a first-level prefix table, or map tables into SRAM. Those
choices reduce comparator power and area at the cost of extra latency. A
100-200 MHz target after banking/pipelining is an architectural assumption, not
a synthesis claim.

Pyflate spends substantial interpreter time extracting bits, walking
variable-length Huffman codes, and dispatching symbols. Software builds the
canonical table once per block, writes it through MMIO or a small configuration
DMA, then streams refillable 32-bit windows through the data DMA. It advances
its bit cursor by `out_consumed_bits`. Any reported error, unsupported alphabet,
or malformed stream returns control to the software decoder at the saved block
boundary.

BZip2 can define two to six Huffman tables and change the selected table every
50 decoded symbols. The submitted reference block stores one active table, so
a functionally correct integration must reprogram it when the selector changes.
That cost can erase acceleration. A production design should replicate or bank
the table memory six ways and add a selector input; the report's performance
estimate treats this banking as a required optimization rather than claiming it
exists in the reference RTL.

## Validation

The self-checking testbenches cover multiple exact vectors, output
backpressure, reset while an output is pending, saturation, variable code
lengths, truncated input, missing codes, ambiguous tables, bad configuration,
and invalid bit counts.

Run syntax/elaboration checks with:

```sh
make lint SLANG=/usr/intel/bin/slang
```

When Icarus Verilog is installed, compile and execute both tests with:

```sh
make test
```
