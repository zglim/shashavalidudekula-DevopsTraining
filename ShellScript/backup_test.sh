#!/bin/bash
#
# Regression tests for backup.sh
# Run from the repo root or the ShellScript directory.
#

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_SH="${SCRIPT_DIR}/backup.sh"
PASS=0
FAIL=0

##############################################################################
# Helpers
##############################################################################
setup_tmpdir() {
    TMPDIR_TEST="$(mktemp -d)"
    # Create a small source tree to back up
    mkdir -p "${TMPDIR_TEST}/src/subdir"
    echo "file1" > "${TMPDIR_TEST}/src/file1.txt"
    echo "file2" > "${TMPDIR_TEST}/src/subdir/file2.txt"
    mkdir -p "${TMPDIR_TEST}/out"
}

cleanup_tmpdir() {
    [ -n "${TMPDIR_TEST:-}" ] && rm -rf "$TMPDIR_TEST"
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected=$expected, got=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local label="$1" pattern="$2" text="$3"
    if echo "$text" | grep -q "$pattern"; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (pattern '$pattern' not found in output)"
        FAIL=$((FAIL + 1))
    fi
}

##############################################################################
# Test 1 – Local backup succeeds
##############################################################################
echo "TEST 1: Local backup succeeds"
setup_tmpdir
output=$(bash "$BACKUP_SH" -s "${TMPDIR_TEST}/src" -o "${TMPDIR_TEST}/out" 2>&1)
rc=$?
assert_eq "exit code is 0" "0" "$rc"
assert_contains "output says success" "Backup completed successfully" "$output"
assert_contains "output contains archive path" "${TMPDIR_TEST}/out/backup_src_" "$output"
# Verify a .tar.gz file was actually created
gz_count=$(find "${TMPDIR_TEST}/out" -name '*.tar.gz' | wc -l | tr -d ' ')
assert_eq "exactly one .tar.gz created" "1" "$gz_count"
assert_contains "skipping upload message" "No remote target specified; skipping upload" "$output"
cleanup_tmpdir

##############################################################################
# Test 2 – Source directory does not exist
##############################################################################
echo "TEST 2: Source directory does not exist"
setup_tmpdir
output=$(bash "$BACKUP_SH" -s "${TMPDIR_TEST}/nonexistent" -o "${TMPDIR_TEST}/out" 2>&1)
rc=$?
assert_eq "exit code is non-zero" "1" "$rc"
assert_contains "error mentions source" "does not exist" "$output"
# No archive should have been created
gz_count=$(find "${TMPDIR_TEST}/out" -name '*.tar.gz' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "no .tar.gz created" "0" "$gz_count"
cleanup_tmpdir

##############################################################################
# Test 3 – Output directory not writable
##############################################################################
echo "TEST 3: Output directory not writable"
setup_tmpdir
chmod 000 "${TMPDIR_TEST}/out"
output=$(bash "$BACKUP_SH" -s "${TMPDIR_TEST}/src" -o "${TMPDIR_TEST}/out" 2>&1)
rc=$?
assert_eq "exit code is non-zero" "1" "$rc"
assert_contains "error mentions writable" "not writable" "$output"
chmod 755 "${TMPDIR_TEST}/out"   # restore so cleanup works
cleanup_tmpdir

##############################################################################
# Test 4 – gzip failure does not trigger upload
#   Simulate by replacing gzip with a failing stub via PATH override.
##############################################################################
echo "TEST 4: Compression failure prevents upload"
setup_tmpdir
# Create a fake gzip that always fails
FAKE_BIN="${TMPDIR_TEST}/fakebin"
mkdir -p "$FAKE_BIN"
cat > "${FAKE_BIN}/gzip" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "${FAKE_BIN}/gzip"

output=$(PATH="${FAKE_BIN}:${PATH}" bash "$BACKUP_SH" \
    -s "${TMPDIR_TEST}/src" \
    -o "${TMPDIR_TEST}/out" \
    -r "user@fakehost:/backup" 2>&1)
rc=$?
assert_eq "exit code is non-zero" "1" "$rc"
assert_contains "error mentions gzip" "gzip failed" "$output"
# Upload message must NOT appear
if echo "$output" | grep -q "Uploading"; then
    echo "  FAIL: upload was attempted despite gzip failure"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: upload was not attempted"
    PASS=$((PASS + 1))
fi
cleanup_tmpdir

##############################################################################
# Test 5 – No remote target: local-only backup completes
##############################################################################
echo "TEST 5: No remote target means local-only backup"
setup_tmpdir
output=$(bash "$BACKUP_SH" -s "${TMPDIR_TEST}/src" -o "${TMPDIR_TEST}/out" 2>&1)
rc=$?
assert_eq "exit code is 0" "0" "$rc"
assert_contains "no upload attempted" "No remote target specified" "$output"
# scp must not appear in output
if echo "$output" | grep -qi "scp"; then
    echo "  FAIL: scp mentioned in output"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: scp not mentioned"
    PASS=$((PASS + 1))
fi
cleanup_tmpdir

##############################################################################
# Summary
##############################################################################
echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
