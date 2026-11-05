# ADR-0004: Figures are cropped from a page render

- **Status:** accepted
- **Date:** 2026-11-05
- **Phase:** P1

## Context

Figures must end up as image files linked from the Markdown. A PDF can show a figure
as an image XObject, as vector paths in a form XObject, or as a stack of both, with
masks, soft masks, ICC color spaces, clipping and rotation applied. Slide decks repeat
logos and templates on every page, and scanned books hold one image per page. Those
must not be saved.

## Options considered

### Option A: Extract the XObject streams

Pixel-exact, and JPEG data can be copied without re-encoding. But Flate, CCITT and
JBIG2 data needs decoding, with color spaces, masks and transforms applied by hand.
Vector figures, which are most charts and diagrams in LaTeX and Office PDFs, have no
image to extract at all.

### Option B: Render the page and crop

CoreGraphics draws the page as a reader sees it, so masks, vector content and overlays
are correct by construction. `CGPDFScanner` still locates the figures: it tracks the
CTM and reports each placement. Costs: one 2× render on pages with figures, resolution
limited to 2×, and anything overlapping the figure ends up in the crop.

## Decision

We choose **Option B**. Fidelity to what the page shows matters more than preserving
source pixels, and it is the only option that handles vector figures. To keep the cost
down, a page is rendered only when it has a figure to crop, and each distinct image is
cropped once.

Identity comes from a SHA-256 of the XObject's stream bytes. Forms hash recursively
through `/Resources`, because wrapper Forms such as `/Im0 Do` can share bytes while
showing different images.

Filters: skip tiny images, page-sized images on text pages (backgrounds, searchable
scans) and the page image of OCR'd scans. Dedupe by digest. Drop images repeating on at
least `max(3 pages, 30%)` of pages. Use JPEG for large DCT or JPX sources and PNG
otherwise. The render scale drops below 2× only for huge pages, to cap bitmap memory.

## Consequences

**Positive:** one code path for raster and vector figures, correct masks and rotation,
and no image decoders to maintain.

**Negative:** a photo embedded above 2× resolution is downsampled, JPEGs get re-encoded,
and text drawn over an image stays in its crop. Text fully inside a kept figure leaves
the prose flow, so figure labels are in the image, not the Markdown.

**Cost of reverting:** low. The crop is one function behind `PageRendering`.

## What would invalidate this decision

- Real slides where 2× crops are too coarse to read. The fix would be raising the scale
  by source resolution, not changing the approach.
- Figures drawn straight into the page content with no XObject being common in real
  samples. Those are not detected today, and would need path clustering.
