# Plan

Six phases, one push at the end of each. A phase closes when its gate has been
verified by running something.

| Phase | Scope | Gate | Status |
|---|---|---|---|
| P1 | Conventions, `CLAUDE.md`, ADRs 0001 to 0008, `.claude/` agents and commands | Docs reviewed against the code that exists | Done 2026-11-05 |
| P2 | Package, CLI with exit codes, Makefile and scripts, `FixtureGen` with ground truth, CI | Every Makefile target runs from a path with spaces, first CI run | Done 2026-11-05 |
| P3 | Scanner, extractor, layout, structure, writer, worker pool, spool, emit, supervisor, log, bench | Goldens and recall green, footprint flat at 175/350/700/1400 pages | Done 2026-11-05: 101 tests, 1400 pages at 222 MB against 212 MB at 700 |
| P4 | OCR and tables, then images, then math | Goldens extended, fuzz smoke clean, bench flat on a scanned 700-page file | Done 2026-11-05: 36 mutated files clean, scanned 700 sawtooth with no steady growth |
| P5 | Quick Action, installer, detach, notifications, cancel, README | `scripts/e2e.sh` green on the installed workflow, final bench | Done 2026-11-05: 194 tests, e2e 77 of 77, scanned peaks 726/851/913 MB at 300/700/1400 pages |
| P6 | Audit, Dependabot, release `v1.0.0`, ruleset, go public | CI watched, owner's OK before the visibility change | Done 2026-11-05: CI green with 5 Vision tests skipped (ADR-0008), `v1.0.0` released, ruleset active, repo public |

Key decisions are in [`docs/adr/`](adr/).

## Things to measure, not assume

- Trace match rate on real PDFs, including Type0 fonts with `/W`. 100% on one real book, a 488-page
  LuaLaTeX file (ADR-0009, ADR-0010). **Still open:** Office files and anything else real. Synthetic
  `pdftex-style` and `book-cm` fixtures pass.
- Memory slope across page counts. Text: flat, 214 to 218 MB from 700 to 1400 pages. Scanned: slowing,
  726, 851 and 913 MB at 300, 700 and 1400 pages, and physical footprint doesn't climb during a
  1400-page run. **Image-heavy documents are still open:** no fixture has many distinct images.
- Whether goldens stay stable on the CI image. Vision requests fail there, so goldens with tables
  are skipped on CI (ADR-0008). The others are checked there.
- Whether `automator` passes the environment through to the workflow's shell. **It doesn't.**
  `scripts/e2e.sh` runs a test copy of the workflow with the variables inline.
- Whether a detached child survives the real service runner, not just the CLI. **It does:**
  `scripts/e2e.sh` asks for the service with `NSPerformService`. The caller has to stay alive after
  the call, since the runner reads its pasteboard later.
