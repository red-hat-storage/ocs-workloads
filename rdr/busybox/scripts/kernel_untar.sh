#!/bin/bash

KERNEL_ZIP_URL="https://github.com/torvalds/linux/archive/refs/heads/master.zip"
MOUNT=/mnt/test/
MASTER_COPY=master_kernel.zip
KERNEL_DIRECTORY="linux-master"
MASTER_CHECKSUM_FILE="$MOUNT/kernel_hash"

wget $KERNEL_ZIP_URL -O $MOUNT/$MASTER_COPY
if [ $? -eq 0 ];
then
    echo "Kernel zip downloaded successfully"
else
    echo "Failed to download kernel"
    exit 1
fi

if [ -f "$MOUNT/$MASTER_COPY" ]; then
    unzip -q $MOUNT/$MASTER_COPY -d $MOUNT/
    if [ $? -ne 0 ];
    then
        echo "Failed to unzip reference kernel"
        exit 1
    fi
    arequal-checksum $MOUNT/$KERNEL_DIRECTORY>>$MASTER_CHECKSUM_FILE
    mv $MOUNT/$KERNEL_DIRECTORY $MOUNT/$KERNEL_DIRECTORY"_original"
fi

# From here keep a loop of untaring and renaming the kernel dirs
while true
do
    unzip -q $MOUNT/$MASTER_COPY -d $MOUNT/
    if [ $? -ne 0 ];
    then
        echo "Failed to unzip kernel"
        exit 1
    fi
    mv $MOUNT/$KERNEL_DIRECTORY $MOUNT/$KERNEL_DIRECTORY"_`date +%s`"
done
