# Quicksort: racket-sugar vs Zig vs Elixir, mutable vs immutable

A cross-language / cross-paradigm quicksort benchmark. The single-language entries
come from [Rosetta Code](https://rosettacode.org/wiki/Sorting_algorithms/Quicksort);
the mutable-Racket entry is added to isolate *one* variable at a time.

## Implementations

| file | language | style | allocates? |
|---|---|---|---|
| `quicksort.zig` | Zig 0.16 (ReleaseFast) | in-place **array** | no |
| `quicksort-mutable.trk` | racket-sugar | in-place **vector** (Lomuto) | no |
| `quicksort.trk` | racket-sugar | functional **list** (`partition`/`append`) | yes |
| `quicksort.exs` | Elixir / BEAM (OTP 27) | functional **list** | yes |

## Fairness controls

- **Identical input.** All four generate the same MINSTD sequence
  (`x = 48271·x mod 2147483647`, seed 42).
- **Correctness cross-check.** All four print the same order-dependent checksum
  (`Σ (i+1)·arr[i] mod 1e9+7`); the runner aborts on any mismatch.
- **Execution, not compilation.** Zig is built ReleaseFast and the `.trk`s are
  `raco make`-compiled before timing; `hyperfine --warmup` excludes cold starts.
- **No I/O skew.** Data is generated in-process.

## Results (Apple aarch64; Zig 0.16, Racket CS 8.14, Erlang/OTP 27 JIT; n = 1,000,000)

| implementation | total | startup | **sort-only** | sort vs Zig |
|---|---:|---:|---:|---:|
| Zig (in-place array, native) | 61 ms | ~1.5 ms | ~60 ms | 1.0× |
| racket-sugar (mutable vector) | 277 ms | ~150 ms | ~127 ms | 2.1× |
| racket-sugar (immutable list) | 566 ms | ~150 ms | ~416 ms | 6.9× |
| Elixir (immutable list) | 652 ms | ~266 ms | ~386 ms | 6.4× |

("sort-only" subtracts each runtime's fixed startup — see below.)

### What this shows

- **The price of persistence (same runtime).** Racket's immutable-list quicksort costs
  **~2× total / ~3.3× sort-only** versus the in-place mutable-vector version. That gap is
  pure allocation + GC from building new lists instead of mutating in place — the cost of
  immutability, measured cleanly with everything else held constant.
- **Mutable functional code is close to native.** In-place racket-sugar is only ~2.1× a
  hand-written in-place Zig sort — the managed runtime itself is fast; most of the earlier
  "8×" headline was immutability + startup, not the language.
- **Elixir: startup dominates, the sort doesn't.** On total wall-clock Elixir is slowest,
  but only because BEAM boots in ~266 ms. Its *sort* (~386 ms) is actually a hair faster
  than Racket's immutable list (~416 ms) — OTP 27's JIT is no slouch at list recursion.

## Why does Racket "compile" yet still start in ~150 ms?

`raco make` produces **`.zo` bytecode, not a native executable**. The `racket` binary is
what's native; it *loads* that bytecode. The startup cost is library instantiation:

| stage | time |
|---|---:|
| Racket CS runtime boot (`racket -n`) | 69 ms |
| `#lang racket/base` | 79 ms |
| `#lang racket` (full stdlib) | 151 ms |
| `#lang racket-sugar` | ~158 ms |

So ~half of startup is bringing up the full `#lang racket` standard library — which
`racket-sugar` currently expands to. Expanding to `racket/base` + explicit requires would
roughly halve startup (79 vs 151 ms), at the cost of more `require`s in user code.
(`raco exe` bundles a standalone executable but still instantiates these libraries, so it
doesn't materially change the picture.) Zig, by contrast, is a static native binary with a
~1.5 ms exec cost and no runtime to boot.

## Reproduce

```bash
./benchmarks/quicksort/bench           # n = 1,000,000
./benchmarks/quicksort/bench 3000000   # custom n
```
