#!/bin/bash
# End to end on the real install: Automator run, detach, notifications, cancel, crash and hang
# isolation, global limits, reinstall. Automator strips the environment, so runs that need the
# stub use a copy of the workflow with it inline. One run uses the installed workflow untouched,
# which shows a real notification and adds a line to the real log.
source "$(dirname "$0")/lib.sh"
require_xcode

BIN="$HOME/.local/bin/pdf2md"
WORKFLOW="$HOME/Library/Services/Convert to Markdown.workflow"
FIXTURES="$REPO_ROOT/Fixtures"
PBS=/System/Library/CoreServices/pbs
AUTOMATOR=/usr/bin/automator
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pdf2md-e2e.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0

check() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        passed=$((passed + 1))
        echo "  ok    $name"
    else
        failed=$((failed + 1))
        echo "  FAIL  $name"
    fi
}

section() { printf '\n%s\n' "$1"; }
contains() { grep -qF -- "$2" "$1"; }
is_empty_dir() { [ -z "$(ls -A "$1" 2>/dev/null)" ]; }
is_nonempty_file() { [ -s "$1" ]; }
lacks() { ! grep -qF -- "$2" "$1"; }
missing() { [ ! -e "$1" ]; }
no_process_matches() { ! pgrep -f "$1"; }

# Waits for a file to hold a text, up to a number of seconds.
wait_for_text() {
    local file="$1" text="$2" seconds="$3" waited=0
    while [ "$waited" -lt $((seconds * 5)) ]; do
        if grep -qF -- "$text" "$file" 2>/dev/null; then return 0; fi
        /bin/sleep 0.2
        waited=$((waited + 1))
    done
    return 1
}

# The workflow with the stub and a private home inline. Each scenario gets its own.
make_test_workflow() {
    local home="$1" notes="$2" target="$3"
    local stub="$home/osascript-stub"
    mkdir -p "$home"
    cat > "$stub" <<STUB
#!/bin/sh
for last; do :; done
printf '%s\n--\n' "\$last" >> "$notes"
STUB
    chmod 755 "$stub"
    cp -R "$WORKFLOW" "$target"
    local document="$target/Contents/document.wflow" content inline
    content="$(cat "$document")"
    inline="PDF2MD_OSASCRIPT=\"$stub\" PDF2MD_HOME=\"$home\" \"$BIN\""
    printf '%s\n' "${content//\"$BIN\"/$inline}" > "$document"
}

if [ ! -f "$FIXTURES/large-700.pdf" ] || [ ! -f "$FIXTURES/bench-text-1400.pdf" ]; then
    bash "$REPO_ROOT/scripts/fixtures.sh" --bench
fi

section "Install"
bash "$REPO_ROOT/scripts/install.sh" >/dev/null
bash "$REPO_ROOT/scripts/install.sh" >/dev/null
check "install runs twice" test -x "$BIN"
check "no external volume in load commands" bash -c "! otool -L '$BIN' | grep -q /Volumes/"
check "no external volume in rpaths" bash -c "! otool -l '$BIN' | grep -q 'path /Volumes/'"
check "ad-hoc signed" bash -c "codesign -dv '$BIN' 2>&1 | grep -q 'Signature=adhoc'"
"$PBS" -dump > "$WORK/services.txt" 2>/dev/null
check "service registered" contains "$WORK/services.txt" "Convert to Markdown"
check "service takes PDFs" contains "$WORK/services.txt" "com.adobe.pdf"

section "Quick Action on several files at once"
A="$WORK/a"
mkdir -p "$A/in"
make_test_workflow "$A/home" "$A/notes.txt" "$A/test.workflow"
for name in book.pdf slides.pdf scanned.pdf encrypted.pdf corrupt.pdf large-700.pdf; do
    cp "$FIXTURES/$name" "$A/in/"
done
EMOJI="$(cd "$FIXTURES" && ls | grep '🚀' | head -1)"
cp "$FIXTURES/$EMOJI" "$A/in/"
find "$A/in" -name '*.pdf' -print > "$A/list.txt"
started=$SECONDS
automator_status=0
"$AUTOMATOR" -i - "$A/test.workflow" < "$A/list.txt" > "$A/automator.txt" 2>&1 ||
    automator_status=$?
elapsed=$((SECONDS - started))
check "automator exits with 0" test "$automator_status" -eq 0
check "automator returns in seconds ($elapsed s)" test "$elapsed" -lt 20
if ls "$A/home/jobs" 2>/dev/null | grep -q .; then job_alive=yes; else job_alive=no; fi
check "the job keeps running after the workflow exits" test "$job_alive" = yes
check "conversion ends" wait_for_text "$A/notes.txt" "Converted " 240
check "start notification" contains "$A/notes.txt" "Converting 7 PDFs…"
check "end notification" contains "$A/notes.txt" "Converted 5 of 7 in "
check "failure named with a reason" contains "$A/notes.txt" "encrypted.pdf: password-protected"
for name in book slides scanned large-700; do
    check "$name.md written" is_nonempty_file "$A/in/$name.md"
done
check "name with accents and emoji" is_nonempty_file "$A/in/${EMOJI%.pdf}.md"
check "encrypted file has no output" missing "$A/in/encrypted.md"
check "corrupt file has no output" missing "$A/in/corrupt.md"
check "front matter" contains "$A/in/book.md" 'source: "book.pdf"'
check "OCR ran on the scan" contains "$A/in/scanned.md" "Foundations of Computing"
check "a figure's file exists" is_nonempty_file "$A/in/slides_assets/p0005-01.png"
check "its link is there" contains "$A/in/slides.md" "![Figure](slides_assets/p0005-01.png)"
check "a table came through" contains "$A/in/slides.md" "| Prueba 1 | 5 | 30% |"
check "the math came through" contains "$A/in/book.md" '\alpha x^2'
check "one log line per file" test "$(wc -l < "$A/home/logs/pdf2md.log")" -eq 7
check "job directory is gone" is_empty_dir "$A/home/jobs"
check "caches are empty" is_empty_dir "$A/home/caches"

section "Cancel"
B="$WORK/b"
mkdir -p "$B/in"
make_test_workflow "$B/home" "$B/notes.txt" "$B/test.workflow"
cp "$FIXTURES/bench-text-1400.pdf" "$B/in/cancel-me-1.pdf"
cp "$FIXTURES/large-700.pdf" "$B/in/cancel-me-2.pdf"
find "$B/in" -name '*.pdf' -print > "$B/list.txt"
"$AUTOMATOR" -i - "$B/test.workflow" < "$B/list.txt" > /dev/null 2>&1
PDF2MD_HOME="$B/home" "$BIN" --cancel > "$B/cancel.txt"
check "cancel reports the job" contains "$B/cancel.txt" "Cancelled 1"
check "no partial markdown" bash -c "! ls '$B/in' | grep -q '\.md$'"
check "no assets left" bash -c "! ls '$B/in' | grep -q '_assets$'"
check "no temp files left" bash -c "! ls -A '$B/in' | grep -q 'pdf2md-tmp'"
check "job directory is gone" is_empty_dir "$B/home/jobs"
check "no process left" no_process_matches "__convert-child.*cancel-me"

section "A crash costs one file"
C="$WORK/c"
mkdir -p "$C"
cp "$FIXTURES/large-700.pdf" "$FIXTURES/book.pdf" "$C/"
export_home=(env "PDF2MD_HOME=$C/home")
"${export_home[@]}" "$BIN" "$C/large-700.pdf" "$C/book.pdf" > "$C/out.txt" 2>&1 &
supervisor=$!
/bin/sleep 1.5
victim="$(pgrep -P "$supervisor" -f large-700 | head -1 || true)"
check "the child was running" test -n "$victim"
[ -n "$victim" ] && kill -9 "$victim"
wait "$supervisor" && crash_status=0 || crash_status=$?
check "exit code says some failed" test "$crash_status" -eq 1
check "the crash is reported" contains "$C/out.txt" "large-700.pdf: crashed"
check "the other file converted" is_nonempty_file "$C/book.md"
check "no partial output from the crash" missing "$C/large-700.md"

section "A hang costs one file"
D="$WORK/d"
mkdir -p "$D"
cp "$FIXTURES/large-700.pdf" "$D/"
env "PDF2MD_HOME=$D/home" PDF2MD_WATCHDOG_SECONDS=2 "$BIN" "$D/large-700.pdf" > "$D/out.txt" 2>&1 &
supervisor=$!
/bin/sleep 1
victim="$(pgrep -P "$supervisor" | head -1 || true)"
check "the child was running" test -n "$victim"
[ -n "$victim" ] && kill -STOP "$victim"
wait "$supervisor" && hang_status=0 || hang_status=$?
check "exit code says it failed" test "$hang_status" -eq 1
check "the hang is reported" contains "$D/out.txt" "stopped responding"
check "no partial output from the hang" missing "$D/large-700.md"

section "A killed supervisor leaves no writers, and the next run cleans up"
E="$WORK/e"
mkdir -p "$E"
cp "$FIXTURES/book.pdf" "$E/"
cp "$FIXTURES/large-700.pdf" "$E/orphaned.pdf"
env "PDF2MD_HOME=$E/home" "$BIN" "$E/orphaned.pdf" > /dev/null 2>&1 &
supervisor=$!
/bin/sleep 1
child="$(pgrep -P "$supervisor" | head -1 || true)"
check "the child was running" test -n "$child"
kill -9 "$supervisor"
wait "$supervisor" 2>/dev/null || true
/bin/sleep 1
if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then child_alive=yes; else child_alive=no; fi
check "its child exits" test "$child_alive" = no
env "PDF2MD_HOME=$E/home" "$BIN" "$E/book.pdf" > /dev/null 2>&1
check "the stale job is swept" is_empty_dir "$E/home/jobs"
check "its placeholder is gone" missing "$E/orphaned.md"
check "the new run converted" is_nonempty_file "$E/book.md"

section "Limits are global across runs"
F="$WORK/f"
mkdir -p "$F/one" "$F/two"
for index in 1 2 3; do
    cp "$FIXTURES/bench-text-350.pdf" "$F/one/limit-a$index.pdf"
    cp "$FIXTURES/bench-text-350.pdf" "$F/two/limit-b$index.pdf"
done
env "PDF2MD_HOME=$F/home" "$BIN" --detach "$F/one/"*.pdf
env "PDF2MD_HOME=$F/home" "$BIN" --detach "$F/two/"*.pdf
peak=0
while pgrep -f "pdf2md --ready-fd.*$F" > /dev/null; do
    # Children's JSON arguments escape every slash, so this matches on the file name only.
    count="$( (pgrep -f "__convert-child.*limit-" || true) | wc -l | tr -d ' ')"
    [ "$count" -gt "$peak" ] && peak="$count"
    /bin/sleep 0.1
done
check "at most 3 files in flight across both runs (peak $peak)" test "$peak" -le 3
check "they overlapped (peak $peak)" test "$peak" -ge 2
for index in 1 2 3; do
    check "first run, file $index" is_nonempty_file "$F/one/limit-a$index.md"
    check "second run, file $index" is_nonempty_file "$F/two/limit-b$index.md"
done

section "Output names and fallback"
G="$WORK/g"
mkdir -p "$G/in" "$G/dl"
cp "$FIXTURES/book.pdf" "$G/in/"
run_g=(env "PDF2MD_HOME=$G/home" "PDF2MD_DOWNLOADS=$G/dl" "$BIN")
"${run_g[@]}" "$G/in/book.pdf" > /dev/null 2>&1
printf 'edited by hand' >> "$G/in/book.md"
"${run_g[@]}" "$G/in/book.pdf" > /dev/null 2>&1
check "never overwrites" contains "$G/in/book.md" "edited by hand"
check "the next name is free" is_nonempty_file "$G/in/book (1).md"
check "the name bumps its assets too" is_nonempty_file "$G/in/book (1)_assets/p0003-01.png"
check "its link follows" contains "$G/in/book (1).md" "book%20%281%29_assets"
"${run_g[@]}" --overwrite "$G/in/book.pdf" > /dev/null 2>&1
check "--overwrite replaces" lacks "$G/in/book.md" "edited by hand"
mkdir -p "$G/locked"
cp "$FIXTURES/book.pdf" "$G/locked/"
chmod 555 "$G/locked"
"${run_g[@]}" "$G/locked/book.pdf" > "$G/fallback.txt" 2>&1 || true
chmod 755 "$G/locked"
check "an unwritable folder falls back to Downloads" is_nonempty_file "$G/dl/book.md"
check "and says so" contains "$G/fallback.txt" "not writable"

section "The installed workflow, untouched"
H="$WORK/h"
mkdir -p "$H"
cp "$FIXTURES/book.pdf" "$H/real.pdf"
printf '%s\n' "$H/real.pdf" > "$H/list.txt"
real_status=0
"$AUTOMATOR" -i - "$WORKFLOW" < "$H/list.txt" > /dev/null 2>&1 || real_status=$?
check "automator exits with 0" test "$real_status" -eq 0
check "the real log records it" wait_for_text "$HOME/Library/Logs/pdf2md/pdf2md.log" "file=\"real.pdf\"" 120
check "the output is next to the PDF" is_nonempty_file "$H/real.md"

section "Uninstall and reinstall"
bash "$REPO_ROOT/scripts/uninstall.sh" > /dev/null
"$PBS" -dump > "$WORK/services-after.txt" 2>/dev/null
check "binary removed" missing "$BIN"
check "workflow removed" missing "$WORKFLOW"
check "service unregistered" lacks "$WORK/services-after.txt" "Convert to Markdown"
check "tool data removed" missing "$HOME/Library/Application Support/pdf2md"
check "logs removed" missing "$HOME/Library/Logs/pdf2md"
bash "$REPO_ROOT/scripts/install.sh" > /dev/null
check "reinstalled" test -x "$BIN"

printf '\ne2e: %d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
