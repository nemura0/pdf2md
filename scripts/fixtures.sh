#!/bin/bash
# Generates the synthetic PDFs into Fixtures/ (git-ignored). Pass --bench for the large set.
source "$(dirname "$0")/lib.sh"
require_xcode
swift run --quiet FixtureGen --output "$REPO_ROOT/Fixtures" "$@"
