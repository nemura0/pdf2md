#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_xcode
swift test "$@"
