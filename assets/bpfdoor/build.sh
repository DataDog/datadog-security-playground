#!/bin/bash
# Build script for fake-bpfdoor binary
# This script compiles the BPFDoor simulator using gcc

set -e  # Exit on error
set -u  # Exit on undefined variable

# Configuration
BINARY_NAME="fake-bpfdoor.x64"
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

# Display build info
echo "Source: $SOURCE_FILE"
echo "Target: $BINARY_NAME"
echo "Compiler: $(gcc --version | head -n1)"
echo ""

# Compile
echo "Compiling..."
gcc -o "$BINARY_NAME" "$SOURCE_FILE"

# Verify binary was created
if [ -f "$BINARY_NAME" ]; then
    echo -e "${GREEN}✓ Build successful!${NC}"
    echo ""
    echo "Binary information:"
    ls -lh "$BINARY_NAME"
    file "$BINARY_NAME" || true
    exit 0
else
    echo -e "${RED}✗ Build failed!${NC}"
    exit 1
fi
