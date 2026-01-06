# Multi-stage Dockerfile for building Datadog Security Playground assets
# This provides a reproducible build environment for all simulation binaries

###############################################################################
# Build image for BPFDoor simulator, uses Ubuntu 24.04 base image
###############################################################################
FROM ubuntu@sha256:c35e29c9450151419d9448b0fd75374fec4fff364a27f176fb458d472dfc9e54 AS bpfdoor-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y file \
        gcc-14-x86-64-linux-gnu \
        binutils-x86-64-linux-gnu \
        libc6-dev-amd64-cross

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/x86_64-linux-gnu-gcc-14 10 \
    --slave /usr/bin/as as /usr/bin/x86_64-linux-gnu-as \
    --slave /usr/bin/ld ld /usr/bin/x86_64-linux-gnu-ld

ENV CC=x86_64-linux-gnu-gcc

WORKDIR /build
COPY bpfdoor/fake-bpfdoor.c bpfdoor/build.sh ./
RUN chmod +x build.sh && ./build.sh

###############################################################################
# Build image for malware simulator (uses Go 1.24.3)
###############################################################################
FROM golang@sha256:81bf5927dc91aefb42e2bc3a5abdbe9bb3bae8ba8b107e2a4cf43ce3402534c6 AS malware-builder

WORKDIR /build
COPY malware/go.mod malware/go.sum ./
RUN go mod download
COPY malware/main.go malware/build.sh ./
RUN chmod +x build.sh && ./build.sh

###############################################################################
# Copy built binaries from builder images to final image
###############################################################################
FROM alpine:latest

WORKDIR /output
COPY --from=bpfdoor-builder /build/fake-bpfdoor.x64 ./bpfdoor/
COPY --from=malware-builder /build/malware.x64 ./malware/
COPY --from=malware-builder /build/malware.arm64 ./malware/

CMD ["ls", "-lhR", "/output/*"]
