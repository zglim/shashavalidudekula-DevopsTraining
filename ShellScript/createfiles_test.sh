#!/bin/bash
# Regression tests for createfiles.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/createfiles.sh"
PASS=0
FAIL=0
TEST_DIR=""

# ── Helpers ────────────────────────────────────────────────
setup() {
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/createfiles_test.XXXXXX")"
}

teardown() {
    [[ -n "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc (expected='$expected', actual='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" path="$2"
    if [[ -f "$path" ]]; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc (file '$path' not found)"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_not_exists() {
    local desc="$1" path="$2"
    if [[ ! -f "$path" ]]; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc (file '$path' should not exist)"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc (output does not contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_code() {
    local desc="$1" expected="$2" actual="$3"
    assert_eq "$desc" "$expected" "$actual"
}

# ═══════════════════════════════════════════════════════════
# Test 1: Default parameters
# ═══════════════════════════════════════════════════════════
echo "--- Test 1: Default parameters ---"
setup
output=$(cd "$TEST_DIR" && bash "$SCRIPT" 2>&1)
assert_file_exists "default: name1.txt exists" "$TEST_DIR/name1.txt"
assert_file_exists "default: name5.txt exists" "$TEST_DIR/name5.txt"
assert_file_not_exists "default: name6.txt not created" "$TEST_DIR/name6.txt"
assert_contains "default: summary shows Created" "Created" "$output"
assert_contains "default: summary shows Planned : 5" "Planned          : 5" "$output"
teardown

# ═══════════════════════════════════════════════════════════
# Test 2: Custom directory, prefix, extension
# ═══════════════════════════════════════════════════════════
echo "--- Test 2: Custom dir, prefix, extension ---"
setup
custom_dir="$TEST_DIR/subdir"
bash "$SCRIPT" -n 3 -p log -e csv -d "$custom_dir" 2>&1
assert_file_exists "custom: log1.csv exists" "$custom_dir/log1.csv"
assert_file_exists "custom: log3.csv exists" "$custom_dir/log3.csv"
assert_file_not_exists "custom: log4.csv not created" "$custom_dir/log4.csv"
teardown

# ═══════════════════════════════════════════════════════════
# Test 3: Starting number offset
# ═══════════════════════════════════════════════════════════
echo "--- Test 3: Start number offset ---"
setup
bash "$SCRIPT" -n 4 -s 10 -d "$TEST_DIR" 2>&1
assert_file_exists "offset: name10.txt exists" "$TEST_DIR/name10.txt"
assert_file_exists "offset: name13.txt exists" "$TEST_DIR/name13.txt"
assert_file_not_exists "offset: name9.txt not created" "$TEST_DIR/name9.txt"
assert_file_not_exists "offset: name14.txt not created" "$TEST_DIR/name14.txt"
teardown

# ═══════════════════════════════════════════════════════════
# Test 4: Preview mode – no files created
# ═══════════════════════════════════════════════════════════
echo "--- Test 4: Preview mode ---"
setup
output=$(bash "$SCRIPT" -n 3 -y -d "$TEST_DIR" 2>&1)
assert_file_not_exists "preview: name1.txt NOT created" "$TEST_DIR/name1.txt"
assert_file_not_exists "preview: name3.txt NOT created" "$TEST_DIR/name3.txt"
assert_contains "preview: output says Preview" "Preview" "$output"
assert_contains "preview: output lists name2.txt" "name2.txt" "$output"
teardown

# ═══════════════════════════════════════════════════════════
# Test 5: Overwrite protection – existing files are skipped
# ═══════════════════════════════════════════════════════════
echo "--- Test 5: Overwrite protection ---"
setup
# Pre-create two files
touch "$TEST_DIR/name1.txt" "$TEST_DIR/name2.txt"
output=$(bash "$SCRIPT" -n 4 -d "$TEST_DIR" 2>&1)
assert_contains "overwrite: SKIP for name1.txt" "SKIP" "$output"
assert_contains "overwrite: summary Skipped" "Skipped (exist)  : 2" "$output"
assert_contains "overwrite: summary Created" "Created          : 2" "$output"
teardown

# ═══════════════════════════════════════════════════════════
# Test 6: Validation – bad count
# ═══════════════════════════════════════════════════════════
echo "--- Test 6: Validation – bad count ---"
setup
output=$(bash "$SCRIPT" -n abc -d "$TEST_DIR" 2>&1)
ec=$?
assert_exit_code "bad count: exit code non-zero" "1" "$ec"
assert_contains "bad count: error message" "positive integer" "$output"
teardown

# ═══════════════════════════════════════════════════════════
# Test 7: Validation – empty prefix
# ═══════════════════════════════════════════════════════════
echo "--- Test 7: Validation – empty prefix ---"
setup
output=$(bash "$SCRIPT" -p "" -d "$TEST_DIR" 2>&1)
ec=$?
assert_exit_code "empty prefix: exit code 1" "1" "$ec"
assert_contains "empty prefix: error message" "prefix" "$output"
teardown

# ═══════════════════════════════════════════════════════════
# Test 8: Auto-create target directory
# ═══════════════════════════════════════════════════════════
echo "--- Test 8: Auto-create target directory ---"
setup
new_dir="$TEST_DIR/new/nested"
bash "$SCRIPT" -n 1 -d "$new_dir" 2>&1
assert_file_exists "auto-create dir: file created in new dir" "$new_dir/name1.txt"
teardown

# ── Final report ──────────────────────────────────────────
echo
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="
exit $FAIL
