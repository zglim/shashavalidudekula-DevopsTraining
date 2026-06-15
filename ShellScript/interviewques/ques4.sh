#!/bin/bash
#Purpose: Bash Scripting Training
#Author : Shashavali
#Date: 12th Jun,2022
#use: Script to check given input is file/dir.. if it is a file display contents, if it is a dir list no of files in dir

echo
read -p "Enter file/dir name: " name
echo

# Check for empty input
if [ -z "$name" ]; then
	echo "Error: No input provided. Please enter a file or directory path."
	exit 1
fi

# Check if path exists
if [ ! -e "$name" ]; then
	echo "Error: '$name' does not exist."
	exit 1
fi

# Check if it is a regular file
if [ -f "$name" ]; then
	echo "=== File: $name ==="
	echo
	cat "$name"
	echo
	exit 0
fi

# Check if it is a directory
if [ -d "$name" ]; then
	files=$(find "$name" -maxdepth 1 -type f | wc -l)
	echo "=== Directory: $name ==="
	echo
	echo "You have $files file(s) in your '$name' directory."
	echo
	echo "Contents of '$name':"
	echo
	ls "$name"
	echo
	exit 0
fi

# Neither a regular file nor a directory (e.g., device, socket, pipe, etc.)
echo "Error: '$name' is neither a regular file nor a directory."
exit 1
