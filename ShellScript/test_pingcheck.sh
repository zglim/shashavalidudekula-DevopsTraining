#!/bin/bash
# Regression tests for pingcheck.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PINGCHECK="$SCRIPT_DIR/pingcheck.sh"
TMPDIR_TEST="$(mktemp -d)"
passed=0
failed=0
total=0

cleanup() {
    rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    total=$((total + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        passed=$((passed + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        failed=$((failed + 1))
    fi
}

assert_contains() {
    local desc="$1" pattern="$2" text="$3"
    total=$((total + 1))
    if echo "$text" | grep -qE "$pattern"; then
        echo "  PASS: $desc"
        passed=$((passed + 1))
    else
        echo "  FAIL: $desc"
        echo "    pattern '$pattern' not found in output"
        failed=$((failed + 1))
    fi
}

assert_not_contains() {
    local desc="$1" pattern="$2" text="$3"
    total=$((total + 1))
    if echo "$text" | grep -qE "$pattern"; then
        echo "  FAIL: $desc"
        echo "    pattern '$pattern' was found in output but should not be"
        failed=$((failed + 1))
    else
        echo "  PASS: $desc"
        passed=$((passed + 1))
    fi
}

echo "=== Test 1: Default hosts file (ShellScript/myhosts) ==="
output=$(bash "$PINGCHECK" 2>&1)
rc=$?
assert_eq "exit code is 0" "0" "$rc"
assert_contains "output contains Summary" "Summary" "$output"
assert_contains "output contains Total hosts" "Total hosts:" "$output"

echo
echo "=== Test 2: Custom hosts file via argument ==="
cat > "$TMPDIR_TEST/custom_hosts" <<'EOF'
localhost
EOF
output=$(bash "$PINGCHECK" "$TMPDIR_TEST/custom_hosts" 2>&1)
rc=$?
assert_eq "exit code is 0" "0" "$rc"
assert_contains "localhost is up" "localhost is up and running" "$output"
assert_contains "Total hosts: 1" "Total hosts: 1" "$output"
assert_contains "Successful: 1" "Successful:.*1" "$output"

echo
echo "=== Test 3: Blank lines, whitespace, and comments are skipped ==="
cat > "$TMPDIR_TEST/messy_hosts" <<'EOF'


# this is a comment
   # indented comment
localhost   # inline comment

   localhost

EOF
output=$(bash "$PINGCHECK" "$TMPDIR_TEST/messy_hosts" 2>&1)
rc=$?
assert_eq "exit code is 0" "0" "$rc"
assert_contains "Total hosts: 2" "Total hosts: 2" "$output"
assert_not_contains "no comment text pinged" "this is a comment" "$output"
assert_not_contains "no hash pinged" "indented comment" "$output"

echo
echo "=== Test 4: Date/time is printed correctly ==="
output=$(bash "$PINGCHECK" "$TMPDIR_TEST/custom_hosts" 2>&1)
# The output should contain a real date, not literal '$date' or empty
assert_not_contains "no literal \$date" '\$date' "$output"
assert_not_contains "no literal backtick-date" '`' "$output"
# Should contain a year (e.g. 2025 or 2026)
assert_contains "output contains current year" "20[0-9][0-9]" "$output"

echo
echo "=== Test 5: Non-existent hosts file ==="
output=$(bash "$PINGCHECK" "$TMPDIR_TEST/no_such_file" 2>&1)
rc=$?
assert_eq "exit code is non-zero" "1" "$rc"
assert_contains "error message mentions file" "does not exist" "$output"

echo
echo "=== Test 6: Empty hosts file (no valid entries) ==="
cat > "$TMPDIR_TEST/empty_hosts" <<'EOF'


# only comments
   # another comment

EOF
output=$(bash "$PINGCHECK" "$TMPDIR_TEST/empty_hosts" 2>&1)
rc=$?
assert_eq "exit code is non-zero" "1" "$rc"
assert_contains "error about no valid entries" "no valid host entries" "$output"

echo
echo "=== Test 7: Truly empty file ==="
: > "$TMPDIR_TEST/zero_hosts"
output=$(bash "$PINGCHECK" "$TMPDIR_TEST/zero_hosts" 2>&1)
rc=$?
assert_eq "exit code is non-zero" "1" "$rc"
assert_contains "error about no valid entries" "no valid host entries" "$output"

echo
echo "=================================="
echo "Results: $passed/$total passed, $failed failed"
if [ "$failed" -gt 0 ]; then
    exit 1
else
    echo "All tests passed!"
    exit 0
fi
