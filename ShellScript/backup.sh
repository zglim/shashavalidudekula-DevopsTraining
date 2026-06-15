#!/bin/bash
# Purpose: Backup script with configurable source, output, and optional remote upload.
# Usage:   backup.sh [-s SOURCE_DIR] [-o OUTPUT_DIR] [-r REMOTE_TARGET] [-h]
#
#   -s SOURCE_DIR    Directory to back up        (default: current directory)
#   -o OUTPUT_DIR    Directory for the archive   (default: current directory)
#   -r REMOTE_TARGET Remote scp target           (optional, e.g. user@host:/path)
#   -h               Show this help message

set -o pipefail

# ---------- defaults ----------
SOURCE_DIR="$(pwd)"
OUTPUT_DIR="$(pwd)"
REMOTE_TARGET=""

# ---------- argument parsing ----------
usage() {
    echo "Usage: $0 [-s SOURCE_DIR] [-o OUTPUT_DIR] [-r REMOTE_TARGET] [-h]"
    echo
    echo "Options:"
    echo "  -s SOURCE_DIR    Directory to back up        (default: current directory)"
    echo "  -o OUTPUT_DIR    Directory for the archive   (default: current directory)"
    echo "  -r REMOTE_TARGET Remote scp target           (optional)"
    echo "  -h               Show this help message"
    exit 0
}

while getopts "s:o:r:h" opt; do
    case "$opt" in
        s) SOURCE_DIR="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        r) REMOTE_TARGET="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# ---------- derived paths ----------
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ARCHIVE_NAME="backup_${TIMESTAMP}.tar"
TAR_PATH="${OUTPUT_DIR}/${ARCHIVE_NAME}"
GZ_PATH="${TAR_PATH}.gz"

# ======================================================
# Phase 0: Pre-flight checks
# ======================================================

# Source directory must exist and be readable
if [ ! -d "$SOURCE_DIR" ]; then
    echo "[ERROR] Source directory does not exist: ${SOURCE_DIR}" >&2
    exit 1
fi

if [ ! -r "$SOURCE_DIR" ]; then
    echo "[ERROR] Source directory is not readable: ${SOURCE_DIR}" >&2
    exit 1
fi

# Output directory must exist and be writable
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "[ERROR] Output directory does not exist: ${OUTPUT_DIR}" >&2
    exit 1
fi

if [ ! -w "$OUTPUT_DIR" ]; then
    echo "[ERROR] Output directory is not writable: ${OUTPUT_DIR}" >&2
    exit 1
fi

# Target archive files must not already exist
if [ -e "$TAR_PATH" ]; then
    echo "[ERROR] Target archive already exists: ${TAR_PATH}" >&2
    exit 1
fi

if [ -e "$GZ_PATH" ]; then
    echo "[ERROR] Target archive already exists: ${GZ_PATH}" >&2
    exit 1
fi

# ======================================================
# Phase 1: tar — pack source directory
# ======================================================
echo "[INFO] Packing source directory: ${SOURCE_DIR} -> ${TAR_PATH}"
tar_output=$(tar -cf "$TAR_PATH" "$SOURCE_DIR" 2>&1)
tar_rc=$?

if [ $tar_rc -ne 0 ]; then
    echo "[ERROR] tar failed (exit code ${tar_rc})." >&2
    if [ -n "$tar_output" ]; then
        echo "  Details: ${tar_output}" >&2
    fi
    # Clean up partial file if it was created
    [ -f "$TAR_PATH" ] && rm -f "$TAR_PATH"
    exit 1
fi

echo "[INFO] tar completed successfully."

# ======================================================
# Phase 2: gzip — compress the tar archive
# ======================================================
echo "[INFO] Compressing archive: ${TAR_PATH} -> ${GZ_PATH}"
gzip_output=$(gzip "$TAR_PATH" 2>&1)
gzip_rc=$?

if [ $gzip_rc -ne 0 ]; then
    echo "[ERROR] gzip failed (exit code ${gzip_rc})." >&2
    if [ -n "$gzip_output" ]; then
        echo "  Details: ${gzip_output}" >&2
    fi
    # Clean up partial files
    [ -f "$TAR_PATH" ] && rm -f "$TAR_PATH"
    [ -f "$GZ_PATH" ] && rm -f "$GZ_PATH"
    exit 1
fi

if [ ! -f "$GZ_PATH" ]; then
    echo "[ERROR] gzip finished but output file not found: ${GZ_PATH}" >&2
    exit 1
fi

echo "[INFO] Compression successful: ${GZ_PATH}"

# ======================================================
# Phase 3: scp — optional remote upload
# ======================================================
if [ -z "$REMOTE_TARGET" ]; then
    echo "[INFO] No remote target specified. Skipping upload."
    echo "[OK] Local backup completed successfully: ${GZ_PATH}"
    exit 0
fi

echo "[INFO] Uploading to remote target: ${REMOTE_TARGET}"
scp_output=$(scp "$GZ_PATH" "$REMOTE_TARGET" 2>&1)
scp_rc=$?

if [ $scp_rc -ne 0 ]; then
    echo "[ERROR] scp upload failed (exit code ${scp_rc})." >&2
    if [ -n "$scp_output" ]; then
        echo "  Details: ${scp_output}" >&2
    fi
    echo "[WARN] Local backup is still available at: ${GZ_PATH}"
    exit 1
fi

echo "[OK] Backup and upload completed successfully."
echo "  Local archive:  ${GZ_PATH}"
echo "  Remote target:  ${REMOTE_TARGET}"
exit 0
