#!/bin/bash
# ---------------------------------------------------------------------------
# Minimal regression tests for pingcheck.sh
#
# Strategy: put a fake `ping` on PATH so tests run instantly without real
# network access.  The shim succeeds for any host whose name contains "up"
# or is "localhost" / an IP starting with "127.", and fails otherwise.
# ---------------------------------------------------------------------------
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINGCHECK="${SCRIPT_DIR}/pingcheck.sh"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0

# ── helpers ────────────────────────────────────────────────────────────────

setup_fake_ping() {
    local fake_bin="${TMPDIR_BASE}/bin"
    mkdir -p "$fake_bin"
    cat > "${fake_bin}/ping" << 'SHIM'
#!/bin/bash
# Extract the last argument (the host)
host="${@: -1}"
case "$host" in
    *up*|localhost|127.*) exit 0 ;;
    *)                    exit 1 ;;
esac
SHIM
    chmod +x "${fake_bin}/ping"
    export PATH="${fake_bin}:${PATH}"
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected to find: '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  FAIL: $label (should NOT contain: '$needle')"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    fi
}

assert_exit_code() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" -eq "$expected" ]]; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected exit $expected, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

# ── fake ping ──────────────────────────────────────────────────────────────
setup_fake_ping

# ────────────────────────────────────────────────────────────────────────────
echo "=== Test 1: Default hosts file (no argument) ==="
# The default myhosts lives next to pingcheck.sh.  Run without arguments and
# make sure the script actually reads that file (we know it contains
# "localhost" which our fake ping treats as "up").
output="$(bash "$PINGCHECK" 2>&1)"
rc=$?
assert_contains "reads default myhosts (localhost appears)" "$output" "localhost"
assert_contains "prints summary header"                  "$output" "Summary"
assert_contains "total count present"                   "$output" "Total hosts checked"

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Test 2: Custom hosts file via argument ==="
custom="${TMPDIR_BASE}/custom_hosts"
printf 'server-up-1\nserver-down-1\nserver-up-2\n' > "$custom"
output="$(bash "$PINGCHECK" "$custom" 2>&1)"
rc=$?
assert_contains "custom file: server-up-1 OK"   "$output" "[OK]   server-up-1"
assert_contains "custom file: server-down-1 FAIL" "$output" "[FAIL] Unable to connect to server-down-1"
assert_contains "custom file: server-up-2 OK"   "$output" "[OK]   server-up-2"
assert_contains "summary: total = 3"           "$output" "Total hosts checked : 3"
assert_contains "summary: success = 2"         "$output" "Successful (up)     : 2"
assert_contains "summary: fail = 1"            "$output" "Failed (down)       : 1"

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Test 3: Blank lines, whitespace-only lines, and comment lines ==="
messy="${TMPDIR_BASE}/messy_hosts"
{
    echo "# this is a comment"
    echo ""
    echo "   "
    echo "  host-up-A  "      # leading/trailing spaces – should be trimmed
    echo "	"               # tab-only line
    echo "  # indented comment"
    echo "host-down-B"
    echo ""
} > "$messy"
output="$(bash "$PINGCHECK" "$messy" 2>&1)"
rc=$?
assert_contains "trimmed host-up-A"     "$output" "[OK]   host-up-A"
assert_contains "host-down-B fails"     "$output" "[FAIL] Unable to connect to host-down-B"
assert_not_contains "comment not pinged" "$output" "this is a comment"
assert_not_contains "indented comment not pinged" "$output" "indented comment"
assert_contains "only 2 valid hosts"    "$output" "Total hosts checked : 2"

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Test 4: Time output contains a real date, not literal \$date ==="
output="$(bash "$PINGCHECK" "$custom" 2>&1)"
# The header line must NOT contain the literal string '$date' or '`$date`'
assert_not_contains "no literal \$date in output" "$output" '$date'
# It should contain the current year (good enough proxy for "a real date")
year="$(date +%Y)"
assert_contains "header contains current year ($year)" "$output" "$year"

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Test 5: Nonexistent hosts file ==="
output="$(bash "$PINGCHECK" "/no/such/file/hosts.txt" 2>&1)"
rc=$?
assert_contains "error message for missing file" "$output" "[ERROR] Hosts file not found"
assert_exit_code "exit code 1 for missing file" 1 "$rc"

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Test 6: Empty / comment-only hosts file ==="
empty="${TMPDIR_BASE}/empty_hosts"
printf '# nothing here\n\n   \n' > "$empty"
output="$(bash "$PINGCHECK" "$empty" 2>&1)"
rc=$?
assert_contains "error for empty file" "$output" "[ERROR] Hosts file is empty"
assert_exit_code "exit code 1 for empty file" 1 "$rc"

# ────────────────────────────────────────────────────────────────────────────
echo
echo "========================================"
echo "  Results:  $PASS passed,  $FAIL failed"
echo "========================================"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
