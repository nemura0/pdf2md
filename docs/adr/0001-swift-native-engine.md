# ADR-0001: Swift-native engine instead of Python ML

- **Status:** accepted
- **Date:** 2026-11-05
- **Phase:** P1

## Context

The tool converts lecture slides, books and long technical documents to Markdown
for LLMs. It runs from a Finder Quick Action, so it must start instantly, have no
runtime to manage, work offline, and handle hundreds of pages at a time on a
16 GB laptop, several files at once.

The best open-source converters use layout and formula models. Their math output
is better than anything heuristic. The question is whether that is worth what it
costs here.

## Options considered

### Option A: Python with ML models

Layout and formula-recognition models produce real LaTeX for stacked fractions and
matrices.

- Needs a Python environment plus model weights in the gigabytes, downloaded on
  first use. That breaks "zero network calls" unless weights are pre-installed.
- Memory and per-page time are far higher, which works against several large books
  at once on 16 GB.
- A Quick Action would depend on a virtual environment staying healthy across
  Python and OS upgrades.

### Option B: Python without ML

PDF libraries expose fonts and geometry directly, with no models. It still brings
the runtime and packaging problem, and it needs a separate OCR engine.

### Option C: Swift with Apple frameworks

PDFKit and CoreGraphics read the PDF, Vision does OCR and table structure, all
on-device and already on every Mac running macOS 26.

Measured on this hardware: about 5 ms per page for text extraction, and 0.15 s per
page for `RecognizeDocumentsRequest` (0.44 s in a fresh process, 37 s only for the
one-time model load). Eight parallel Vision requests took 0.22 s.

The cost is that math is heuristic and only macOS is supported.

## Decision

We choose **Option C**. A single small binary with no runtime, no downloads and no
network code fits the Quick Action and meets the "no limits, fully offline"
priority. Math stays best effort, with a cropped image when a formula can't be
rebuilt confidently (ADR-0005).

## Consequences

**Positive:** one binary, instant start, nothing to install or update, no model
downloads, low memory, and native OCR with Spanish support. The only dependency is
`swift-argument-parser`.

**Negative:** stacked fractions and matrices come out as a linearization plus an
image, not LaTeX. macOS 26 or later only, because `RecognizeDocumentsRequest`
requires it. Behaviour follows Apple's frameworks across OS versions.

**Cost of reverting:** high. The extraction, layout and structure stages are built
on PDFKit and CoreGraphics types. The `Markdown` output format would survive.

## What would invalidate this decision

- Real lecture material where formula-heavy pages are unusable for an LLM even with
  the crop. The answer would then be the optional ML path on the roadmap, not a
  replacement of this engine.
- Apple removing or degrading PDFKit's text layer or `RecognizeDocumentsRequest`.
