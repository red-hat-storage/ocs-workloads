while true
    file=/mnt/test/data_`date +%s`
    hashfile=/mnt/test/hashfile
    do
        dd if=/dev/urandom of=$file bs=4k count=$(($RANDOM%3+1)) oflag=direct
        md5sum $file >>$hashfile
        sync
        sleep $(($RANDOM%15+1))
        if [ $(($RANDOM%2)) == 1 ]
        then
            md5sum -c --quiet $hashfile
        fi
    done
