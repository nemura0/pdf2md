# Plan

Six phases, one push at the end of each. A phase closes when its gate has been
verified by running something.

| Phase | Scope | Gate | Status |
|---|---|---|---|
| P1 | Conventions, `CLAUDE.md`, ADRs 0001 to 0008, `.claude/` agents and commands | Docs reviewed against the code that exists | In progress |
| P2 | Package, CLI with exit codes, Makefile and scripts, `FixtureGen` with ground truth, CI | Every Makefile target runs from a path with spaces, first CI run | |
| P3 | Scanner, extractor, layout, structure, writer, worker pool, spool, emit, supervisor, log, bench | Goldens and recall green, footprint flat at 175/350/700/1400 pages | |
| P4 | OCR and tables, then images, then math | Goldens extended, fuzz smoke clean, bench flat on a scanned 700-page file | |
| P5 | Quick Action, installer, detach, notifications, cancel, README | `scripts/e2e.sh` green on the installed workflow, final bench | |
| P6 | Audit, Dependabot, release `v1.0.0`, ruleset, go public | CI watched, owner's OK before the visibility change | |

Key decisions are in [`docs/adr/`](adr/).

## Things to measure, not assume

- Trace match rate on real PDFs, including Type0 fonts with `/W`.
- Memory slope across page counts, for text, scanned and image-heavy documents.
- Whether goldens stay stable on the CI image.
- Whether `automator` passes the environment through to the workflow's shell.
- Whether a detached child survives the real service runner, not just the CLI.
