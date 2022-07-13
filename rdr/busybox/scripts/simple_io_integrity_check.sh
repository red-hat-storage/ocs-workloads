#!/bin/bash

HASHFILE=/mnt/test/hashfile

if [ -f "$HASHFILE" ]; then
    echo "Found hashfile"
else
    echo "Hashfile not found, can't continue with integrity check"
    exit 1
fi

md5sum -c --quiet $HASHFILE
exit $?
