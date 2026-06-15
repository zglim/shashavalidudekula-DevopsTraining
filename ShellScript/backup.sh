#!/bin/bash
#Purpose: Create a compressed backup of a given directory
#Author: Shashavali (refactored)
#Date: 13th June,2022
#Use: backup.sh [-s SOURCE_DIR] [-o OUTPUT_DIR] [-r REMOTE_TARGET]
#     SOURCE_DIR   - directory to back up        (default: current directory)
#     OUTPUT_DIR   - where to write the archive  (default: /tmp)
#     REMOTE_TARGET- optional scp destination; skipped when not provided

set -euo pipefail

##############################################################################
# Defaults
##############################################################################
SOURCE_DIR="."
OUTPUT_DIR="/tmp"
REMOTE_TARGET=""

##############################################################################
# Usage
##############################################################################
usage() {
    echo "Usage: $0 [-s SOURCE_DIR] [-o OUTPUT_DIR] [-r REMOTE_TARGET]"
    echo ""
    echo "  -s SOURCE_DIR     Directory to back up (default: current directory)"
    echo "  -o OUTPUT_DIR     Directory to place the archive in (default: /tmp)"
    echo "  -r REMOTE_TARGET  Optional scp destination (user@host:/path)"
    echo "  -h                Show this help message"
    exit 1
}

##############################################################################
# Parse arguments
##############################################################################
while getopts "s:o:r:h" opt; do
    case "$opt" in
        s) SOURCE_DIR="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        r) REMOTE_TARGET="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

##############################################################################
# Pre-flight checks
##############################################################################

# Resolve to absolute path for clear messages
SOURCE_DIR="$(cd "$SOURCE_DIR" 2>/dev/null && pwd)" || {
    echo "ERROR: Source directory '$SOURCE_DIR' does not exist or is not accessible." >&2
    exit 1
}

if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: Source directory '$SOURCE_DIR' does not exist." >&2
    exit 1
fi

if [ ! -r "$SOURCE_DIR" ]; then
    echo "ERROR: Source directory '$SOURCE_DIR' is not readable." >&2
    exit 1
fi

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "ERROR: Output directory '$OUTPUT_DIR' does not exist." >&2
    exit 1
fi

if [ ! -w "$OUTPUT_DIR" ]; then
    echo "ERROR: Output directory '$OUTPUT_DIR' is not writable." >&2
    exit 1
fi

# Build archive file paths
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BASENAME="$(basename "$SOURCE_DIR")"
TAR_FILE="${OUTPUT_DIR}/backup_${BASENAME}_${TIMESTAMP}.tar"
GZ_FILE="${TAR_FILE}.gz"

if [ -e "$TAR_FILE" ] || [ -e "$GZ_FILE" ]; then
    echo "ERROR: Target archive file already exists: ${GZ_FILE}" >&2
    exit 1
fi

##############################################################################
# Step 1 - Create tar archive
##############################################################################
echo "Packing '$SOURCE_DIR' into '$TAR_FILE' ..."
if ! tar -cf "$TAR_FILE" -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")" 2>/dev/null; then
    echo "ERROR: tar failed while packing '$SOURCE_DIR'." >&2
    rm -f "$TAR_FILE"
    exit 1
fi
echo "Tar archive created successfully."

##############################################################################
# Step 2 - Compress with gzip
##############################################################################
echo "Compressing '$TAR_FILE' ..."
if ! gzip "$TAR_FILE" 2>/dev/null; then
    echo "ERROR: gzip failed while compressing '$TAR_FILE'." >&2
    rm -f "$TAR_FILE" "$GZ_FILE"
    exit 1
fi
echo "Compression successful: $GZ_FILE"

##############################################################################
# Step 3 - Optional remote upload
##############################################################################
if [ -n "$REMOTE_TARGET" ]; then
    echo "Uploading '$GZ_FILE' to '$REMOTE_TARGET' ..."
    if ! scp "$GZ_FILE" "$REMOTE_TARGET" 2>/dev/null; then
        echo "ERROR: scp upload to '$REMOTE_TARGET' failed." >&2
        echo "Local backup is still available at: $GZ_FILE"
        exit 1
    fi
    echo "Upload to '$REMOTE_TARGET' succeeded."
else
    echo "No remote target specified; skipping upload."
fi

##############################################################################
# Done
##############################################################################
echo ""
echo "Backup completed successfully."
echo "  Archive: $GZ_FILE"
if [ -n "$REMOTE_TARGET" ]; then
    echo "  Uploaded to: $REMOTE_TARGET"
fi
