#!/bin/bash
#Purpose: Bash Scripting Training
#Author: Shashavali
#Date: 9th June,2022
#Use: check ping status of hosts given in myhosts file

# ---------------------------------------------------------------------------
# Resolve the default hosts file: prefer the one shipped alongside this script
# (i.e. <script_dir>/myhosts).  An explicit argument always wins.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_HOSTS="${SCRIPT_DIR}/myhosts"

hosts="${1:-$DEFAULT_HOSTS}"

# ---------------------------------------------------------------------------
# Validate the hosts file before doing anything else
# ---------------------------------------------------------------------------
if [[ ! -f "$hosts" ]]; then
    echo "[ERROR] Hosts file not found: $hosts" >&2
    exit 1
fi

if [[ ! -r "$hosts" ]]; then
    echo "[ERROR] Hosts file is not readable: $hosts" >&2
    exit 1
fi

# Check whether the file has at least one usable (non-blank, non-comment) line
has_entry=false
while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip leading/trailing whitespace
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    # Skip blank lines and comment lines (starting with #)
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" == \#* ]] && continue
    has_entry=true
    break
done < "$hosts"

if [[ "$has_entry" != true ]]; then
    echo "[ERROR] Hosts file is empty or contains no valid entries: $hosts" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Print header with the *real* current date/time
# ---------------------------------------------------------------------------
clear 2>/dev/null   # harmless if clear is unavailable
echo
echo -e "\t==========================\tChecking the host connections at $(date)\t=========================="

# ---------------------------------------------------------------------------
# Main loop – read line-by-line so spaces / blanks / comments are handled
# correctly without word-splitting issues.
# ---------------------------------------------------------------------------
total=0
success=0
fail=0

while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip leading/trailing whitespace
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

    # Skip blank lines and comment lines
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" == \#* ]] && continue

    ip="$trimmed"
    total=$((total + 1))

    if ping -c1 "$ip" &> /dev/null; then
        echo -e "\t[OK]   $ip is up and running"
        success=$((success + 1))
    else
        echo -e "\t[FAIL] Unable to connect to $ip"
        fail=$((fail + 1))
    fi
done < "$hosts"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo -e "\t==========================\tSummary\t=========================="
echo -e "\tTotal hosts checked : $total"
echo -e "\tSuccessful (up)     : $success"
echo -e "\tFailed (down)       : $fail"
echo -e "\t============================================================"
echo

# Exit non-zero when any host was unreachable so callers can react
if [[ $fail -gt 0 ]]; then
    exit 2
fi
exit 0
