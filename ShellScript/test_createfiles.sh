#!/bin/bash
# Regression tests for createfiles.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/createfiles.sh"
TMPBASE="$(mktemp -d)"
PASS=0
FAIL=0

cleanup() { rm -rf "$TMPBASE"; }
trap cleanup EXIT

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $label"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label (expected='$expected', actual='$actual')"
        FAIL=$(( FAIL + 1 ))
    fi
}

assert_contains() {
    local label="$1" pattern="$2" text="$3"
    if echo "$text" | grep -q "$pattern"; then
        echo "  PASS: $label"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label (pattern='$pattern' not found)"
        FAIL=$(( FAIL + 1 ))
    fi
}

assert_file_exists() {
    local label="$1" path="$2"
    if [ -e "$path" ]; then
        echo "  PASS: $label"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label ($path does not exist)"
        FAIL=$(( FAIL + 1 ))
    fi
}

assert_file_not_exists() {
    local label="$1" path="$2"
    if [ ! -e "$path" ]; then
        echo "  PASS: $label"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label ($path should not exist)"
        FAIL=$(( FAIL + 1 ))
    fi
}

# ============================================================
echo "=== Test 1: Default parameters (count + prefix only) ==="
D="$TMPBASE/t1"
mkdir -p "$D"
OUT=$(bash "$SCRIPT" -n 3 -p file -d "$D" 2>&1)
assert_file_exists "file1.txt exists" "$D/file1.txt"
assert_file_exists "file2.txt exists" "$D/file2.txt"
assert_file_exists "file3.txt exists" "$D/file3.txt"
assert_contains "summary shows Created: 3" "Created:.*3" "$OUT"

# ============================================================
echo "=== Test 2: Custom directory and extension ==="
D="$TMPBASE/t2/subdir"
OUT=$(bash "$SCRIPT" -n 2 -p log -d "$D" -e csv 2>&1)
assert_file_exists "directory auto-created" "$D"
assert_file_exists "log1.csv exists" "$D/log1.csv"
assert_file_exists "log2.csv exists" "$D/log2.csv"
assert_contains "summary shows Created: 2" "Created:.*2" "$OUT"

# ============================================================
echo "=== Test 3: Start number offset ==="
D="$TMPBASE/t3"
mkdir -p "$D"
OUT=$(bash "$SCRIPT" -n 3 -p data -d "$D" -s 5 2>&1)
assert_file_not_exists "data1 should not exist" "$D/data1.txt"
assert_file_exists "data5.txt exists" "$D/data5.txt"
assert_file_exists "data6.txt exists" "$D/data6.txt"
assert_file_exists "data7.txt exists" "$D/data7.txt"

# ============================================================
echo "=== Test 4: Dry-run / preview mode ==="
D="$TMPBASE/t4"
mkdir -p "$D"
OUT=$(bash "$SCRIPT" -n 3 -p preview -d "$D" --dry-run 2>&1)
assert_file_not_exists "no file created in dry-run" "$D/preview1.txt"
assert_contains "DRY-RUN shown" "DRY-RUN" "$OUT"
assert_contains "CREATE listed" "CREATE" "$OUT"
assert_contains "No files were created" "No files were created" "$OUT"

# ============================================================
echo "=== Test 5: Overwrite protection (existing files skipped) ==="
D="$TMPBASE/t5"
mkdir -p "$D"
touch "$D/item1.txt"
echo "pre-existing" > "$D/item1.txt"
OUT=$(bash "$SCRIPT" -n 3 -p item -d "$D" 2>&1)
assert_contains "skip reported" "SKIP.*item1.txt" "$OUT"
assert_contains "Created: 2" "Created:.*2" "$OUT"
assert_contains "Skipped: 1" "Skipped:.*1" "$OUT"
# Verify pre-existing content was not overwritten
CONTENT=$(cat "$D/item1.txt")
assert_eq "existing file content preserved" "pre-existing" "$CONTENT"

# ============================================================
echo "=== Test 6: Validation - missing count ==="
OUT=$(bash "$SCRIPT" -p name 2>&1 || true)
assert_contains "error on missing count" "Count is required" "$OUT"

echo "=== Test 7: Validation - non-integer count ==="
OUT=$(bash "$SCRIPT" -n abc -p name 2>&1 || true)
assert_contains "error on bad count" "positive integer" "$OUT"

echo "=== Test 8: Validation - empty prefix ==="
OUT=$(bash "$SCRIPT" -n 1 -p "" 2>&1 || true)
assert_contains "error on empty prefix" "Prefix is required" "$OUT"

# ============================================================
echo
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
