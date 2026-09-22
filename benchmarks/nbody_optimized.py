"""
N-body benchmark from the Computer Language Benchmarks Game.

This is intended to support Unladen Swallow's pyperf.py. Accordingly, it has been
modified from the Shootout version:
- Accept standard Unladen Swallow benchmark options.
- Run report_energy()/advance() in a loop.
- Reimplement itertools.combinations() to work with older Python versions.

Pulled from:
http://benchmarksgame.alioth.debian.org/u64q/program.php?test=nbody&lang=python3&id=1

Contributed by Kevin Carson.
Modified by Tupteq, Fredrik Johansson, and Daniel Nanz.
"""

import math

import numpy as np
import pyperf
from numba import njit

__contact__ = "collinwinter@google.com (Collin Winter)"
DEFAULT_ITERATIONS = 20000
DEFAULT_REFERENCE = 'sun'


def combinations(l):
    """Pure-Python implementation of itertools.combinations(l, 2)."""
    result = []
    for x in range(len(l) - 1):
        ls = l[x + 1:]
        for y in ls:
            result.append((l[x], y))
    return result


PI = 3.14159265358979323
SOLAR_MASS = 4 * PI * PI
DAYS_PER_YEAR = 365.24

BODIES = {
    'sun': ([0.0, 0.0, 0.0], [0.0, 0.0, 0.0], SOLAR_MASS),

    'jupiter': ([4.84143144246472090e+00,
                 -1.16032004402742839e+00,
                 -1.03622044471123109e-01],
                [1.66007664274403694e-03 * DAYS_PER_YEAR,
                 7.69901118419740425e-03 * DAYS_PER_YEAR,
                 -6.90460016972063023e-05 * DAYS_PER_YEAR],
                9.54791938424326609e-04 * SOLAR_MASS),

    'saturn': ([8.34336671824457987e+00,
                4.12479856412430479e+00,
                -4.03523417114321381e-01],
               [-2.76742510726862411e-03 * DAYS_PER_YEAR,
                4.99852801234917238e-03 * DAYS_PER_YEAR,
                2.30417297573763929e-05 * DAYS_PER_YEAR],
               2.85885980666130812e-04 * SOLAR_MASS),

    'uranus': ([1.28943695621391310e+01,
                -1.51111514016986312e+01,
                -2.23307578892655734e-01],
               [2.96460137564761618e-03 * DAYS_PER_YEAR,
                2.37847173959480950e-03 * DAYS_PER_YEAR,
                -2.96589568540237556e-05 * DAYS_PER_YEAR],
               4.36624404335156298e-05 * SOLAR_MASS),

    'neptune': ([1.53796971148509165e+01,
                 -2.59193146099879641e+01,
                 1.79258772950371181e-01],
                [2.68067772490389322e-03 * DAYS_PER_YEAR,
                 1.62824170038242295e-03 * DAYS_PER_YEAR,
                 -9.51592254519715870e-05 * DAYS_PER_YEAR],
                5.15138902046611451e-05 * SOLAR_MASS)}


SYSTEM = list(BODIES.values())
PAIRS = combinations(SYSTEM)
BODY_NAMES = tuple(BODIES)
POSITIONS = np.array([body[0] for body in SYSTEM], dtype=np.float64)
VELOCITIES = np.array([body[1] for body in SYSTEM], dtype=np.float64)
MASSES = np.array([body[2] for body in SYSTEM], dtype=np.float64)


def advance(dt, n, bodies=SYSTEM, pairs=PAIRS):
    for i in range(n):
        for (([x1, y1, z1], v1, m1),
             ([x2, y2, z2], v2, m2)) in pairs:
            dx = x1 - x2
            dy = y1 - y2
            dz = z1 - z2
            mag = dt * ((dx * dx + dy * dy + dz * dz) ** (-1.5))
            b1m = m1 * mag
            b2m = m2 * mag
            v1[0] -= dx * b2m
            v1[1] -= dy * b2m
            v1[2] -= dz * b2m
            v2[0] += dx * b1m
            v2[1] += dy * b1m
            v2[2] += dz * b1m
        for (r, [vx, vy, vz], m) in bodies:
            r[0] += dt * vx
            r[1] += dt * vy
            r[2] += dt * vz


def report_energy(bodies=SYSTEM, pairs=PAIRS, e=0.0):
    for (((x1, y1, z1), v1, m1),
         ((x2, y2, z2), v2, m2)) in pairs:
        dx = x1 - x2
        dy = y1 - y2
        dz = z1 - z2
        e -= (m1 * m2) / ((dx * dx + dy * dy + dz * dz) ** 0.5)
    for (r, [vx, vy, vz], m) in bodies:
        e += m * (vx * vx + vy * vy + vz * vz) / 2.
    return e


def offset_momentum(ref, bodies=SYSTEM, px=0.0, py=0.0, pz=0.0):
    for (r, [vx, vy, vz], m) in bodies:
        px -= vx * m
        py -= vy * m
        pz -= vz * m
    (r, v, m) = ref
    v[0] = px / m
    v[1] = py / m
    v[2] = pz / m


@njit
def offset_momentum_array(reference, velocities, masses):
    px = 0.0
    py = 0.0
    pz = 0.0
    for index in range(masses.shape[0]):
        mass = masses[index]
        px -= velocities[index, 0] * mass
        py -= velocities[index, 1] * mass
        pz -= velocities[index, 2] * mass
    velocities[reference, 0] = px / masses[reference]
    velocities[reference, 1] = py / masses[reference]
    velocities[reference, 2] = pz / masses[reference]


@njit
def report_energy_array(positions, velocities, masses):
    energy = 0.0
    body_count = masses.shape[0]
    for first in range(body_count - 1):
        for second in range(first + 1, body_count):
            dx = positions[first, 0] - positions[second, 0]
            dy = positions[first, 1] - positions[second, 1]
            dz = positions[first, 2] - positions[second, 2]
            distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            energy -= masses[first] * masses[second] / distance
    for index in range(body_count):
        vx = velocities[index, 0]
        vy = velocities[index, 1]
        vz = velocities[index, 2]
        energy += masses[index] * (vx * vx + vy * vy + vz * vz) / 2.0
    return energy


@njit
def run_nbody_kernel(loops, iterations, dt, positions, velocities, masses):
    checksum = 0.0
    body_count = masses.shape[0]
    for _ in range(loops):
        checksum += report_energy_array(positions, velocities, masses)
        for _ in range(iterations):
            for first in range(body_count - 1):
                for second in range(first + 1, body_count):
                    dx = positions[first, 0] - positions[second, 0]
                    dy = positions[first, 1] - positions[second, 1]
                    dz = positions[first, 2] - positions[second, 2]
                    distance_squared = dx * dx + dy * dy + dz * dz
                    mag = dt * distance_squared ** (-1.5)
                    first_mass = masses[first] * mag
                    second_mass = masses[second] * mag
                    velocities[first, 0] -= dx * second_mass
                    velocities[first, 1] -= dy * second_mass
                    velocities[first, 2] -= dz * second_mass
                    velocities[second, 0] += dx * first_mass
                    velocities[second, 1] += dy * first_mass
                    velocities[second, 2] += dz * first_mass
            for index in range(body_count):
                positions[index, 0] += dt * velocities[index, 0]
                positions[index, 1] += dt * velocities[index, 1]
                positions[index, 2] += dt * velocities[index, 2]
        checksum += report_energy_array(positions, velocities, masses)
    return checksum


def bench_nbody(loops, reference, iterations):
    # Compile before timing so the measurement represents steady-state execution.
    run_nbody_kernel(0, iterations, 0.01, POSITIONS, VELOCITIES, MASSES)
    offset_momentum_array(BODY_NAMES.index(reference), VELOCITIES, MASSES)
    t0 = pyperf.perf_counter()
    checksum = run_nbody_kernel(
        loops,
        iterations,
        0.01,
        POSITIONS,
        VELOCITIES,
        MASSES,
    )
    elapsed = pyperf.perf_counter() - t0
    if not math.isfinite(checksum):
        raise RuntimeError("N-body energy checksum is not finite")
    return elapsed


def add_cmdline_args(cmd, args):
    cmd.extend(("--iterations", str(args.iterations)))


if __name__ == '__main__':
    runner = pyperf.Runner(add_cmdline_args=add_cmdline_args)
    runner.metadata['description'] = "Numba-compiled n-body benchmark"
    runner.metadata['optimization'] = "NumPy structure-of-arrays plus Numba JIT"
    runner.argparser.add_argument("--iterations",
                                  type=int, default=DEFAULT_ITERATIONS,
                                  help="Number of nbody advance() iterations "
                                       "(default: %s)" % DEFAULT_ITERATIONS)
    runner.argparser.add_argument("--reference",
                                  type=str, default=DEFAULT_REFERENCE,
                                  help="nbody reference (default: %s)"
                                       % DEFAULT_REFERENCE)

    args = runner.parse_args()
    runner.bench_time_func('nbody', bench_nbody,
                           args.reference, args.iterations)
