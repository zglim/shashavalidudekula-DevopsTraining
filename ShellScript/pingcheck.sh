#!/bin/bash
#Purpose: Bash Scripting Training
#Author: Shashavali
#Date: 9th June,2022
#Use: check ping status of hosts given in myhosts file

# Determine the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Use first argument as hosts file, otherwise default to myhosts beside this script
hosts="${1:-${SCRIPT_DIR}/myhosts}"

# Validate the hosts file
if [ ! -f "$hosts" ]; then
    echo "Error: hosts file '$hosts' does not exist." >&2
    exit 1
fi

if [ ! -r "$hosts" ]; then
    echo "Error: hosts file '$hosts' is not readable." >&2
    exit 1
fi

# Check that the file has at least one valid (non-blank, non-comment) host entry
has_hosts=false
while IFS= read -r line || [ -n "$line" ]; do
    stripped="${line%%#*}"
    stripped="$(echo "$stripped" | xargs)"
    if [ -n "$stripped" ]; then
        has_hosts=true
        break
    fi
done < "$hosts"

if [ "$has_hosts" = false ]; then
    echo "Error: hosts file '$hosts' contains no valid host entries." >&2
    exit 1
fi

# Counters
total=0
success=0
fail=0

echo
echo -e "\t==========================\tChecking the host connections at $(date)\t=========================="
echo

while IFS= read -r line || [ -n "$line" ]; do
    # Strip inline comments
    stripped="${line%%#*}"
    # Trim leading and trailing whitespace
    stripped="$(echo "$stripped" | xargs)"
    # Skip empty lines
    [ -z "$stripped" ] && continue

    total=$((total + 1))
    if ping -c1 -W2 "$stripped" &> /dev/null; then
        echo -e "\t$stripped is up and running"
        success=$((success + 1))
    else
        echo -e "\tUnable to connect to $stripped"
        fail=$((fail + 1))
    fi
done < "$hosts"

echo
echo -e "\t==========================\tSummary\t=========================="
echo -e "\tTotal hosts: $total"
echo -e "\tSuccessful:  $success"
echo -e "\tFailed:      $fail"
echo
