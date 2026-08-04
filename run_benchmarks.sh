#!/usr/bin/env bash
#
# Builds and runs every benchmark suite, then prints the comparison table.
#
# Any extra arguments are passed through to the compiler, which is how the
# suites are tuned:
#
#   ./run_benchmarks.sh -d:SAMPLE=10 -d:ENTITY_COUNT=100

set -euo pipefail

cd "$(dirname "$0")"

for src in src/*_bench.nim; do
    if ! nim c -r -d:danger -o:bench_runner "$@" "$src"; then
        echo "!!! Benchmark failed for $src" >&2
        exit 1
    fi
done

nim r src/results.nim
