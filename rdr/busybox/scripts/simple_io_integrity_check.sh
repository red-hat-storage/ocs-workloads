#!/bin/bash

HASHFILE="/mnt/test/hashfile"
MAX_FILES=100

# Check if hashfile exists
if [ -f "$HASHFILE" ]; then
    echo "Found hashfile"
else
    echo "Hashfile not found, can't continue with integrity check"
    if [ "$CONTAINER_VALUE" == "init" ]; then
        exit 0
    else
        exit 1
    fi
fi

# Control the number of data files (files starting with 'data_')
file_count=$(ls /mnt/test/data_* 2>/dev/null | wc -l)
if [ "$file_count" -gt "$MAX_FILES" ]; then
    oldest_file=$(ls -t /mnt/test/data_* | tail -1)
    echo "Removing oldest file: $oldest_file"
    # Remove the corresponding entry from the hashfile as well
    grep -v "$(basename "$oldest_file")" "$HASHFILE" > "${HASHFILE}.tmp" && mv "${HASHFILE}.tmp" "$HASHFILE"
    rm -f "$oldest_file"
fi

# Run the integrity check based on CONTAINER_VALUE mode
if [ "$CONTAINER_VALUE" == "init" ]; then
    md5sum -c "$HASHFILE"
else
    md5sum -c --quiet "$HASHFILE"
fi

retVal=$?
if [ $retVal -ne 0 ]; then
    echo "Error: Integrity check failed"
else
    echo "Integrity check passed"
fi

exit $retVal

