# pdf2md: operating context for Claude Code

> This file is the project's constitution. If something in a conversation
> contradicts it, this file wins. If you think it is wrong, stop and propose an
> explicit change. Do not ignore it silently.

Machine-specific notes (toolchain and repo locations) live in the git-ignored
`CLAUDE.local.md`.

## 1. What this is

A native macOS PDF to Markdown converter with a Finder Quick Action. Select PDFs
in Finder, right-click, Quick Actions, **Convert to Markdown**, and a `.md`
appears next to each PDF. The main use is turning lecture slides, books and long
technical documents into compact Markdown to feed LLMs.

Priorities, in order:

1. Faithful structure and content.
2. Token efficiency: no noise.
3. No limits: any page count, file size or file count. Fully offline, zero
   network calls.

## 2. Architecture invariants

| # | Invariant | How it is checked |
|---|---|---|
| A1 | No networking code anywhere. Vision and PDFKit run on-device | `scripts/check-invariants.sh` |
| A2 | The only package dependency is `apple/swift-argument-parser` | `scripts/check-invariants.sh` |
| A3 | A `PDFDocument` is owned by exactly one `PageWorker` and never crosses isolation domains. Preflight opens its own short-lived instance | `scripts/check-invariants.sh`, review by `pipeline-reviewer` |
| A4 | Emit never opens the PDF. Anything needing a document happens in a worker and is spooled | `scripts/check-invariants.sh` |
| A5 | Font facts come from `ContentStreamScanner`. `NSFont` names are a per-word fallback only, because PDFKit reports `Helvetica` for fonts not installed on the Mac (ADR-0003) | Fixtures `book-cm` and `pdftex-style`, trace match rate in tests |
| A6 | `page.characterBounds(at:)` is never used. Its index drifts after ligatures (ADR-0003) | `scripts/check-invariants.sh` |
| A7 | Memory stays flat as page count grows. Workers recycle their `PDFDocument` (ADR-0006) | `make bench`, slope across page counts |
| A8 | One file's failure, crash or hang never affects another file. One supervised child process per file (ADR-0007) | `scripts/e2e.sh`, fuzz smoke test |
| A9 | Page and file limits are global across runs, through `flock` slot files (ADR-0007) | `scripts/e2e.sh` |
| A10 | Never overwrite without `--overwrite`. Cancel and stale sweeps never delete finished output | `OutputWriter` tests |
| A11 | Output has one `#`, no empty headings, no double blank lines, no trailing spaces, no HTML beyond `<!-- page N -->` | Asserted on every golden |
| A12 | The installed binary never depends on an external volume | `scripts/install.sh` rejects `/Volumes` in `otool -L` and `LC_RPATH` |
| A13 | Real documents never enter the repo. `*.pdf` is git-ignored, fixtures are generated | `scripts/check-invariants.sh` |

## 3. Repository map

```
Sources/PDF2MDKit/   All logic, behind protocol seams
  Model/             Sendable, Codable page and block types
  Extract/           Worker stage: PDFKit words, CGPDFScanner trace, Vision, render
  Layout/            Lines, columns, reading order
  Structure/         Profile, title, headings, margins, lists, reflow, code, tables
  Math/              Span detection, LaTeX mapping, sub/superscripts, display equations
  Images/            Figure filtering, digests, crops
  Output/            Markdown emit, front matter, reservation, atomic commit
  Pipeline/          PageWorker, spool, document conversion
  Runtime/           Supervisor, slots, jobs, detach, cancel, notifications, log, preflight
Sources/pdf2md/      Thin CLI (swift-argument-parser)
Sources/FixtureGen/  Deterministic synthetic PDFs and their ground truth
Tests/PDF2MDKitTests/ Swift Testing suites and Golden/ files
scripts/             Quoted shell scripts behind the Makefile
templates/           Automator workflow templates
docs/adr/            Architecture Decision Records
```

Pipeline: supervisor → one child per file → page workers (extract to a disk spool)
→ document profile → sequential emit → temp file → rename. See ADR-0006 and
ADR-0007.

## 4. Commands

```bash
make build     # debug build
make test      # Swift Testing suites, including goldens
make fixtures  # generate synthetic PDFs into Fixtures/
make bench     # pages/s and peak RSS, plus memory slope across page counts
make install   # release build to ~/.local/bin, workflow to ~/Library/Services
make uninstall # reverses install and removes tool-owned data
make lint      # swift format lint and architecture invariants
```

Other useful commands:

```bash
bash scripts/e2e.sh               # real install, Automator run, cancel, notifications
swift run pdf2md --verbose a.pdf  # run from source
swift test --filter MathMapper    # one suite
```

Builds need the volume holding Xcode mounted. The scripts fail fast with a clear
message if it is not. Paths contain spaces: quote everything.

## 5. How to work here

### Mandatory order

1. **Verify Apple APIs before relying on them.** Read the SDK's `.swiftinterface`
   and headers or Apple's documentation. Never guess signatures. When behaviour
   matters, measure it with a throwaway probe. Several of the core decisions
   here exist because a probe contradicted the obvious assumption.
2. **Tests first** for pure stages in `Model`, `Layout`, `Structure`, `Math` and
   `Output`.
3. **A hard-to-reverse decision gets an ADR**, ideally before the code. Use
   `/adr`.
4. **Close phases with `/phase-close`.** Green means verified by running
   something, not by reading code.

### Before pushing

- [ ] `make build test lint` green from this folder, zero warnings
- [ ] Goldens changed only on purpose, and the diff was read
- [ ] `perf-gate` run if `Pipeline/`, `Extract/` or `Runtime/` changed
- [ ] `pipeline-reviewer` run if concurrency, spool or recycling changed

While the repo is private, macOS Actions minutes are billed, so push at the end
of a phase and never loop on CI. Once public, `main` only takes pull requests.

### Do not do without asking

- Add a package dependency.
- Add network access of any kind.
- Commit a real document, or any personal absolute path.
- Change a repetition threshold, heading rule or output format just to make a
  golden pass. Fix the cause, or change it on purpose and say why.

## 6. Style

- Everything in English: code, comments, CLI, notifications, docs, commits.
- Swift 6 language mode, strict concurrency, zero warnings (`.treatAllWarnings`).
  Deployment target macOS 26.
- `camelCase` functions and variables, `PascalCase` types, `is/has/should` for
  booleans. Named constants for thresholds, with the reason in a comment when it
  isn't obvious.
- Value types and `Sendable` models. PDFKit types stay inside their worker.
- Functions under 50 lines, files under 800 lines. Early returns over nesting.
- Comments explain why, not what. A measured surprise deserves a comment with the
  number and the ADR.

### Commits

Conventional Commits: `<type>(<scope>): <description>`.

```
feat(extract): trace fonts from the content stream
fix(output): bump the suffix for the .md and assets dir together
perf(pipeline): recycle the document every 100 pages
docs(adr): ADR-0007 process per file
```

## 7. Anti-goals

Do not build these. If asked, point here and ask whether the scope should change.

- ML models or any download at runtime. `ML-grade LaTeX math` stays on the roadmap
  as a separate optional path.
- A GUI app or an app extension. The Quick Action is the interface (ADR-0002).
- Folder input before 1.0. It is on the roadmap.
- HTML in the output beyond page markers.
- Password cracking or bypass. Locked PDFs are skipped with a reason.
- Windows or Linux. The engine is PDFKit and Vision by design (ADR-0001).
