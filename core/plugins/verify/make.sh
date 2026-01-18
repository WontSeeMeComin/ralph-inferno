#!/bin/bash
# make.sh - Make build verification plugin
# Usage: source this file, then call verify_make_build

verify_make_build() {
    if [ ! -f "Makefile" ] && [ ! -f "makefile" ]; then
        echo "[make] No Makefile found, skipping"
        return 0
    fi

    log "${CYAN:-}Running make...${NC:-}"

    local output
    local exit_code=0
    output=$(make 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "${GREEN:-}✅ make passed${NC:-}"
        return 0
    fi

    log "${RED:-}❌ make failed${NC:-}"

    # Show errors
    echo "$output" | grep -E "(error|Error|ERROR)" | head -20

    return 1
}

# Run make test if available
verify_make_tests() {
    if [ ! -f "Makefile" ] && [ ! -f "makefile" ]; then
        return 0
    fi

    # Check if test target exists
    if ! grep -qE "^test:" Makefile makefile 2>/dev/null; then
        return 0
    fi

    log "${CYAN:-}Running make test...${NC:-}"

    local output
    local exit_code=0
    output=$(make test 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "${GREEN:-}✅ make test passed${NC:-}"
        return 0
    fi

    log "${RED:-}❌ make test failed${NC:-}"
    echo "$output" | grep -E "(FAIL|error|Error)" | head -20

    return 1
}
