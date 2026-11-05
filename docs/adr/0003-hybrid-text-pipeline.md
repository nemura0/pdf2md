# ADR-0003: Hybrid pipeline: PDFKit text, CGPDFScanner fonts, Vision OCR

- **Status:** accepted
- **Date:** 2026-11-05
- **Phase:** P1

## Context

Structure detection depends on three things: the text, where each word sits, and
which font set it. Headings need sizes and bold, code needs monospace, math needs
font names and baseline offsets.

The obvious source is PDFKit: `PDFPage.string`, `attributedString` and
`characterBounds(at:)`. Probes on macOS 27.0.1 showed that this is not safe:

| Probe | Result |
|---|---|
| `attributedString` with fonts installed on the Mac | Correct names, sizes and traits |
| `attributedString` with embedded or unembedded fonts **not** installed (Lato, Source Code Pro, CMR10, CMMI10, CMTT10) | Reports `Helvetica`, no bold, italic or mono, and merges runs. Sizes and `CTBaselineOffset` stay correct |
| `attributedString` | Logs `attributedStringScaled…` to stderr on every call |
| `characterBounds(at:)` | Index drifts after ligatures: index 68 returned the rect of the character 4 positions later, index 119 a zero rect |
| `selection(for: NSRange)` | Aligned with `page.string`, about 8 µs per call |
| `page.string` | Collapses leading and repeated spaces |

The first row is the trap. A test suite using system fonts passes, while every real
LaTeX or Office document loses all of its font signals.

## Options considered

### Option A: PDFKit only

Simple, and PDFKit decodes every encoding. It fails on the trap above, so math, code
and bold detection would not work on real documents.

### Option B: Own text extractor on CGPDFScanner

Full control of fonts and positions, but decoding glyphs to Unicode means
reimplementing `ToUnicode` CMaps, encodings, `Differences` arrays and glyph-name
lists. PDFKit already does that well.

### Option C: PDFKit for text and geometry, CGPDFScanner for font facts

PDFKit supplies the decoded text and word rectangles. A `CGPDFScanner` pass tracks the
CTM and text state, and records, for each show operation, its origin, `BaseFont`,
effective size and descriptor flags. No glyph decoding. Each word is matched to the
trace by position.

Tested on a hand-written pdfTeX-style PDF (`TJ` kerns, `Tc`, `Tw`, `Tz`, `TL`, `T*`,
`'`, `cm` scaling, nested Forms, unembedded CM fonts): **26 of 26 words matched** with
the right font and effective size, while `attributedString` said `Helvetica` for all
of them. Words mixing fonts, such as `x2`, resolve from trace boundaries.

### OCR source

For pages without usable text, `RecognizeDocumentsRequest` (macOS 26+) gives lines and
table structure. Its lines feed the same `Line` model, sized by line height, so there
is one layout path. It also finds tables on born-digital pages, where
`cell.content.boundingRegion` gives a cell rectangle to fill with PDFKit text instead
of OCR text.

## Decision

We choose **Option C**, with Vision for OCR and table structure. `characterBounds(at:)`
is banned. `attributedString` is only a per-word fallback when the trace has no match,
for example with Type3 fonts. The match rate is tracked and gated in tests.

## Consequences

**Positive:** real font names on real documents, true baseline offsets and effective
sizes, and no glyph decoder to maintain.

**Negative:** two views of the same page must agree, so there is a matching step with
its own failure mode. Fonts in Type0 form need `/W` for advance widths. Fixtures must
exercise raw content streams on purpose, because CoreGraphics output never shows these
operators, so `pdftex-style` is hand-written. Vision can drop isolated single-letter
cells in scanned tables, and a second pass on the crop recovers nothing. That is a
documented limitation for scans. Born-digital tables are unaffected.

**Cost of reverting:** medium. The trace is one component behind a small interface.

## What would invalidate this decision

- A trace match rate well below 95% on real PDFs that can't be fixed in the scanner.
- PDFKit fixing `attributedString` to report embedded font names. The scanner would
  still be needed for images and rules, but the font part could be dropped.
