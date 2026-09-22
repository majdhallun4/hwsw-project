#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ "$(id -u)" -eq 0 ]]; then
    apt-get update
    apt-get install -y git graphviz iverilog linux-tools-common python3-dbg python3-venv
    if ! apt-get install -y "linux-tools-$(uname -r)"; then
        echo "Kernel-specific perf package unavailable; trying generic tools." >&2
        apt-get install -y linux-tools-generic
    fi
fi

python3 -m venv .venv
.venv/bin/python3 -m pip install --upgrade pip
.venv/bin/python3 -m pip install -r requirements.txt

python3-dbg -m venv .venv-dbg
.venv-dbg/bin/python3 -m pip install --upgrade pip
.venv-dbg/bin/python3 -m pip install pyperf==2.10.0

if [[ ! -d FlameGraph ]]; then
    git clone --depth 1 https://github.com/brendangregg/FlameGraph.git
fi

echo "Setup complete."
.venv/bin/python3 --version
.venv/bin/python3 -m pyperformance --version
perf --version
iverilog -V 2>&1 | head -1
