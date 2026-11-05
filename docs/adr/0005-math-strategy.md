# ADR-0005: Math is rebuilt from fonts and geometry, with crops as a safety net

- **Status:** accepted
- **Date:** 2026-11-05
- **Phase:** P1

## Context

Technical documents are full of formulas, and an LLM reads `\alpha_i^2` far better
than `αi2`. PDFs hold no math structure: only glyphs, fonts and positions. Without ML
(ADR-0001), reconstruction can only be partial, and a wrong formula that looks right
is worse than an obviously rough one.

## Options considered

### Option A: Raw Unicode

Emit the text as PDFKit gives it. Cheap and honest, but `x^2` becomes `x2`, which
silently changes the meaning.

### Option B: Crop every equation

Faithful for a human, useless for a text-only LLM, and expensive in images.

### Option C: Heuristic LaTeX with confidence

Detect math spans from font names (`CMMI`, `CMSY`, `CMEX`, `MSBM`, `STIX`, `*Math*`),
math Unicode blocks and Greek. Map symbols to LaTeX, and math-italic letters to plain
letters. Rebuild sub and superscripts from font size ratio and baseline offset, which
the content-stream trace gives exactly. Linear formulas come out right. Stacked ones
cannot, so they need a fallback.

## Decision

We choose **Option C**. Output is `$…$` inline and `$$…$$` for display equations.

When a display equation can't be rebuilt confidently, emit the best linearization
**and** a cropped image of it. Low confidence means stacked lines overlapping
horizontally, a fraction rule from the scanner's ruling segments, or big delimiters
from `CMEX`-style fonts. With `--no-images`, only the linearization is written.

Crops happen in the worker, the only stage holding a document (ADR-0006).

## Consequences

**Positive:** most inline math and simple display equations become real LaTeX at low
token cost, and hard equations always keep a faithful image.

**Negative:** stacked fractions and matrices stay as linearizations in the text. False
positives are possible where a text font carries math-like glyphs, so Greek in prose
may be wrapped as math. Math fonts without usable Unicode mappings go through the
garbled-text path and may be OCR'd, where math is not rebuilt.

**Cost of reverting:** low. The stage is self-contained, and removing it leaves plain
text.

## What would invalidate this decision

- Real samples showing frequent wrong LaTeX in inline math. The fix would be tightening
  detection, or raising the confidence needed to emit LaTeX at all.
- An optional ML path being added, which would replace the linearization for low
  confidence equations.
