HASHFILE=/mnt/test/hashfile

if [ -f "$HASHFILE" ]; then
    echo "Found hashfile"
else
    echo "Hashfile not found, can't continue with integrity check"
    if [ "$CONTAINER_VALUE" == "init" ]
    then
        exit 0
    else
        exit 1
    fi
fi
if [ "$CONTAINER_VALUE" == "init" ]
then
	md5sum -c $HASHFILE
else
	md5sum -c --quiet $HASHFILE
fi

retVal=$?
if [ $retVal -ne 0 ]; then
    echo "Error"
else
    echo "Integrity checked Passed"
fi
exit $retVal