# Quicksort: native vs managed, mutable vs immutable, typed vs untyped

A cross-language / cross-paradigm sorting benchmark. Single-language entries come from
[Rosetta Code](https://rosettacode.org/wiki/Sorting_algorithms/Quicksort); the rest are
added to isolate one variable at a time. Every implementation generates the **same**
MINSTD input and prints the **same** order-dependent checksum, so they cross-check each
other (the runner aborts on any mismatch — a wrong sort can't look fast).

## Implementations

| file | language / dialect | algorithm | data |
|---|---|---|---|
| `quicksort.zig` | Zig 0.16 (ReleaseFast) | quicksort, in-place | mutable array |
| `quicksort-mutable.trk` / `-typed.trk` | racket-sugar (untyped / typed) | quicksort, in-place | mutable vector |
| `quicksort.trk` / `quicksort-typed.trk` | racket-sugar (untyped / typed) | quicksort, functional | immutable list |
| `stdsort.trk` / `stdsort-typed.trk` | racket-sugar (untyped / typed) | built-in `sort` (merge sort) | immutable list |
| `quicksort.exs` | Elixir / BEAM (OTP 27) | quicksort, functional | immutable list |
| `stdsort.exs` | Elixir / BEAM | built-in `Enum.sort` (merge sort) | immutable list |

## Results (Apple aarch64; Zig 0.16, Racket CS 8.14, Erlang/OTP 27 JIT; n = 1,000,000)

End-to-end process time (`hyperfine -N --warmup`), representative run:

| implementation | total | vs Zig |
|---|---:|---:|
| Zig — in-place array | ~62 ms | 1.0× |
| racket-sugar — mutable vector (untyped) | ~285 ms | ~4.6× |
| racket-sugar — built-in `sort` (untyped) | ~300 ms | ~4.8× |
| racket-sugar — mutable vector (typed) | ~380 ms | ~6.1× |
| racket-sugar — built-in `sort` (typed) | ~414 ms | ~6.7× |
| Elixir — built-in `Enum.sort` | ~475 ms | ~7.6× |
| racket-sugar — immutable list quicksort (untyped) | ~565 ms | ~9.1× |
| Elixir — immutable list quicksort | ~700 ms | ~11× |
| racket-sugar — immutable list quicksort (typed) | ~730 ms | ~12× |

Fixed startup (subtract for "sort-only"): Zig ~1.5 ms, Racket ~150 ms, BEAM ~266 ms.

## Four things this measures

**1. The price of persistence (same runtime).** Immutable-list quicksort vs in-place
mutable-vector quicksort in Racket: ~2× total, ~3× sort-only. That gap is pure
allocation + GC from rebuilding lists — the cost of immutability, with everything else
held constant. *You opt into it at will*: pay the tax and get the guarantee, or use a
mutable vector and leave it on the table.

**2. Algorithm beats mutability — immutability is ~free with the right algorithm.**
Racket's **immutable** built-in `sort` (~300 ms) is as fast as the hand-rolled **mutable**
quicksort (~285 ms), and ~2× faster than the immutable *quicksort*. Quicksort is
intrinsically in-place, so doing it on immutable lists fights the algorithm; merge sort
(what `sort`/`Enum.sort` use) is naturally functional. **The "immutability tax" was an
algorithm mismatch, not immutability itself.**

**3. Types here cost speed, they don't buy it.** Every typed variant is ~25–35% *slower*
than its untyped twin. Reason: the code is typed with `Integer`, which is
arbitrary-precision — Typed Racket's numeric optimizer can't specialize it, so you get
the same generic arithmetic *plus* boundary/check overhead. Types here are for safety and
documentation, not speed. (Typing the hot paths with `Fixnum`/`Index` instead would let
the TR optimizer kick in and could *flip* this — a worthwhile follow-up.)

**4. Elixir: startup dominates, the sort competes.** On total time the BEAM's ~266 ms boot
makes Elixir look slow, but its *sorts* are competitive (Enum.sort ~209 ms sort-only vs
Racket's ~150 ms; OTP 27's JIT is no slouch).

## Why does Racket "compile" yet start in ~150 ms?

`raco make` emits **`.zo` bytecode, not a native binary** — the `racket` executable is
native and *loads* the bytecode. The startup is library instantiation:

| stage | time |
|---|---:|
| Racket CS runtime boot (`racket -n`) | 69 ms |
| `#lang racket/base` | 79 ms |
| `#lang racket` (full stdlib) | 151 ms |
| `#lang racket-sugar` | ~158 ms |

~Half is bringing up the full `#lang racket` stdlib that racket-sugar expands to;
`racket/base` + explicit requires would roughly halve it. Zig is a static native binary
(~1.5 ms exec, no runtime to boot).

## Note on typed racket-sugar syntax

The typed variants use the racket-sugar annotation surface — `:` annotations and `~->`
arrows — and importantly **no `ann`**: typed lambda parameters are written with
*paren-grouped* params, `(lambda ((e : Integer)) …)`, which Typed Racket accepts natively
because Racket treats `()` and `[]` as the same datum. (racket-sugar reserves `[]` for
persistent vectors, so the bracket form `[e : T]` is unavailable — but parens substitute
everywhere `[]` would normally be used.)

## Reproduce

```bash
./benchmarks/quicksort/bench           # n = 1,000,000
./benchmarks/quicksort/bench 3000000   # custom n
```
