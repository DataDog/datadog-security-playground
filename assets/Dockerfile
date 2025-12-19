# Multi-stage Dockerfile for building Datadog Security Playground assets
# This provides a reproducible build environment for all simulation binaries

# Stage 1: Build BPFDoor simulator (requires gcc and Linux headers)
FROM gcc:13 AS bpfdoor-builder

WORKDIR /build
# Copy source code and build script
COPY bpfdoor/fake-bpfdoor.c bpfdoor/build.sh ./
# Make build script executable and run it
RUN chmod +x build.sh && ./build.sh

# Stage 2: Build malware simulator (requires Go toolchain)
FROM golang:1.24.3 AS malware-builder

WORKDIR /build
# Copy Go module files first for better layer caching
COPY malware/go.mod malware/go.sum ./
# Download dependencies
RUN go mod download
# Copy source code and build script
COPY malware/main.go malware/build.sh ./
# Make build script executable and run it
RUN chmod +x build.sh && ./build.sh

FROM alpine:latest

WORKDIR /output
# Copy all built artifacts
COPY --from=bpfdoor-builder /build/fake-bpfdoor.x64 ./bpfdoor/
COPY --from=malware-builder /build/malware.x64 ./malware/
COPY --from=malware-builder /build/malware.arm64 ./malware/

CMD ["ls", "-lhR", "/output/*"]
