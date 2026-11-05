# ADR-0006: Extract to a disk spool, then emit in order; recycle the document

- **Status:** accepted
- **Date:** 2026-11-05
- **Phase:** P1

## Context

Memory must stay flat as page count grows, and Markdown must reach disk in page order.
But the first line of output already depends on the whole document: body font size and
heading ranks need every page's sizes, and the rules that remove repeated headers and
logos (at least `max(3 pages, 30%)` of pages) need counts across all pages.

A separate problem showed up in measurement. One open `PDFDocument`, 1500 pages, with an
`autoreleasepool` per page:

| Strategy | Page 300 | Page 900 | Page 1500 | Time |
|---|---|---|---|---|
| One document | 226 MB | 480 MB | 736 MB | 8.3 s |
| Reopen every 100 pages | 251 MB | 251 MB | 252 MB | 7.4 s |

(Process footprint, including the in-memory test PDF and the JIT.) That is about
0.43 MB per page, retained by the document itself. The per-page pool does not help.

## Options considered

### Option A: Single pass with sampled stats

Decide body size and repeats from the first N pages. Flat and fast, but wrong for
documents that change partway, and "repeats on 30% of pages" can't be sampled honestly.

### Option B: Two full passes over the PDF

A light scan for stats, then a second pass to convert. No spool, but pages are parsed
twice, and OCR'd pages have no text until they are OCR'd, so scans would run OCR in the
first pass and throw it away, or run it twice.

### Option C: Extract to a spool, then emit

Workers extract each page in parallel and write a compact Codable record to disk, with
crops alongside. A cheap accumulator collects stats. Then one sequential pass reads the
records in order, applies the global decisions, and streams Markdown to a temp file.

## Decision

We choose **Option C**, with this rule: **everything needing a `PDFDocument` happens in
a worker, and emit never opens the PDF.** Decisions that depend on global stats are
spooled as flags and resolved at emit. For example, lines inside a figure are dropped
only if that figure is kept.

Workers reopen their document every 100 pages. Accumulators prune entries that can no
longer reach the threshold, so their size stays bounded by the threshold rather than by
page count.

The spool lives in `~/Library/Caches/pdf2md/<job>/`, not next to the PDF, so a PDF in
Dropbox doesn't sync temp files.

## Consequences

**Positive:** flat memory, OCR runs once, parallel extraction with strictly ordered
output, and paragraphs split across a page break can be joined because emit sees pages
in sequence.

**Negative:** nothing appears in the output until extraction finishes (acceptable, since
the output is written through a temp file anyway). Temporary disk use is proportional to
document size, and mostly crops. Cancel and crash paths must clean the spool up.

**Cost of reverting:** medium. The record format is the seam between the two stages.

## What would invalidate this decision

- `make bench` showing footprint growth that recycling and the spool don't remove.
- Spool I/O dominating runtime on normal documents, in which case an in-memory ring with
  a spill threshold would be worth the complexity.
