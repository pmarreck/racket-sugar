# Project Plan

## Goal
Create a Racket syntax variant that uses significant **tab-based** indentation instead of parentheses, with CLI converters to and from standard Racket, managed via Nix flake. "Done" when:
- #lang loads and runs tab-indented code.
- Tests pass.

## Milestones
- Flake + dev shell with full Racket, test runner.
- Tabbed reader (#lang) with tabs-only indentation + continuation `\` support.
- Integration: sample program runs via new reader.

## Open Questions
- Edge cases for tabs inside strings are allowed; ensure scanner doesn’t mangle.
- Handling of atoms appearing alone at top-level (keep allowed?).
- sweet-exp reuse vs bespoke parser; start with sweet-exp + tab guard.

## Risks
- Ambiguity reconstructing paren structure from indentation; need deterministic canonical form.
- Mixed tabs/spaces: must normalize or reject to avoid subtle bugs.

## Test Strategy
- Unit: reader indentation parsing, continuation lines, space rejection/normalization.
- Integration: run a tabbed sample via `racket -l tab-racket` or `#lang tab-racket` module.
