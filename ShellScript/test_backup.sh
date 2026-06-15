#!/bin/bash
# test_backup.sh — minimal regression tests for backup.sh
# Run from the project directory: bash ShellScript/test_backup.sh

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup.sh"
TEST_TMP=""
PASS_COUNT=0
FAIL_COUNT=0

# ---------- helpers ----------

setup_test_tmp() {
    TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/backup_test_XXXXXX")"
}

cleanup_test_tmp() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [ "$expected" -eq "$actual" ]; then
        echo "  [PASS] ${label} (exit=${actual})"
        ((PASS_COUNT++))
    else
        echo "  [FAIL] ${label}: expected exit=${expected}, got exit=${actual}" >&2
        ((FAIL_COUNT++))
    fi
}

assert_output_contains() {
    local needle="$1"
    local haystack="$2"
    local label="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  [PASS] ${label} (output contains '${needle}')"
        ((PASS_COUNT++))
    else
        echo "  [FAIL] ${label}: output does not contain '${needle}'" >&2
        echo "         Actual output: ${haystack}" >&2
        ((FAIL_COUNT++))
    fi
}

assert_output_not_contains() {
    local needle="$1"
    local haystack="$2"
    local label="$3"
    if ! echo "$haystack" | grep -qF "$needle"; then
        echo "  [PASS] ${label} (output does not contain '${needle}')"
        ((PASS_COUNT++))
    else
        echo "  [FAIL] ${label}: output unexpectedly contains '${needle}'" >&2
        ((FAIL_COUNT++))
    fi
}

assert_file_exists() {
    local path="$1"
    local label="$2"
    if [ -f "$path" ]; then
        echo "  [PASS] ${label} (file exists: ${path})"
        ((PASS_COUNT++))
    else
        echo "  [FAIL] ${label}: file not found: ${path}" >&2
        ((FAIL_COUNT++))
    fi
}

assert_file_not_exists() {
    local path="$1"
    local label="$2"
    if [ ! -f "$path" ]; then
        echo "  [PASS] ${label} (file absent as expected: ${path})"
        ((PASS_COUNT++))
    else
        echo "  [FAIL] ${label}: file should not exist: ${path}" >&2
        ((FAIL_COUNT++))
    fi
}

# ======================================================
# Test 1: Successful local backup (no upload)
# ======================================================
echo "=== Test 1: Successful local backup ==="
setup_test_tmp

SOURCE="${TEST_TMP}/src"
OUT="${TEST_TMP}/out"
mkdir -p "$SOURCE" "$OUT"
echo "hello world" > "${SOURCE}/sample.txt"
echo "data"        > "${SOURCE}/data.csv"

output=$(bash "$BACKUP_SCRIPT" -s "$SOURCE" -o "$OUT" 2>&1)
rc=$?

assert_exit_code 0 "$rc" "backup exits 0 on success"
assert_output_contains "Compression successful" "$output" "reports compression success"
assert_output_contains "Skipping upload" "$output" "reports upload skipped"
assert_output_not_contains "[ERROR]" "$output" "no errors in output"

# Verify a .tar.gz file was produced in the output dir
gz_file=$(ls "$OUT"/backup_*.tar.gz 2>/dev/null | head -1)
if [ -n "$gz_file" ]; then
    assert_file_exists "$gz_file" "archive file exists"
else
    echo "  [FAIL] No .tar.gz archive found in output dir" >&2
    ((FAIL_COUNT++))
fi

cleanup_test_tmp

# ======================================================
# Test 2: Source directory does not exist
# ======================================================
echo
echo "=== Test 2: Source directory does not exist ==="
setup_test_tmp

OUT="${TEST_TMP}/out"
mkdir -p "$OUT"

output=$(bash "$BACKUP_SCRIPT" -s "${TEST_TMP}/nonexistent_dir" -o "$OUT" 2>&1)
rc=$?

assert_exit_code 1 "$rc" "backup exits 1 when source missing"
assert_output_contains "[ERROR]" "$output" "prints error message"
assert_output_contains "does not exist" "$output" "mentions directory does not exist"

# No archive should be created
gz_count=$(ls "$OUT"/backup_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
if [ "$gz_count" -eq 0 ]; then
    echo "  [PASS] No archive created when source missing"
    ((PASS_COUNT++))
else
    echo "  [FAIL] Archive should not have been created" >&2
    ((FAIL_COUNT++))
fi

cleanup_test_tmp

# ======================================================
# Test 3: gzip failure prevents upload from running
# ======================================================
echo
echo "=== Test 3: gzip failure prevents upload ==="
setup_test_tmp

SOURCE="${TEST_TMP}/src"
OUT="${TEST_TMP}/out"
mkdir -p "$SOURCE" "$OUT"
echo "test data" > "${SOURCE}/file.txt"

# Override gzip in PATH to simulate failure by placing a fake gzip script
FAKE_BIN="${TEST_TMP}/fake_bin"
mkdir -p "$FAKE_BIN"
cat > "${FAKE_BIN}/gzip" << 'EOF'
#!/bin/bash
echo "gzip: simulated failure" >&2
exit 2
EOF
chmod +x "${FAKE_BIN}/gzip"

output=$(PATH="${FAKE_BIN}:${PATH}" bash "$BACKUP_SCRIPT" \
    -s "$SOURCE" -o "$OUT" -r "user@fakehost:/tmp/backup" 2>&1)
rc=$?

assert_exit_code 1 "$rc" "backup exits 1 on gzip failure"
assert_output_contains "[ERROR]" "$output" "reports gzip error"
assert_output_not_contains "Uploading" "$output" "upload is not attempted after gzip failure"
assert_output_not_contains "[OK]" "$output" "no success message on gzip failure"

cleanup_test_tmp

# ======================================================
# Test 4: No remote target — local backup only, no scp attempt
# ======================================================
echo
echo "=== Test 4: No remote target — local backup only ==="
setup_test_tmp

SOURCE="${TEST_TMP}/src"
OUT="${TEST_TMP}/out"
mkdir -p "$SOURCE" "$OUT"
echo "local only" > "${SOURCE}/note.txt"

# Ensure scp is unavailable to prove it's never called
FAKE_BIN="${TEST_TMP}/fake_bin"
mkdir -p "$FAKE_BIN"
cat > "${FAKE_BIN}/scp" << 'EOF'
#!/bin/bash
echo "scp: should not have been called" >&2
exit 99
EOF
chmod +x "${FAKE_BIN}/scp"

output=$(PATH="${FAKE_BIN}:${PATH}" bash "$BACKUP_SCRIPT" -s "$SOURCE" -o "$OUT" 2>&1)
rc=$?

assert_exit_code 0 "$rc" "backup exits 0 with no remote target"
assert_output_contains "Skipping upload" "$output" "reports upload skipped"
assert_output_not_contains "should not have been called" "$output" "scp binary was never invoked"
assert_output_contains "Local backup completed" "$output" "confirms local backup complete"

cleanup_test_tmp

# ======================================================
# Test 5: Output directory not writable
# ======================================================
echo
echo "=== Test 5: Output directory not writable ==="
setup_test_tmp

SOURCE="${TEST_TMP}/src"
OUT="${TEST_TMP}/readonly_out"
mkdir -p "$SOURCE" "$OUT"
echo "data" > "${SOURCE}/file.txt"
chmod 555 "$OUT"  # read + execute only

output=$(bash "$BACKUP_SCRIPT" -s "$SOURCE" -o "$OUT" 2>&1)
rc=$?

assert_exit_code 1 "$rc" "backup exits 1 when output dir not writable"
assert_output_contains "[ERROR]" "$output" "reports error for unwritable output dir"

# Restore permissions for cleanup
chmod 755 "$OUT"
cleanup_test_tmp

# ======================================================
# Test 6: Source directory not readable
# ======================================================
echo
echo "=== Test 6: Source directory not readable ==="
setup_test_tmp

SOURCE="${TEST_TMP}/noread"
OUT="${TEST_TMP}/out"
mkdir -p "$SOURCE" "$OUT"
echo "secret" > "${SOURCE}/secret.txt"
chmod 333 "$SOURCE"  # write + execute only, no read

output=$(bash "$BACKUP_SCRIPT" -s "$SOURCE" -o "$OUT" 2>&1)
rc=$?

assert_exit_code 1 "$rc" "backup exits 1 when source not readable"
assert_output_contains "[ERROR]" "$output" "reports error for unreadable source"

chmod 755 "$SOURCE"
cleanup_test_tmp

# ======================================================
# Summary
# ======================================================
echo
echo "=============================="
echo "Test results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "=============================="

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
