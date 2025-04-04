HASHFILE="/mnt/test/hashfile"

# Check if hashfile exists
if [ -f "$HASHFILE" ]; then
    echo "Found hashfile"
else
    echo "Hashfile not found, can't continue with integrity check"

    # Exit code based on container mode
    if [ "$CONTAINER_VALUE" == "init" ]; then
        exit 0  # OK during init
    else
        exit 1  # Error in other modes
    fi
fi

# Run checksum verification based on mode
if [ "$CONTAINER_VALUE" == "init" ]; then
    md5sum -c "$HASHFILE"
else
    md5sum -c --quiet "$HASHFILE"
fi

# Capture and evaluate result
retVal=$?
if [ $retVal -ne 0 ]; then
    echo "Error: Integrity check failed"
else
    echo "Integrity check passed"
fi

exit $retVal
