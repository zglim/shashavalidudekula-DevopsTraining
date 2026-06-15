#!/bin/bash
# Regression tests for ques4.sh
# Covers: normal file, normal dir, path with spaces, empty input, non-existent path

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUES4="$SCRIPT_DIR/ques4.sh"
PASS=0
FAIL=0

# Helper: run ques4 with given input and check exit code + output pattern
run_test() {
    local desc="$1"
    local input="$2"
    local expect_exit="$3"
    local expect_pattern="$4"

    output=$(echo "$input" | bash "$QUES4" 2>&1)
    actual_exit=$?

    if [ "$actual_exit" -eq "$expect_exit" ] && echo "$output" | grep -q "$expect_pattern"; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc"
        echo "  input='$input'  expect_exit=$expect_exit  actual_exit=$actual_exit"
        echo "  expect_pattern='$expect_pattern'"
        echo "  output: $output"
        FAIL=$((FAIL + 1))
    fi
}

# Setup temp fixtures
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Regular file
echo "hello world" > "$TMPDIR/testfile.txt"

# Directory with 2 files
mkdir "$TMPDIR/testdir"
touch "$TMPDIR/testdir/a.txt" "$TMPDIR/testdir/b.txt"

# Path with spaces
mkdir "$TMPDIR/my dir"
echo "space content" > "$TMPDIR/my dir/my file.txt"
touch "$TMPDIR/my dir/another.txt"

# --- Tests ---

run_test "regular file" \
    "$TMPDIR/testfile.txt" \
    0 \
    "is a file"

run_test "regular directory" \
    "$TMPDIR/testdir" \
    0 \
    "is a directory"

run_test "directory file count" \
    "$TMPDIR/testdir" \
    0 \
    "File count: 2"

run_test "path with spaces (file)" \
    "$TMPDIR/my dir/my file.txt" \
    0 \
    "is a file"

run_test "path with spaces (dir)" \
    "$TMPDIR/my dir" \
    0 \
    "is a directory"

run_test "dir with spaces file count" \
    "$TMPDIR/my dir" \
    0 \
    "File count: 2"

run_test "empty input" \
    "" \
    1 \
    "Error: No input provided"

run_test "non-existent path" \
    "$TMPDIR/does_not_exist" \
    1 \
    "Error.*does not exist"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
