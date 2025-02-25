Cyan='\033[0;36m'         
NC='\033[0m' # No Color

while true
    hostname=$(hostname -f)
    file=/mnt/test/data_`date +%s`_$hostname
    printf "Creating file with name:-  ${Cyan}$file ${NC}\n"
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
