# ADR-0009: Headings follow the PDF's outline when it has one

- **Status:** accepted
- **Date:** 2026-11-05
- **Phase:** post 1.0, first audit on a real book

## Context

Headings were ranked only by font size: the largest sizes in the document took `##`, `###` and
`####`. The first real book checked (488 pages, LuaLaTeX) showed where that fails. A cover in 56,
49 and 29 point type took the top ranks, so all of the 325 real headings landed on `####` and the
document had no hierarchy. Display lines set at a heading size became headings, such as a formula
in words at 14.3 points. A chapter number set alone at 20.7 points became a heading of its own.

Most books made with LaTeX or a word processor carry an outline, and that one had 241 entries. Of
those, 233 matched a line on their own page exactly or after its printed number, measured with a
throwaway probe. The other eight were two-line titles, parts split across lines, and labels
holding residue from `\colorbox`, all of which the matcher now handles.

## Options considered

### Option A: better size rules only

Ignore sizes that are rare and keep ranking by size. It needs no new input, and it is what a PDF
without an outline has to rely on. It can't tell a section from a display line at the same size,
and it can only guess at depth from the number of sizes in use.

### Option B: use the outline as the only source

Exact where it applies. But unnumbered front matter (`Prefacio`, `Introducción`) often isn't in
it, so real headings would become text, and a poor outline (one entry, generic bookmarks) would
remove every heading.

### Option C: the outline decides when it matches the pages, sizes fill the gaps

An outline counts when at least three entries, and at least half of them, name a heading-like line
on their page. Then each matched line is a heading at its entry's depth, and the sizes and weights
of those lines decide the rest: another line in the same size and weight is a heading at the level
most of its size had. Sizes the outline never used are text, which takes care of covers. Otherwise
the outline is ignored and sizes rank as before, except that a size found on one page of a long
document gets no rank and neither does a line with no letters.

## Decision

We choose **Option C**. The printed line stays the text of the heading, so numbers survive, while
the outline only says which line it is and how deep. Depth 0 is `##`, one level each below it, down
to `######`. Slide decks keep their own rule, since their titles are the headings and `##`.

The outline is read in preflight, which already opens a short-lived document, so emit still never
opens the PDF (A3, A4). Reading stops at 20,000 entries and depth 16, so a malformed or cyclic
outline can't hang a conversion.

## Consequences

**Positive:** books get a real hierarchy. Covers and display lines stop being headings. A monospace
heading in the outline no longer becomes a code fence.

**Negative:** heading levels can now reach `#####` and `######`. A line the outline doesn't name,
in the same size and weight as its headings, still becomes a heading, as `Versión 0.3b` on a title
page does. Each page runs one more text comparison, only when it has entries.

**Cost of reverting:** low. Drop the entries from the profile and sizes take over.

## What would invalidate this decision

- Real documents whose outlines match by accident and describe something other than their headings.
- Outlines that name the right lines at depths that don't reflect the document.
