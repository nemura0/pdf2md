# ADR-0002: Automator Quick Action as the Finder integration

- **Status:** accepted
- **Date:** 2026-11-05
- **Phase:** P1

## Context

The product is a right-click in Finder. The integration must appear only for PDFs,
accept several files, install from `make install` without manual steps, and never
block Finder, even on a conversion that takes minutes. It has no Developer ID
signing today.

## Options considered

### Option A: Automator Quick Action

A `.workflow` bundle is two property lists. It can be generated from templates in
the repo, dropped into `~/Library/Services` and registered with `pbs -update`.

Verified on macOS 27.0.1: `/usr/bin/automator` runs workflows from the shell,
`com.apple.Automator.fileSystemObject.PDF` exists as an input type, `pbs -dump`
lists services, and hand-built Finder workflows work on this machine.
`NSSendFileTypes` with `com.adobe.pdf` restricts the menu item to PDFs.

The downside is that Automator is old technology, the script runs with a minimal
environment, and a long-running script would block the workflow. The last two are
handled by an absolute path and `--detach`.

### Option B: Shortcuts

Shortcuts is the current direction and can appear as a Quick Action. But a shortcut
has no supported silent install: importing goes through a signed file and a user
confirmation, so `make install` can't be idempotent, and `make uninstall` can't
reverse it cleanly.

### Option C: App extension

An Action or Finder Sync extension is the most integrated option. It requires a host
`.app`, an Xcode project and, to run smoothly on other Macs, Developer ID signing and
notarization. Extensions are sandboxed, which complicates writing next to arbitrary
PDFs. It adds a GUI product where none is wanted.

## Decision

We choose **Option A**. It is the only option that installs and uninstalls
idempotently from a script, needs no signing identity, and filters by PDF. The binary
stays the product, and the workflow is a thin wrapper that can be replaced later.

## Consequences

**Positive:** plain text templates in the repo, no Xcode project, a scriptable and
testable install, and the same binary works from the terminal.

**Negative:** the workflow must call the binary by absolute path and detach
immediately. Notifications go through `osascript`, so macOS attributes them to Script
Editor. TCC prompts attach to the Automator runner, not to `pdf2md`, and can only be
confirmed by a real right-click.

**Cost of reverting:** low. Only `templates/` and the install scripts know about
Automator.

## What would invalidate this decision

- Apple removing `/usr/bin/automator` or Quick Action workflows from a macOS release.
- The detached child being killed or denied when launched by the real service runner.
  That is checked with `NSPerformService` in `scripts/e2e.sh`.
- Getting a Developer ID identity, which makes Option C viable for other Macs.
