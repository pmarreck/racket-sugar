# Quicksort: racket-sugar vs Zig

A cross-language quicksort benchmark using the [Rosetta Code](https://rosettacode.org/wiki/Sorting_algorithms/Quicksort)
implementations of each language, adapted only enough to be measurable and to
**cross-check each other**.

## What's being compared

| | `quicksort.trk` (racket-sugar) | `quicksort.zig` (Zig 0.16) |
|---|---|---|
| Source | Rosetta Code Racket entry, in tab syntax | Rosetta Code Zig entry |
| Style | Functional, **list**-based, immutable | In-place, mutable **array** |
| Allocates | Yes (new lists via `partition`/`append`) | No (sorts in place) |
| Build | `raco make` (precompiled bytecode) | `zig build-exe -O ReleaseFast` |

These are intentionally the *idiomatic* version in each language — that's what
Rosetta shows, and it's an honest reflection of how each community writes it.

## Fairness controls

- **Identical input.** Both generate the same sequence with the same MINSTD LCG
  (`x = 48271·x mod 2147483647`, seed 42), so neither benefits from "easier" data.
- **No I/O skew.** Data is generated in-process; nothing is read/parsed from disk.
- **Correctness cross-check.** Both print the same order-dependent checksum
  (`Σ (i+1)·arr[i] mod 1e9+7`). The runner aborts on mismatch — a wrong sort can't
  look fast.
- **Execution, not compilation.** The `.trk` is `raco make`-compiled and the Zig is
  built once before timing; `hyperfine --warmup` excludes cold starts.

## Results (Apple aarch64, Zig 0.16, Racket CS 8.14)

End-to-end process time (`hyperfine -N`):

| n | racket-sugar | Zig ReleaseFast | total ratio |
|---:|---:|---:|---:|
| 1,000,000 | 508 ms | 59 ms | 8.6× |
| 3,000,000 | 1.51 s | 192 ms | 7.9× |

Fixed overhead: racket-sugar ~148 ms (runtime boot + `#lang` reader load), Zig ~1.5 ms.
Subtracting startup, the **pure sort** gap is ≈ **6–7×**.

That a GC'd, fully-immutable, list-based functional quicksort lands within ~6–7× of
hand-written in-place Zig says a lot about the Racket CS (Chez) backend.

## Reproduce

```bash
./benchmarks/quicksort/bench           # n = 1,000,000
./benchmarks/quicksort/bench 3000000   # custom n
```
