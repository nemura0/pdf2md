# ADR-0010: What a page draws is read from its paths

- **Status:** accepted
- **Date:** 2026-11-05
- **Phase:** post 1.0, first audit on a real book

## Context

ADR-0003 reads text from PDFKit and fonts from the content stream. Neither says anything about the
paths a page draws, and a LaTeX book draws a lot of structure instead of typesetting it. The first
real book checked (488 pages, LuaLaTeX) showed what that costs:

- **Diagrams.** TikZ draws them inline, with no image or form to find, so ADR-0004 never saw them.
  Their labels landed in the text as loose words between sentences. A probe found 879 clusters of
  shapes: 763 mostly monospace (listing backgrounds and shaded terminal output), 112 others, and 4
  with no text. Most of the 112 are diagrams, and they're content: class diagrams are what the book
  teaches.
- **Tables.** `tabular` draws a full grid of rules, and it cuts each column line at every row, with
  gaps of 0.2 to 0.4 points. Vision found most of them, but it needs a render, and it read two
  listings set side by side as a table.
- **Footnotes.** Sorted into the flow by position, a note landed in the middle of the sentence that
  crossed its page, with its number glued on (`1Ingeniería`) and its marker glued to the word before
  it (`Java5`). Sentence cuts in the output were 424, many of them for this reason.

If nothing changes, a reader of the Markdown alone gets scrambled text on hundreds of pages. That
reader is usually an LLM, which can't see images unless they're sent along.

## Options considered

### Diagrams

**A: crop, and take the labels out of the text.** What ADR-0004 does for figures it finds, and what
the audit first proposed. Cheapest in tokens and clean to read, but the diagram is gone for a reader
of the text alone, and that is the main use of this tool.

**B: leave the labels in the text and don't crop.** Costs nothing to build, and it's the problem
itself.

**C: crop, and follow the crop with a fence of the labels placed by position.** The words survive
and their arrangement mostly does: a class box reads as a column of members. Arrows don't survive,
so a relation between two classes is only in the image. It costs tokens: 92,984 characters on that
book, about 10% of the output, though most of those are spaces, which tokenizers compress.

**D: rebuild the diagram as Mermaid or PlantUML.** The best output when it's right. Telling what an
arrow means from a path takes more than geometry: open and filled diamonds, dashed lines, labels
near two ends. A wrong diagram that looks right is worse than a rough one (the same call as ADR-0005),
and doing it well is ML territory (ADR-0001).

### Tables

**E: Vision only.** One path, but slower, and it can't tell a grid from aligned code.

**F: rules first, Vision for pages with none.** Exact where the grid is drawn, and a page whose
tables are all found this way needs no render. It adds a second path, and it has to tell tables from
other grids: class boxes, arrays of cells, frames.

### Footnotes

**G: leave them in the flow.** Simple, and the problem above.

**H: collect them at the end of the document.** Clean text, but a note ends up far from its page,
and numbering restarts per chapter or per page, so labels would need rewriting anyway.

**I: Markdown footnotes, written after the page they belong to.** `[^p22-6]` in the text, and its
definition before the next page's marker. A note stays near its reference, and the page number in
the label keeps restarting numbers unique. It relies on finding the separator rule, so a note under
no rule stays where it was.

## Decision

We choose **C**, **F** and **I**.

- **Drawings.** Shapes are clustered by distance. A cluster counts with three or more shapes, or an
  inner rule, since TikZ can draw a class box as one path. A cluster crossed by long lines of text,
  full of numbered lines, mostly code inside a frame, or holding long lines of prose isn't a drawing.
  A captioned frame close to a drawing joins it. Slides are skipped, because their framed lists matter
  more. With `--no-images` only the labels are written. A drawing repeating on 30% of pages is
  furniture and is dropped, labels included.
- **Identity.** A drawing's digest holds its shapes and its words, because one book drew the same
  boxes on three pages with different labels.
- **Tables.** Rules touching each other form a grid, which needs a closed frame, text in at least two
  rows, and no wholly empty column. Vision still runs on pages with none, and its tables are dropped
  when they overlap a table already found or are mostly monospace.
- **Footnotes.** The separator is a lone rule, 10% to 50% of the page wide, in the lower 60% of the
  page, starting near a line's left edge, and outside tables and drawings. Everything below it must
  be small print, except a page number, and its first line must start with a raised marker. A marker
  with no reference in the text stays as plain text, since Markdown viewers drop a definition nothing
  points at.

This extends ADR-0004, whose note that labels stay in the image no longer holds for drawings.

## Consequences

**Positive:** on that book, sentence cuts between blocks go from 424 to 0, and 121 diagrams keep their
words. All 69 footnotes are linked, and tables come out right without Vision. It ran in about 5 s,
against 68 s before, with Vision's model already loaded: only 2 image-only pages still need OCR.

**Negative:** the labels fence adds tokens, and the whole output went up about 3% (244,662 to 251,177
estimated) even with thousands of empty fence lines gone. Arrows are only in the image. Detection is
heuristic, tuned on one book, so an unusual drawing can be missed or a framed paragraph taken for one.
Fractions at body size in a display equation still flatten, because their lines overlap as one, and
they get no crop (ADR-0005's limit).

**Cost of reverting:** low. Nothing stored depends on this: each part is a pass in the worker or at
emit, and output is regenerated from the PDF.

## What would invalidate this decision

- Real documents where label fences take more than about a third of the output, or where they mislead
  an LLM more than no labels would.
- False drawings on real documents, seen as prose or code inside a `text` fence.
- Grids that aren't tables coming out as tables, such as forms or calendars.
- Footnotes from Word or InDesign left in the flow, meaning their separators don't fit these numbers.
- A Markdown reader that matters here dropping `[^label]` definitions placed before the document's end.
