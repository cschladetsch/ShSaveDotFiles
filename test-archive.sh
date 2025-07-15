#!/bin/bash

# test-archive.sh - Test suite for archive-dot-files.sh

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Testing archive-dot-files.sh ===${NC}\n"

# Setup
TEST_DIR="$(pwd)/test-output"
TEST_HOME="$TEST_DIR/test-home"
ORIGINAL_HOME="$HOME"

# Clean and create test environment
rm -rf "$TEST_DIR"
mkdir -p "$TEST_HOME"/{.ssh,bin,doc}
echo "test bashrc" > "$TEST_HOME/.bashrc"
echo "test script" > "$TEST_HOME/bin/test.sh"
echo "test doc" > "$TEST_HOME/doc/test.txt"
chmod 700 "$TEST_HOME/.ssh"

# Change HOME for tests
export HOME="$TEST_HOME"

# Test 1: Basic backup
echo -n "Test 1 - Basic backup: "
if ./archive-dot-files.sh test-basic >/dev/null 2>&1 && [[ -f "$TEST_HOME/test-basic.tar.gz" ]]; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

# Test 2: Compression types
echo -n "Test 2 - Bzip2 compression: "
if ./archive-dot-files.sh test-bz2 --compression=bzip2 >/dev/null 2>&1 && [[ -f "$TEST_HOME/test-bz2.tar.bz2" ]]; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

echo -n "Test 3 - XZ compression: "
if ./archive-dot-files.sh test-xz --compression=xz >/dev/null 2>&1 && [[ -f "$TEST_HOME/test-xz.tar.xz" ]]; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

# Test 3: File inclusion
echo -n "Test 4 - File inclusion: "
if tar -tzf "$TEST_HOME/test-basic.tar.gz" 2>/dev/null | grep -q "bin/test.sh" && \
   tar -tzf "$TEST_HOME/test-basic.tar.gz" 2>/dev/null | grep -q "doc/test.txt"; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

# Test 4: Compression levels
echo -n "Test 5 - Compression levels: "
./archive-dot-files.sh test-fast --level=1 >/dev/null 2>&1
./archive-dot-files.sh test-best --level=9 >/dev/null 2>&1
SIZE1=$(stat -c%s "$TEST_HOME/test-fast.tar.gz" 2>/dev/null || stat -f%z "$TEST_HOME/test-fast.tar.gz")
SIZE9=$(stat -c%s "$TEST_HOME/test-best.tar.gz" 2>/dev/null || stat -f%z "$TEST_HOME/test-best.tar.gz")
if [[ $SIZE1 -ge $SIZE9 ]]; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

# Test 5: Invalid compression
echo -n "Test 6 - Invalid compression handling: "
if ! ./archive-dot-files.sh test-invalid --compression=invalid >/dev/null 2>&1; then
    echo -e "${GREEN}PASSED${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

# Restore HOME
export HOME="$ORIGINAL_HOME"

# Summary
echo -e "\n${BLUE}Created archives:${NC}"
ls -lh "$TEST_HOME"/*.tar.* 2>/dev/null | awk '{printf "  %s (%s)\n", $9, $5}'

# Cleanup
echo -e "\n${BLUE}Cleaning up...${NC}"
rm -rf "$TEST_DIR"
echo -e "${GREEN}Done!${NC}"