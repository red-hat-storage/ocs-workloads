
Cyan='\033[0;36m'
NC='\033[0m' # No Color

hashfile="/mnt/test/hashfile"
max_files=1000000
count=0

while [ $count -lt $max_files ]; do
    hostname=$(hostname -f)
    file="/mnt/test/data_$(date +%s)_$hostname"

    printf "Creating file with name: ${Cyan}$file${NC}\n"

    dd if=/dev/urandom of="$file" bs=4k count=$((RANDOM % 3 + 1)) oflag=direct status=none
    md5sum "$file" >> "$hashfile"
    sync

    sleep $((RANDOM % 15 + 1))

    if [ $((RANDOM % 2)) -eq 1 ]; then
        echo "Verifying file hashes..."
        md5sum -c --quiet "$hashfile"
    fi

    count=$((count + 1))
done

echo "Reached max file count: $max_files"
