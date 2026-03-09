#!/bin/bash
# Build script for fake-bpfdoor binary
# This script compiles the BPFDoor simulator for x64 and arm64

set -e  # Exit on error
set -u  # Exit on undefined variable

# Configuration
SOURCE_FILE="fake-bpfdoor.c"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "==================================="
echo "Building BPFDoor Simulator"
echo "==================================="

# Check if source file exists
if [ ! -f "$SOURCE_FILE" ]; then
    echo -e "${RED}Error: Source file $SOURCE_FILE not found${NC}"
    exit 1
fi

build_target() {
    local binary="$1"
    local cc="$2"

    echo "Source: $SOURCE_FILE"
    echo "Target: $binary"
    echo "Compiler: $($cc --version | head -n1)"
    echo ""
    echo "Compiling..."
    $cc -o "$binary" "$SOURCE_FILE"

    if [ -f "$binary" ]; then
        echo -e "${GREEN}✓ Build successful: $binary${NC}"
        ls -lh "$binary"
        file "$binary" || true
        echo ""
    else
        echo -e "${RED}✗ Build failed: $binary${NC}"
        exit 1
    fi
}

build_target "fake-bpfdoor.x64"  "gcc"
build_target "fake-bpfdoor.arm64" "aarch64-linux-gnu-gcc"
