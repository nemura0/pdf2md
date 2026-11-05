#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_xcode
swift format lint --strict --recursive --parallel \
    --configuration "$REPO_ROOT/.swift-format" \
    "$REPO_ROOT/Package.swift" "$REPO_ROOT/Sources" "$REPO_ROOT/Tests"
bash "$REPO_ROOT/scripts/check-invariants.sh"
echo "lint: ok"
