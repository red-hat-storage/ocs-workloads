FROM alpine:latest
RUN apk add --no-cache python3 py3-pip bash coreutils git automake autoconf build-base pv
RUN git clone https://github.com/avati/arequal.git
WORKDIR arequal
RUN ./autogen.sh ; ./configure ; make ; make install
WORKDIR /
ADD https://raw.githubusercontent.com/red-hat-storage/ocs-workloads/master/rdr/busybox/scripts/simple_io_integrity_check.sh /mnt/simple_io_integrity_check.sh
RUN chmod +x /mnt/simple_io_integrity_check.sh
ADD https://raw.githubusercontent.com/red-hat-storage/ocs-workloads/master/rdr/busybox/scripts/simple_io.sh /mnt/simple_io.sh
RUN chmod +x /mnt/simple_io.sh
RUN apk del git automake autoconf build-base --no-cache 
RUN rm -rf arequal
