# PLAN

## In flight (2026-06-09)

### Issue 3 — direnv hang (racket source build) — FIX APPLIED, verifying
- [x] Diagnose: `direnv allow` was compiling racket-8.18 from source (no darwin binary
      cache for nixos-unstable / 25.05). Confirmed via narinfo 404.
- [x] Find cached racket: `nixos-24.11` → racket-8.14, narinfo 200, full closure fetch-only.
- [x] Repin `flake.nix` nixpkgs → `nixos-24.11`; `nix flake update nixpkgs`.
- [ ] Materialize racket in store (`nix develop`), confirm `direnv allow` is fast.

### Establish green baseline (blocked on racket download)
- [ ] `raco test tests` → record pass/fail before any rename.

### Issue 1 — rename tab-racket → racket-sugar
Decision: Racket collection / `#lang` = `racket-sugar` (hyphen, Racket-idiomatic).
Repo directory stays `racket_sugar` (underscore = project identifier). `.trk` ext KEPT.
- [ ] Rename collection dir `tab-racket/` → `racket-sugar/`.
- [ ] Update `info.rkt` collection name.
- [ ] Update all `#lang tab-racket` / `#lang tab-racket/typed` in examples, tests, README.
- [ ] Update `flake.nix` pname + description.
- [ ] Update docs (PROJECT_PLAN.md, HAMT_*.md) and test filenames referencing tab-racket.
- [ ] `raco test tests` → green again after rename.

### Issue 2 — README infix examples
Decision: weave `~func` infix into marquee/gallery examples (keep existing section).
Convert binary prefix ops only: `(+ 1 2)`→`1 ~+ 2`, `(= n 0)`→`(n ~= 0)`, `(- n 1)`→`(n ~- 1)`.
Structural forms (cond/define/if/let) stay prefix.
- [ ] Convert intro example, Fibonacci, Conditionals, Let, Word-freq examples.

### Peter's extra ask — benchmark racket vs zig
- [ ] Once racket is up, time an example algorithm (e.g. fibonacci) vs a zig equivalent
      with hyperfine. Report numbers; do not over-engineer.
