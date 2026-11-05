# ADR-0008: CI runs on the `xcode-27` image

- **Status:** accepted
- **Date:** 2026-11-05
- **Phase:** P1

## Context

CI should build and run the tests on the newest hosted macOS runner. The code needs the
macOS 26 SDK or later for `RecognizeDocumentsRequest`. Golden files compare exact
Markdown, and PDFKit's behaviour varies by OS version, so the runner's OS matters as much
as its Xcode.

Checked in `actions/runner-images` on 2026-11-05:

| Label | OS | Xcode | Note |
|---|---|---|---|
| `macos-latest`, `macos-26` | macOS 26.6.2 | 26.6 default | Stable, can build the Vision code |
| `xcode-27` | macOS 27.0.1 (26A434) | 27.1 default, 27.2 available | Public preview, same OS build as development |

While the repo is private, macOS minutes are billed, so CI must also stay cheap.

## Options considered

### Option A: `macos-latest`

Stable and in general availability. But goldens produced on macOS 27 may not match
PDFKit on macOS 26, which would force skipping them on CI, and CI would stop testing the
real environment.

### Option B: `xcode-27`

The newest available. Same OS build as development, so goldens should match. It is a
preview, with possible queueing and instability.

## Decision

We choose **Option B**, with `DEVELOPER_DIR` pointing at Xcode 27.2 to match development.
CI runs build, lint and tests, on pushes to `main` and on pull requests, with
cancel-in-progress. There is no `paths-ignore`, because a required status check has to
report on every pull request.

If OCR tests can't run on the VM, they are skipped on CI through an explicit environment
variable, and the README says so. CI is never made green by hiding a real failure.

Measured on the first CI run with OCR: every real Vision request fails within about 2 s on
this image, while lint, build and all other tests pass. So the workflow sets
`PDF2MD_CI_NO_VISION`, which skips the tests that need real Vision, including the goldens
with tables. A separate informational step converts a fixture and prints the error each run.
OCR, tables and those goldens are only verified locally, through `make test`.

## Consequences

**Positive:** CI tests the same OS and toolchain as development.

**Negative:** preview status means the label may change, and queue times may be long. The
deployment target (macOS 26) isn't tested on macOS 26 itself.

**Cost of reverting:** low. It is one line.

## What would invalidate this decision

- The image being retired or renamed: move to its successor, such as a `macos-27` label.
- Sustained queueing or instability on the preview image.
- Goldens failing here for environment reasons that a different image doesn't have.
