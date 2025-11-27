#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
exec racket test/perf-test.rkt
