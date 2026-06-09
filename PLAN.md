# PLAN

## Done (2026-06-09 EST)

### Issue 3 — direnv hang (racket source build) — FIXED
- [x] Diagnosed: `direnv allow` was compiling racket-8.18 from source (no aarch64-darwin
      binary cache for nixos-unstable / 25.05; narinfo 404).
- [x] Found cached racket: `nixos-24.11` → racket-8.14 (narinfo 200, full closure fetch-only).
- [x] Repinned `flake.nix` nixpkgs → `nixos-24.11`; `nix flake update nixpkgs`.
- [x] Materialized racket from cache; `direnv allow` / `nix develop` now fast (download).

### Test runner — FIXED (was broken out of the box)
- [x] `./test` now sets `PLTCOLLECTS=$(pwd):` so the in-repo collection resolves,
      runs via `nix develop`, uses `set -u` (not `set -e`), and excludes benchmarks
      (`*-bench.rkt`, `perf-test.rkt` which needs the external `pfds` pkg).

### Issue 1 — rename collection/#lang tab-racket → racket-sugar — DONE
- [x] Renamed dir `tab-racket/` → `racket-sugar/`; `tests/tab-racket-test.rkt`
      → `tests/racket-sugar-test.rkt`.
- [x] Replaced all 22 `tab-racket` occurrences → `racket-sugar` (info.rkt, flake pname,
      examples, tests, README, docs). Repo dir stays `racket_sugar` (project identifier).
- [x] Tests green after rename (68+7+38+16+7+8+2, zero failures).

### Issue 2 — README infix examples — DONE
- [x] Wove `~func` infix into marquee, Fibonacci, Conditionals, Let, Word-freq, and
      Typed-fib examples (binary ops only; structural forms stay prefix). Each converted
      snippet was executed and verified (fib→55, abs→5, let→30, typed fib→55).

## Done (2026-06-09 EST) — ./doctest (Elixir-style README doctests)
Hybrid: unannotated `#lang racket-sugar` blocks must run clean (exit 0); lines with
trailing `; => VALUE` also assert that program's stdout (ordered). `; doctest: skip`
opts a block out (illustrative examples with placeholder identifiers).
- [x] TDD pure core (parse-fenced-blocks, racket-sugar-block?, block-expectations,
      block-skip?, check-expectations) — tests/doctest-test.rkt, 9 tests.
- [x] `tools/doctest.rkt` harness (writes temp .trk at repo root for relative requires).
- [x] `./doctest [file]` wrapper (default README.md); folded into `./test` too.
- [x] Ran against real README; found + fixed 3 broken examples:
      - keywords example used spaces not tabs (would error on copy-paste) — fixed.
      - line-continuation example uses placeholder fns — marked `; doctest: skip`.
      - typed example failed type-check — rewrote to inference form + value checks.
- [x] Converted infix section `; → ..= N` comments → checkable `; => N`. All green.

## Real finding (surfaced by doctest) — needs decision
- [ ] `racket-sugar/typed`: an explicit value annotation on an imported parametric type
      (`: my-map HAMT` before `define my-map (hamt "key" 42)`) fails type-check — the
      value is seen as `Any`. Function-type annotations (`: fib (Integer ~-> Integer)`)
      work. Worth a failing test + fix in the typed reader. README now documents the
      workaround (let inference assign the type).

## Future language sugar ideas (from Peter)
- [ ] Add sugar to change the comment char from `;` to `//` (or `#`, but `#` collides
      with `#lang`/`#rx`/`#t`). Peter: "what the hell were they thinking?" re Lisp `;`.

## Open / optional
- [ ] Peter's extra ask: benchmark racket-sugar vs zig for an example algorithm
      (e.g. fibonacci) with hyperfine. Not yet done — awaiting go-ahead / which algorithm.
- [ ] flake `packages.default` has a pre-existing bug (`cp -r src` but there is no `src/`);
      unrelated to dev workflow. Fix if a buildable package output is wanted.
- [ ] racket pinned to 8.14 (cached) not latest 8.18 (uncached on darwin). Revisit if an
      8.15+ feature is needed.
