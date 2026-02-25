#!/bin/bash

# Check if at least one argument (search string) is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <search_string1> [<search_string2> ...]"
    exit 1
fi

# Find all .R files recursively and search for the provided strings
find . -type f -name "*.R" | while read -r file; do
    grep -Hn "${@}" "$file" 2>/dev/null
done
