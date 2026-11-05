#!/bin/bash
# Invariants no compiler can express (CLAUDE.md section 2). Cheap, and they catch exactly the
# kind of drift that creeps in unnoticed.
set -uo pipefail
cd "$(dirname "$0")/.."

failures=0
fail() {
    echo "invariant $1: $2" >&2
    failures=$((failures + 1))
}

# A1: no networking code.
network=$(grep -rnE 'URLSession|URLRequest|NWConnection|NWPathMonitor|import Network|CFNetwork|CFSocket' \
    Sources Package.swift 2>/dev/null)
[ -z "$network" ] || fail A1 "networking code found:
$network"

# A2: swift-argument-parser is the only package dependency.
dependencies=$(grep -c '\.package(url:' Package.swift)
if [ "$dependencies" -ne 1 ] || ! grep -q 'apple/swift-argument-parser' Package.swift; then
    fail A2 "Package.swift must depend on swift-argument-parser only"
fi

# A3: a PDFDocument is only created by the worker, preflight and FixtureGen.
documents=$(grep -rln 'PDFDocument(' Sources 2>/dev/null |
    grep -vE 'Sources/PDF2MDKit/Pipeline/PageWorker\.swift|Sources/PDF2MDKit/Runtime/Preflight\.swift|Sources/FixtureGen/')
[ -z "$documents" ] || fail A3 "PDFDocument created outside PageWorker and Preflight:
$documents"

# A4: the pure stages and emit never touch PDFKit.
pure_stages=$(grep -rln 'import PDFKit' \
    Sources/PDF2MDKit/Model Sources/PDF2MDKit/Layout Sources/PDF2MDKit/Structure \
    Sources/PDF2MDKit/Math Sources/PDF2MDKit/Output 2>/dev/null)
[ -z "$pure_stages" ] || fail A4 "PDFKit imported in a pure stage:
$pure_stages"

# A6: characterBounds(at:) drifts after ligatures (ADR-0003).
bounds=$(grep -rn 'characterBounds' Sources 2>/dev/null)
[ -z "$bounds" ] || fail A6 "characterBounds(at:) must not be used:
$bounds"

# A13: no PDFs, no personal absolute paths in tracked files.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tracked_pdfs=$(git ls-files | grep -iE '\.pdf$')
    [ -z "$tracked_pdfs" ] || fail A13 "PDFs are tracked:
$tracked_pdfs"

    personal=$(git ls-files -z | grep -zv '^scripts/check-invariants\.sh$' |
        xargs -0 grep -nIE '/Users/[A-Za-z0-9_.-]+|/Volumes/[A-Z0-9][A-Za-z0-9_. -]*/' 2>/dev/null)
    [ -z "$personal" ] || fail A13 "personal absolute paths are tracked:
$personal"
fi

if [ "$failures" -gt 0 ]; then
    echo "check-invariants: $failures failed" >&2
    exit 1
fi
echo "check-invariants: ok"
