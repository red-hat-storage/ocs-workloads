FROM alpine:3.19

# Install required packages including curl
RUN apk add --no-cache python3 py3-pip bash coreutils git automake autoconf build-base pv curl

# Clone and build arequal
RUN git clone https://github.com/avati/arequal.git
WORKDIR arequal
RUN ./autogen.sh && ./configure && make && make install

# Clean up build tools to reduce image size
WORKDIR /
RUN apk del git automake autoconf build-base --no-cache \
    && rm -rf arequal

# Download kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl

# Optional: Verify kubectl is installed
RUN kubectl version --client