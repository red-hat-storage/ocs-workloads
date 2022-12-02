KERNEL_TAR_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.280.tar.gz"
KERNEL_VERSION=`echo $KERNEL_TAR_URL | cut -d '/' -f8 | sed 's/.tar.gz$//'`
MOUNT=/mnt/test/
MASTER_COPY=$KERNEL_VERSION".tar.gz"
KERNEL_DIRECTORY=$KERNEL_VERSION
MASTER_CHECKSUM_FILE="$MOUNT/kernel_hash"
# Allow only upto 90% full disk space
DISK_SPACE_FULL_THRESHOLD=45
# During make free space, don't delete below 50% usage
FREE_SPACE_THRESHOLD=20
# SIGNALLING THROUGH FILES
PAUSE_FILE="IO_PAUSE"
RUNNING_FILE="IO_RUNNING"

get_disk_usage()
{
    usage=`df $MOUNT --output=pcent | sed -n 2p | cut -d "%" -f1`
    echo $usage
}


# Auto cleanup of directories in case if we don't enough space
# We will bring down the space usage to 50% and stop deletion
# so that if failover occurs at the point after deletion but before
# beginning directory creation we will still have some data
make_free_space()
{
    ls -d "$KERNEL_VERSION"_[0-9]*
    if [ $? -eq 0 ]; then
        testdir=`ls -d "$KERNEL_VERSION"_[0-9]* | sed -n 1p`
        echo "Cleaning up $testdir "
        rm -rf $testdir
        sync -f $MOUNT
        cur_usage=$(get_disk_usage)
        if [ $cur_usage -gt $FREE_SPACE_THRESHOLD ]; then
            make_free_space
        fi
    fi
}

# block if there is no diskspace
block_if_no_space_left()
{
    usage=$(get_disk_usage)
    if [ $usage -gt $DISK_SPACE_FULL_THRESHOLD ]; then
        echo "Disk usage greater than "$DISK_SPACE_FULL_THRESHOLD"%, Can't continue IO"
	sleep 10
	make_free_space
    fi
}

# IO status needs to be paused if checksum needs to be calculated
wait_if_pause()
{
    while [ -f $PAUSE_FILE ]
    do
        if [ -f $RUNNING_FILE ]; then
            unlink $RUNNING_FILE
            sync -f $MOUNT
        fi
        sleep 10
    done
}

# set running state
set_running_state()
{
    touch $RUNNING_FILE
    sync -f $MOUNT
}

# Run kernal untar
untar_kernal_file()
{
    # Sleeping for some random interval of time to reduce stress
    echo "Sleeping for $sleep_time"
    sleep $sleep_time
    tar xfz $MASTER_COPY
    if [ $? -ne 0 ];
    then
        echo "Failed to untar kernel"
        exit 1
    fi
    
}

if [ -f "$MOUNT""/""$MASTER_COPY" ]; then
    echo "Master copy tar already exists"
else
    echo "Downloading kernel tar"
    wget $KERNEL_TAR_URL -O $MOUNT/$MASTER_COPY
    if [ $? -eq 0 ];
    then
        echo "Kernel tar ball downloaded successfully"
    else
        echo "Failed to download kernel"
        exit 1
    fi
fi

if [ -f "$MOUNT""/""$MASTER_COPY" ]; then
    if [ -d "$MOUNT""/""$KERNEL_DIRECTORY"_original ]; then
        echo "Reference Kernel dir already exists"
    else
        # If we have broken linux-<version> dir, lets clean it up
        if [ -d "$MOUNT""/""$KERNEL_DIRECTORY" ]; then
            rm -rf $MOUNT/$KERNEL_DIRECTORY
        fi
        cd $MOUNT
        tar xfz $MASTER_COPY
        if [ $? -ne 0 ];
        then
            echo "Failed to untar reference kernel"
            exit 1
        fi
        arequal-checksum $MOUNT/$KERNEL_DIRECTORY>$MASTER_CHECKSUM_FILE
	echo "Performing mv operation for saving original kernal Directory"
        mv $MOUNT/$KERNEL_DIRECTORY $MOUNT/$KERNEL_DIRECTORY"_original"
    fi
fi

# From here keep a loop of untaring and renaming the kernel dirs
sleep_time=$(shuf -i 180-500 -n1)
while true
do
    sync -f $MOUNT
    echo "Sleeping for $sleep_time"
    sleep $sleep_time
    block_if_no_space_left
    # There could be half untared linx dir
    # may be due to failover , so we need to cleanup
    if [ -d $KERNEL_DIRECTORY ]; then
    	echo "Performing rm opeation of $KERNEL_DIRECTORY"
        rm -rf $KERNEL_DIRECTORY
    fi
    cd $MOUNT
    wait_if_pause
    # We are out of pause state
    # create a file for IO running
    set_running_state
    # run io
    untar_kernal_file
    echo "Performing mv operation of kernal directory to new directiry location"
    mv $MOUNT/$KERNEL_DIRECTORY $MOUNT/$KERNEL_DIRECTORY"_`date +%s`"

done
