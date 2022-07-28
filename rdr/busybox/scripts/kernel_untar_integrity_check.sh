KERNEL_TAR_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.280.tar.gz"
KERNEL_VERSION=`echo $KERNEL_TAR_URL | cut -d '/' -f8 | sed 's/.tar.gz$//'`
MOUNT=/mnt/test/
MASTER_CHECKSUM_FILE=$MOUNT"/kernel_hash"
KERNEL_DIRECTORY=$KERNEL_VERSION
# SIGNALLING THROUGH FILES
PAUSE_FILE="IO_PAUSE"
RUNNING_FILE="IO_RUNNING"

if [ -f $MASTER_CHECKSUM_FILE ]; then
    echo "Found master checksum file, proceeding with checksum validation"
else
    echo "Master checksum file not found, couldn't proceed with checksum validation"
    exit 1
fi

wait_if_io_running()
{
    while [ -f $RUNNING_FILE ]
    do
        sleep 10
    done
}

# Iterate over all dirs , calculate checksum of each and find the diff
# with MASTER_CHECKSUM_FILE
cd $MOUNT
# Convey that we want to calculate checksum , let IOs come to pause
touch $PAUSE_FILE
wait_if_io_running
ls -d "$KERNEL_VERSION"_[0-9]*
if [ $? -gt 0 ]; then
    exit 1
fi

for ent in `ls -d "$KERNEL_VERSION"_[0-9]*`
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
unlink $PAUSE_FILE
sync -f $MOUNT
