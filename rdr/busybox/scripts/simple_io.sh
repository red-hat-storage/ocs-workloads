#!/bin/sh

hostname=$(hostname -f)
hashfile=/mnt/test/hashfile
target_dir=/mnt/test
special_chars='@#$%^&*'  # String of special characters

while true
do
    for i in 1 2 3 4 5
    do
        timestamp=$(date +%s)

        random_number=$(echo $((RANDOM % 100000))$(($RANDOM % 100000)))

        # Randomly select a special character
        random_index=$(($RANDOM % ${#special_chars} + 1))
        random_char=$(echo "$special_chars" | cut -c"$random_index")

        # Create a filename with the random special character

        file=/mnt/test/data_${timestamp}_${hostname}_${random_number}_$random_char
        echo "$(date): Creating file: $file"
        dd if=/dev/urandom of=$file bs=1k count=$(($RANDOM%3+1)) oflag=direct
        md5sum $file >>$hashfile
        echo "$(date): File created and checksum added: $file"
        
    done
    sync
        sleep $(($RANDOM%25+1))

    # Optionally check hashfile integrity after creating 5 files
    if [ $(($RANDOM%2)) = 1 ]
    then
        echo "$(date): Checking integrity of files in hashfile"
        md5sum -c --quiet $hashfile
        echo "$(date): Integrity check completed" 
    fi
    # Get the size of the mount point and number of files
    mount_size=$(df -h "$target_dir" | awk 'NR==2 {print $4}')
    file_count=$(find "$target_dir" -type f | wc -l)

    # Print available space and file count in green on terminal and log to file
    echo -e "\e[32m$(date): Available space on $target_dir: $mount_size\e[0m" 
    echo -e "\e[32m$(date): Number of files in $target_dir: $file_count\e[0m"
done
