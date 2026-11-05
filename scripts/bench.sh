#!/bin/bash
# Pages per second and peak memory, for one file at several sizes (the slope shows whether memory
# grows with page count) and for three large files at once.
#
# `time -l` only reports the largest single process, and each file runs in its own child, so a
# sampler also adds up the whole process tree.
source "$(dirname "$0")/lib.sh"
require_xcode

SAMPLE_INTERVAL=0.2
RESULTS="$REPO_ROOT/bench-results"
BENCH_HOME="$(mktemp -d)"
trap 'rm -rf "$BENCH_HOME"' EXIT

swift build -c release --product pdf2md 2>&1 | tail -1
BIN="$(swift build -c release --product pdf2md --show-bin-path)/pdf2md"
[ -f "$REPO_ROOT/Fixtures/bench-scanned-1400.pdf" ] || bash "$REPO_ROOT/scripts/fixtures.sh" --bench

mkdir -p "$RESULTS"
REPORT="$RESULTS/$(date +%Y-%m-%d-%H%M%S).txt"

# Prints the largest total RSS, in MB, of a process and all its descendants until it exits.
sample_tree() {
    local root="$1" peak=0 total
    while kill -0 "$root" 2>/dev/null; do
        total="$(ps -A -o pid=,ppid=,rss= | awk -v root="$root" '
            { parent[$1] = $2; rss[$1] = $3 }
            END {
                for (pid in rss) {
                    for (node = pid; node != 0 && node != ""; node = parent[node]) {
                        if (node == root) { sum += rss[pid]; break }
                    }
                }
                print int(sum / 1024)
            }')"
        [ "${total:-0}" -gt "$peak" ] && peak="$total"
        sleep "$SAMPLE_INTERVAL"
    done
    echo "$peak"
}

# run <label> <pages> <extra flags...> -- <files...>
run() {
    local label="$1" pages="$2" output time_log
    shift 2
    output="$(mktemp -d "$BENCH_HOME/out.XXXXXX")"
    time_log="$(mktemp "$BENCH_HOME/time.XXXXXX")"

    PDF2MD_HOME="$BENCH_HOME/home" /usr/bin/time -l "$BIN" --output-dir "$output" "$@" \
        >/dev/null 2>"$time_log" &
    local pid=$!
    local peak
    peak="$(sample_tree "$pid")"
    wait "$pid" || echo "warning: $label exited with $?"

    local single
    single="$(awk '/maximum resident set size/ { print int($1 / 1048576) }' "$time_log")"
    local seconds rate
    seconds="$(grep -Eo '^ *[0-9.]+ real' "$time_log" | awk '{ print $1 }')"
    rate="$(awk -v p="$pages" -v s="$seconds" 'BEGIN { printf "%.1f", p / s }')"
    printf '%-26s %6s pages %8ss %9s pages/s  tree %6s MB  largest process %6s MB\n' \
        "$label" "$pages" "$seconds" "$rate" "$peak" "$single" | tee -a "$REPORT"
    rm -rf "$output"
}

F="$REPO_ROOT/Fixtures"
echo "Memory slope, one file:" | tee -a "$REPORT"
run "text 175" 175 "$F/bench-text-175.pdf"
run "text 350" 350 "$F/bench-text-350.pdf"
run "text 700" 700 "$F/large-700.pdf"
run "text 1400" 1400 "$F/bench-text-1400.pdf"
echo "Other kinds of page:" | tee -a "$REPORT"
run "slides 400" 400 "$F/bench-slides-400.pdf"
run "scanned 300" 300 "$F/bench-scanned-300.pdf"
run "scanned 700" 700 "$F/bench-scanned-700.pdf"
run "scanned 1400" 1400 "$F/bench-scanned-1400.pdf"
echo "Three large files at once:" | tee -a "$REPORT"

run "three at once" 2500 "$F/large-700.pdf" "$F/bench-text-1400.pdf" "$F/bench-slides-400.pdf"
echo "Saved to bench-results/$(basename "$REPORT")"
