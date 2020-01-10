#!/bin/bash


yum install fio -y &> /dev/null

fio --name=fio-rand-readwrite --filename=/mnt/fio-rand-readwrite --readwrite=randrw  --bs=4K --direct=1 --numjobs=1 --time_based=1 --runtime=36000 --size=10G --iodepth=4 --fsync_on_close=1 --rwmixread=75 --ioengine=libaio --rate=64k --rate_process=poisson --output-format=json --output /mnt/fio_result.json &> /dev/null
