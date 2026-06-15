#!/bin/bash
#Purpose: Batch file creation with flexible command-line options
#Author: Shashavali (enhanced)
#Date: 9th June,2022
#Use: Create files with user input or command-line arguments.
#
# Usage:
#   ./createfiles.sh [OPTIONS]
#
# Options:
#   -n, --count NUM       Number of files to create (required, positive integer)
#   -p, --prefix NAME     File name prefix (required, non-empty)
#   -d, --dir DIR         Target directory (default: current directory)
#   -e, --ext EXT         File extension without dot (default: txt)
#   -s, --start NUM       Starting sequence number (default: 1)
#       --dry-run         Preview mode: show planned file names without creating
#   -h, --help            Show this help message
#
# Examples:
#   ./createfiles.sh -n 5 -p report
#   ./createfiles.sh -n 3 -p log -d /tmp/logs -e csv -s 10
#   ./createfiles.sh -n 5 -p data --dry-run

set -euo pipefail

# --- defaults ---
COUNT=""
PREFIX=""
DIR="."
EXT="txt"
START=1
DRY_RUN=0

# --- helper functions ---
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^#/s/^# \{0,1\}//p }' "$0"
    exit 0
}

die() {
    echo "ERROR: $1" >&2
    exit 1
}

is_positive_int() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_non_negative_int() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 0 ]
}

# --- parse arguments ---
if [ $# -eq 0 ]; then
    # Interactive fallback for backward compatibility
    echo
    echo "How many files you want to create: "
    read -r COUNT
    echo
    echo "Enter the starting name of the file "
    read -r PREFIX
    echo
fi

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--count)  shift; COUNT="${1:-}"; shift ;;
        -p|--prefix) shift; PREFIX="${1:-}"; shift ;;
        -d|--dir)    shift; DIR="${1:-}"; shift ;;
        -e|--ext)    shift; EXT="${1:-}"; shift ;;
        -s|--start)  shift; START="${1:-}"; shift ;;
        --dry-run)   DRY_RUN=1; shift ;;
        -h|--help)   usage ;;
        *)           die "Unknown option: $1" ;;
    esac
done

# --- validate inputs ---
[ -z "$COUNT" ]  && die "Count is required. Use -n NUM."
[ -z "$PREFIX" ] && die "Prefix is required. Use -p NAME."
[ -z "$EXT" ]    && die "Extension must not be empty."

is_positive_int "$COUNT" || die "Count must be a positive integer, got: '$COUNT'"
is_non_negative_int "$START" || die "Start must be a non-negative integer, got: '$START'"

# --- ensure target directory ---
if [ ! -d "$DIR" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "NOTE: Directory '$DIR' does not exist (would be created in normal mode)."
    else
        mkdir -p "$DIR" || die "Failed to create directory: $DIR"
        echo "Created directory: $DIR"
    fi
fi

# --- build file list ---
PLANNED=0
CREATED=0
SKIPPED=0
FAILED=0
END=$(( START + COUNT - 1 ))

if [ "$DRY_RUN" -eq 1 ]; then
    echo "=== DRY-RUN PREVIEW ==="
    echo "The following files would be created in '$(cd "$DIR" 2>/dev/null && pwd || echo "$DIR")':"
    echo
    for i in $(seq "$START" "$END"); do
        PLANNED=$(( PLANNED + 1 ))
        FILEPATH="${DIR}/${PREFIX}${i}.${EXT}"
        if [ -e "$FILEPATH" ]; then
            echo "  [SKIP] $FILEPATH  (already exists)"
        else
            echo "  [CREATE] $FILEPATH"
        fi
    done
    echo
    echo "=== DRY-RUN SUMMARY ==="
    echo "Planned:  $COUNT file(s)"
    echo "Directory: $(cd "$DIR" 2>/dev/null && pwd || echo "$DIR")"
    echo "No files were created."
    exit 0
fi

# --- create files ---
for i in $(seq "$START" "$END"); do
    PLANNED=$(( PLANNED + 1 ))
    FILEPATH="${DIR}/${PREFIX}${i}.${EXT}"

    if [ -e "$FILEPATH" ]; then
        echo "[SKIP] $FILEPATH already exists"
        SKIPPED=$(( SKIPPED + 1 ))
        continue
    fi

    if touch "$FILEPATH" 2>/dev/null; then
        echo "[OK] $FILEPATH created"
        CREATED=$(( CREATED + 1 ))
    else
        echo "[FAIL] $FILEPATH could not be created" >&2
        FAILED=$(( FAILED + 1 ))
    fi
done

# --- summary ---
echo
echo "=== SUMMARY ==="
echo "Planned:   $PLANNED"
echo "Created:   $CREATED"
echo "Skipped:   $SKIPPED"
echo "Failed:    $FAILED"
echo "Directory: $(cd "$DIR" && pwd)"
