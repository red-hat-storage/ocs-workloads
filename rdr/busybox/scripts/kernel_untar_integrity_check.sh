#!/bin/bash

MOUNT=/mnt/test/
MASTER_CHECKSUM_FILE=$MOUNT"/kernel_hash"
KERNEL_DIRECTORY="linux-master"

if [ -f $MASTER_CHECKSUM_FILE ]; then
    echo "Found master checksum file, proceeding with checksum validation"
else
    echo "Master checksum file not found, couldn't proceed with checksum validation"
    exit 1
fi

# Iterate over all dirs , calculate checksum of each and find the diff
# with MASTER_CHECKSUM_FILE
cd $MOUNT
for ent in `ls`
do
    if [ -d "$ent" ]; then
        if [ "$KERNEL_DIRECTORY" != "$ent" ] && [ "$ent" != "$MOUNT/$KERNEL_DIRECTORY_original" ];
        then
            arequal-checksum $ent>>$ent"_checksum"
            diff $MASTER_CHECKSUM_FILE $ent"_checksum"
            if [ $? -ne 0 ];
            then
                echo "Arequal Checksum mismatch for $ent"
                exit 1
            else
                unlink $ent"_checksum"
            fi
        fi
    fi
done
