FROM alpine:latest
RUN apk add --no-cache python3 py3-pip bash coreutils git automake autoconf build-base pv
RUN git clone https://github.com/avati/arequal.git
WORKDIR arequal
RUN ./autogen.sh ; ./configure ; make ; make install
WORKDIR /
RUN apk del git automake autoconf build-base --no-cache 
RUN rm -rf arequal
