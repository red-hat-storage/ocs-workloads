FROM alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc
RUN apk add --no-cache python3 py3-pip bash coreutils git automake autoconf build-base pv
RUN git clone https://github.com/avati/arequal.git
WORKDIR arequal
RUN ./autogen.sh ; ./configure ; make ; make install
WORKDIR /
COPY rdr/busybox/scripts/simple_io_integrity_check.sh /mnt/
RUN chmod +x /mnt/simple_io_integrity_check.sh
COPY rdr/busybox/scripts/simple_io.sh /mnt/
RUN chmod +x /mnt/simple_io.sh
RUN apk del git automake autoconf build-base --no-cache 
RUN rm -rf arequal
