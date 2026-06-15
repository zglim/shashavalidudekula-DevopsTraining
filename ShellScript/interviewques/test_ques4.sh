#!/bin/bash
# Regression tests for ques4.sh
# Covers: normal file, normal directory, path with spaces, empty input, non-existent path

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/ques4.sh"
TMPDIR_BASE=$(mktemp -d)
PASS=0
FAIL=0

cleanup() {
	rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

run_test() {
	local desc="$1"
	local input="$2"
	local expect_exit="$3"
	local expect_pattern="$4"

	output=$(echo "$input" | bash "$SCRIPT" 2>&1)
	actual_exit=$?

	if [ "$actual_exit" -ne "$expect_exit" ]; then
		echo "FAIL: $desc"
		echo "  Expected exit $expect_exit, got $actual_exit"
		echo "  Output: $output"
		FAIL=$((FAIL + 1))
		return
	fi

	if [ -n "$expect_pattern" ]; then
		if echo "$output" | grep -q "$expect_pattern"; then
			echo "PASS: $desc"
			PASS=$((PASS + 1))
		else
			echo "FAIL: $desc"
			echo "  Expected pattern '$expect_pattern' not found in output"
			echo "  Output: $output"
			FAIL=$((FAIL + 1))
		fi
	else
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	fi
}

# --- Setup test fixtures ---

# Normal file
TEST_FILE="$TMPDIR_BASE/testfile.txt"
echo "hello world" > "$TEST_FILE"

# Normal directory with some files
TEST_DIR="$TMPDIR_BASE/testdir"
mkdir -p "$TEST_DIR"
echo "a" > "$TEST_DIR/file1.txt"
echo "b" > "$TEST_DIR/file2.txt"
echo "c" > "$TEST_DIR/file3.txt"

# Path with spaces
SPACE_DIR="$TMPDIR_BASE/path with spaces"
mkdir -p "$SPACE_DIR"
echo "spaced content" > "$SPACE_DIR/spaced file.txt"

SPACE_FILE="$SPACE_DIR/spaced file.txt"

# --- Run tests ---

echo "========================================="
echo " Regression tests for ques4.sh"
echo "========================================="
echo

# 1. Normal file: should show file content and exit 0
run_test "Normal file - shows content" "$TEST_FILE" 0 "hello world"

# 2. Normal directory: should show file count and listing, exit 0
run_test "Normal directory - shows file count" "$TEST_DIR" 0 "3 file(s)"

# 3. Normal directory: listing includes expected files
run_test "Normal directory - lists files" "$TEST_DIR" 0 "file1.txt"

# 4. Path with spaces - directory
run_test "Directory with spaces in path" "$SPACE_DIR" 0 "1 file(s)"

# 5. Path with spaces - file
run_test "File with spaces in path" "$SPACE_FILE" 0 "spaced content"

# 6. Empty input: should error and exit 1
run_test "Empty input - errors" "" 1 "No input provided"

# 7. Non-existent path: should error and exit 1
run_test "Non-existent path - errors" "/nonexistent/path/xyz" 1 "does not exist"

echo
echo "========================================="
echo " Results: $PASS passed, $FAIL failed"
echo "========================================="

if [ "$FAIL" -gt 0 ]; then
	exit 1
fi
exit 0
