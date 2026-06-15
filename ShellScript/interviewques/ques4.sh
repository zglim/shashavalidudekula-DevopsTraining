#!/bin/bash
#Purpose: Bash Scripting Training
#Author : Shashavali
#Date: 12th Jun,2022
#use: Script to check given input is file/dir.. if it is a file display contentes, if it is a dir list no of files in dir

read -p "Enter file/dir name: " name

# Handle empty input
if [ -z "$name" ]; then
    echo "Error: No input provided." >&2
    exit 1
fi

# Handle non-existent path
if [ ! -e "$name" ]; then
    echo "Error: '$name' does not exist." >&2
    exit 1
fi

if [ -f "$name" ]; then
    echo "=== '$name' is a file ==="
    echo "--- Contents ---"
    cat "$name"
    exit 0
fi

if [ -d "$name" ]; then
    files=$(find "$name" -maxdepth 1 -type f | wc -l | tr -d ' ')
    echo "=== '$name' is a directory ==="
    echo "File count: $files"
    echo "--- Directory listing ---"
    ls "$name"
    exit 0
fi

echo "Error: '$name' is neither a regular file nor a directory." >&2
exit 1
