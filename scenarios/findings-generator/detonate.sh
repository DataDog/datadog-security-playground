#!/bin/bash

# Script to generate findings for Essential Linux Binary Modified 
# This script performs various file operations on critical system binaries
# WARNING: This script modifies system binaries and requires root/sudo privileges
# Use only in test environments!

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TEST_BINARY_NAME="test_critical_binary_$$"
TEST_PATH="/usr/local/bin/${TEST_BINARY_NAME}"
SLEEP_INTERVAL=2  # Seconds between operations to allow agent to capture events
TEST_COUNT=1
TEST_NB=1

echo -e "${YELLOW}=================================================${NC}"
echo -e "${YELLOW}Essential Linux Binary Modified Finding Generator${NC}"
echo -e "${YELLOW}=================================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR: This script must be run as root (sudo)${NC}"
    echo "Usage: sudo $0 [operation]"
    echo ""
    echo "Operations:"
    echo "  all      - Run all operations (default)"
    echo "  chmod    - Change file permissions"
    echo "  chown    - Change file ownership"
    echo "  link     - Create symbolic link"
    echo "  rename   - Rename file"
    echo "  open     - Modify file contents"
    echo "  unlink   - Delete file"
    echo "  utimes   - Change file timestamps"
    exit 1
fi

OPERATION=${1:-all}

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up test files...${NC}"
    rm -f "${TEST_PATH}"
    rm -f "${TEST_PATH}.bak"
    rm -f "${TEST_PATH}_renamed"
    rm -f "/tmp/${TEST_BINARY_NAME}_link"
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

# Create test binary
create_test_binary() {
    echo -e "${GREEN}Creating test binary at ${TEST_PATH}${NC}"
    cat > "${TEST_PATH}" << 'EOF'
#!/bin/bash
# Test critical binary for FIM monitoring
echo "This is a test binary"
EOF
    chmod 755 "${TEST_PATH}"
    echo -e "${GREEN}✓ Test binary created${NC}"
    sleep $SLEEP_INTERVAL
}

# Test 1: chmod - Change file permissions
test_chmod() {
    echo ""
    echo -e "${YELLOW}[Test ${TEST_NB}/${TEST_COUNT}] Testing chmod operation...${NC}"
    echo "  Making file executable"
    chmod 755 "${TEST_PATH}"
    TEST_NB=$((TEST_NB + 1))
    echo -e "${GREEN}✓ chmod operation completed${NC}"
    echo "  Agent rule triggered: pci_11_5_critical_binaries_chmod"
    sleep $SLEEP_INTERVAL
    
    # Restore permissions
    chmod 755 "${TEST_PATH}"
}

# Test 2: chown - Change file ownership
test_chown() {
    echo ""
    echo -e "${YELLOW}[Test ${TEST_NB}/${TEST_COUNT}] Testing chown operation...${NC}"
    
    # Get current user and group (username:groupname format, not numeric IDs)
    ORIGINAL_OWNER=$(stat -c "%U:%G" "${TEST_PATH}")
    
    echo "  Changing ownership to nobody:nogroup"
    chown nobody:nogroup "${TEST_PATH}" 2>/dev/null || chown nobody:nobody "${TEST_PATH}"
    TEST_NB=$((TEST_NB + 1))
    echo -e "${GREEN}✓ chown operation completed${NC}"
    echo "  Agent rule triggered: pci_11_5_critical_binaries_chown"
    sleep $SLEEP_INTERVAL
    
    # Restore ownership
    chown "${ORIGINAL_OWNER}" "${TEST_PATH}"
}

# Test 3: link - Create symbolic link
test_link() {
    echo ""
    echo -e "${YELLOW}[Test ${TEST_NB}/${TEST_COUNT}] Testing link operation...${NC}"
    LINK_PATH="/tmp/${TEST_BINARY_NAME}_link"
    echo "  Creating symbolic link: ${LINK_PATH} -> ${TEST_PATH}"
    ln -s "${TEST_PATH}" "${LINK_PATH}"
    TEST_NB=$((TEST_NB + 1))
    echo -e "${GREEN}✓ link operation completed${NC}"
    echo "  Agent rule triggered: pci_11_5_critical_binaries_link"
    sleep $SLEEP_INTERVAL
    
    # Remove link
    rm -f "${LINK_PATH}"
}

# Test 4: rename - Rename file
test_rename() {
    echo ""
    echo -e "${YELLOW}[Test ${TEST_NB}/${TEST_COUNT}] Testing rename operation...${NC}"
    RENAME_PATH="${TEST_PATH}_renamed"
    echo "  Renaming: ${TEST_PATH} -> ${RENAME_PATH}"
    mv "${TEST_PATH}" "${RENAME_PATH}"
    TEST_NB=$((TEST_NB + 1))
    echo -e "${GREEN}✓ rename operation completed${NC}"
    echo "  Agent rule triggered: pci_11_5_critical_binaries_rename"
    sleep $SLEEP_INTERVAL
    
    # Restore name
    mv "${RENAME_PATH}" "${TEST_PATH}"
}

# Test 5: open - Modify file contents
test_open() {
    echo ""
    echo -e "${YELLOW}[Test ${TEST_NB}/${TEST_COUNT}] Testing open/modify operation...${NC}"
    echo "  Modifying file contents"
    echo "# Modified content" >> "${TEST_PATH}"
    TEST_NB=$((TEST_NB + 1))
    echo -e "${GREEN}✓ open/modify operation completed${NC}"
    echo "  Agent rule triggered: pci_11_5_critical_binaries_open"
    sleep $SLEEP_INTERVAL
}

# Test 6: unlink - Delete file
test_unlink() {
    echo ""
    echo -e "${YELLOW}[Test ${TEST_NB}/${TEST_COUNT}] Testing unlink operation...${NC}"
    echo "  Deleting file: ${TEST_PATH}"
    rm -f "${TEST_PATH}"
    TEST_NB=$((TEST_NB + 1))
    echo -e "${GREEN}✓ unlink operation completed${NC}"
    echo "  Agent rule triggered: pci_11_5_critical_binaries_unlink"
    sleep $SLEEP_INTERVAL
    
    # Recreate for next test
    if [ "$OPERATION" = "all" ]; then
        create_test_binary
    fi
}

# Test 7: utimes - Change file timestamps
test_utimes() {
    echo ""
    echo -e "${YELLOW}[Test ${TEST_NB}/${TEST_COUNT}] Testing utimes operation...${NC}"
    echo "  Changing file timestamps"
    touch -t 202301010000 "${TEST_PATH}"
    TEST_NB=$((TEST_NB + 1))
    echo -e "${GREEN}✓ utimes operation completed${NC}"
    echo "  Agent rule triggered: pci_11_5_critical_binaries_utimes"
    sleep $SLEEP_INTERVAL
}

test_download() {
    echo ""
    echo -e "${YELLOW}[Test ${TEST_NB}/${TEST_COUNT}] Testing download operation...${NC}"
    echo "  Downloading kubectl utility to ${TEST_PATH}"
    curl -o "${TEST_PATH}" -L https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl2>/dev/null || echo "#!/bin/bash\necho 'Downloaded test binary'" > "${TEST_PATH}"
    chmod 755 "${TEST_PATH}"
    TEST_NB=$((TEST_NB + 1))
    echo -e "${GREEN}✓ download operation completed${NC}"
    echo "  Agent rule triggered: pci_11_5_critical_binaries_open"
    sleep $SLEEP_INTERVAL
}

# Main execution
echo "Operation mode: ${OPERATION}"
echo ""

# Create initial test binary
create_test_binary

# Execute tests based on operation mode
case $OPERATION in
    all)
        TEST_COUNT=7
        test_chmod
        test_chown
        test_link
        test_rename
        test_open
        test_unlink
        test_utimes
        ;;
    chmod)
        test_chmod
        ;;
    chown)
        test_chown
        ;;
    link)
        test_link
        ;;
    rename)
        test_rename
        ;;
    open)
        test_open
        ;;
    unlink)
        test_unlink
        ;;
    utimes)
        test_utimes
        ;;
    download)
        TEST_COUNT=2
        OPERATION="download utility and make executable"
        test_download
        test_chmod
        ;;
    *)
        echo -e "${RED}ERROR: Unknown operation: ${OPERATION}${NC}"
        echo "Valid operations: all, chmod, chown, link, rename, open, unlink, utimes"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${GREEN}✓ Finding generation complete!${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "Expected findings in Datadog:"
echo "  - Finding: Verify Essential Linux Binary Modified on Container"
echo "  - Resource type: container"
echo "  - Severity: low"
echo "  - Operations triggered: ${OPERATION}"
echo ""
echo "To view findings:"
echo "  1. Navigate to Security > Workload Protection > Findings"
echo "  2. Filter by Finding: 'Verify Essential Linux Binary Modified on Container'"
echo "  3. Check findings for service: ${DD_SERVICE}"
cho ""
echo -e "${YELLOW}Note: It may take a few minutes for findings to appear in Datadog${NC}"

