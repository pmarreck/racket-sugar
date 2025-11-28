# Project Plan

## Goal
Create a Racket syntax variant that uses significant **tab-based** indentation instead of parentheses, with CLI converters to and from standard Racket, managed via Nix flake. "Done" when:
- #lang loads and runs tab-indented code.
- Tests pass.

## Status: ✅ Core Complete

The core `tab-racket` language is functional with the following features:

### Completed Features
- **Tab-based significant indentation** - `#lang tab-racket` parses tabs-only indentation
- **Typed variant** - `#lang tab-racket/typed` for full type annotations
- **Persistent data structures** - `[]` for PVector, `{}` for HAMT with O(log n) operations
- **Self-evaluating keywords** - `:foo` symbols auto-quote like Clojure/Ruby/Elixir atoms
- **File extension convention** - `.trk` for tab-racket source files
- **Comprehensive test suite** - Unit tests + integration tests for all examples
- **Production examples** - ARC and S3-FIFO cache implementations with benchmarks

### Original Milestones
- ✅ Flake + dev shell with full Racket, test runner
- ✅ Tabbed reader (#lang) with tabs-only indentation
- ⏳ Continuation `\` support (not yet implemented)
- ✅ Integration: sample programs run via new reader

## Open Questions
- Edge cases for tabs inside strings are allowed; ensure scanner doesn't mangle.
- Handling of atoms appearing alone at top-level (keep allowed?).
- ~~sweet-exp reuse vs bespoke parser~~ → Went with bespoke parser

## Risks
- ✅ Ambiguity reconstructing paren structure from indentation → Resolved with deterministic parser
- ✅ Mixed tabs/spaces → Rejected at parse time with clear error messages

## Test Strategy
- ✅ Unit: reader indentation parsing, space rejection
- ✅ Unit: self-evaluating keywords, persistent data structures
- ✅ Integration: all examples run via `racket examples/*.trk`
- ✅ Benchmarks: ARC vs S3-FIFO cache performance comparison

## Future Work
- Line continuation with `\`
- CLI converter: tab-racket ↔ standard Racket
- IDE/editor integration (syntax highlighting, indentation guides)
