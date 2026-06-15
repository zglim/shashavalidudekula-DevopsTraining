#!/bin/bash
#Purpose: Batch file creation utility with CLI options
#Author: Shashavali (extended)
#Date: 9th June,2022
#Use: Create files with configurable naming, directory, preview and overwrite protection.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────
COUNT=5
PREFIX="name"
DEST_DIR="."
EXT="txt"
START=1
PREVIEW=false

# ── Usage ─────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Create numbered files in batch.

Options:
  -n NUM    Number of files to create (positive integer, default: $COUNT)
  -p PREFIX Filename prefix (default: "$PREFIX")
  -d DIR    Target directory (default: current directory)
  -e EXT    File extension without dot (default: "$EXT")
  -s START  Starting sequence number (default: $START)
  -y        Preview mode: print planned filenames without creating them
  -h        Show this help message

Examples:
  $(basename "$0")                        # create name1.txt .. name5.txt in .
  $(basename "$0") -n 3 -p log -e csv    # log1.csv log2.csv log3.csv
  $(basename "$0") -n 10 -s 5 -d /tmp/out # name5.txt .. name14.txt in /tmp/out
  $(basename "$0") -y -n 3               # preview only
EOF
    exit 0
}

# ── Parse arguments ───────────────────────────────────────
while getopts ":n:p:d:e:s:yh" opt; do
    case $opt in
        n) COUNT="$OPTARG" ;;
        p) PREFIX="$OPTARG" ;;
        d) DEST_DIR="$OPTARG" ;;
        e) EXT="$OPTARG" ;;
        s) START="$OPTARG" ;;
        y) PREVIEW=true ;;
        h) usage ;;
        :) echo "Error: option -$OPTARG requires an argument." >&2; exit 1 ;;
        *) echo "Error: unknown option -$OPTARG" >&2; exit 1 ;;
    esac
done

# ── Input validation ──────────────────────────────────────
errors=0

# COUNT must be a positive integer
if ! [[ "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: count (-n) must be a positive integer, got '$COUNT'." >&2
    errors=$((errors + 1))
fi

# START must be a non-negative integer (0 is acceptable)
if ! [[ "$START" =~ ^[0-9]+$ ]]; then
    echo "Error: start (-s) must be a non-negative integer, got '$START'." >&2
    errors=$((errors + 1))
fi

# PREFIX must not be empty
if [[ -z "$PREFIX" ]]; then
    echo "Error: prefix (-p) must not be empty." >&2
    errors=$((errors + 1))
fi

# EXT must not be empty
if [[ -z "$EXT" ]]; then
    echo "Error: extension (-e) must not be empty." >&2
    errors=$((errors + 1))
fi

# Target directory handling
if [[ ! -d "$DEST_DIR" ]]; then
    # Try to create it
    if mkdir -p "$DEST_DIR" 2>/dev/null; then
        echo "Info: created target directory '$DEST_DIR'."
    else
        echo "Error: target directory '$DEST_DIR' does not exist and could not be created." >&2
        errors=$((errors + 1))
    fi
fi

if [[ $errors -gt 0 ]]; then
    echo "Aborting due to $errors validation error(s)." >&2
    exit 1
fi

# ── Build filename list ───────────────────────────────────
filenames=()
end=$((START + COUNT - 1))
for i in $(seq "$START" "$end"); do
    filenames+=("${PREFIX}${i}.${EXT}")
done

# ── Preview mode ──────────────────────────────────────────
if [[ "$PREVIEW" == true ]]; then
    echo "=== Preview mode (no files will be created) ==="
    echo "Target directory: $DEST_DIR"
    echo "Planned files ($COUNT):"
    for f in "${filenames[@]}"; do
        echo "  $DEST_DIR/$f"
    done
    echo "=== End of preview ==="
    exit 0
fi

# ── Create files with overwrite protection ────────────────
created=0
skipped=0
failed=0

for f in "${filenames[@]}"; do
    filepath="$DEST_DIR/$f"
    if [[ -e "$filepath" ]]; then
        echo "SKIP: '$filepath' already exists."
        skipped=$((skipped + 1))
        continue
    fi
    if touch "$filepath" 2>/dev/null; then
        echo "OK:   '$filepath' created."
        created=$((created + 1))
    else
        echo "FAIL: could not create '$filepath'." >&2
        failed=$((failed + 1))
    fi
done

# ── Summary ───────────────────────────────────────────────
echo
echo "===== Summary ====="
echo "Target directory : $DEST_DIR"
echo "Planned          : $COUNT"
echo "Created          : $created"
echo "Skipped (exist)  : $skipped"
echo "Failed           : $failed"
echo "==================="
