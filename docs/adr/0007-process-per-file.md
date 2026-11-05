# ADR-0007: One supervised process per file, global limits through flock

- **Status:** accepted
- **Date:** 2026-11-05
- **Phase:** P1

## Context

Requirements: several large files at once, a global page-task limit of about the number
of performance cores, at most 3 files in flight, and one failure must never affect the
others. `--detach` returns immediately, so a second Quick Action run can start while the
first is still going, and the limits should hold across both.

PDF parsers meet malformed input. A failure can be a Swift error, but also a hard crash
or a hang inside CoreGraphics, and neither can be caught or killed from inside the same
process. With one process, a crash on page 300 of one file loses every other conversion,
the summary notification and the cleanup. A hang means no summary at all.

## Options considered

### Option A: One process, Swift concurrency

The simplest design. Vision loads once. It handles Swift errors, but a crash or hang
takes everything down, and the limits only hold within one run.

### Option B: Child per file, static share of `--jobs`

Crash and hang isolation, and memory goes back to the OS after each file. But a one-way
heartbeat can't rebalance: when a short deck finishes, a long book keeps its small share.
Limits still don't hold across runs.

### Option C: Child per file, flock slot files

Slot files live in `~/Library/Application Support/pdf2md/slots/`. Worker *i* takes a
blocking `flock` on `page-i` on its own dispatch queue and holds it for one page. The
supervisor takes a `file-N` slot before spawning a child.

- Waiters wake immediately, with no polling.
- Capacity rebalances by itself as files finish.
- It holds across separate runs, which share the same files.
- The kernel releases locks on crash, so a dead process can't leak a permit.

## Decision

We choose **Option C**, with `--jobs` page slots and `min(3, jobs)` file slots.

The supervisor owns everything that must survive a child's death: the log line, the
summary and partial-output cleanup. A child holds a shared `flock` on the job lock, and
exits on control-pipe EOF so a killed supervisor can't leave writers behind. A watchdog
kills a child after 15 minutes without page progress. Preflight and materialization of
online-only files are exempt, since those can legitimately take a while.

`POSIX_SPAWN_CLOEXEC_DEFAULT` is required: an inherited descriptor would keep a `flock`
alive after its owner is gone.

A new process costs little here: Vision's fresh-process start measured 0.44 s, and the
37 s model load happens once per machine, not once per process.

## Consequences

**Positive:** a crash or hang costs one file. Memory is fully reclaimed between files.
Limits are global and need no coordinator. `--cancel` can stop everything with signals.

**Negative:** three levels of process (detach parent, supervisor, child). `/usr/bin/time
-l` reports the largest child, not the total, so `make bench` adds a process-tree sampler.
Workers exceed slots when several files run, so more `PDFDocument`s are open than pages in
flight, which `make bench` must keep an eye on.

**Cost of reverting:** medium. `DocumentConverter` doesn't know it runs in a child, so an
in-process runner is possible behind `ProcessSpawning`.

## What would invalidate this decision

- Spawn overhead becoming visible on batches of many small files.
- Slot contention showing a real throughput loss in `make bench`.
- A fuzz run and real samples showing that hard crashes never occur, combined with a
  concrete cost from this design. Crash isolation is not free, but neither is losing a
  batch.
