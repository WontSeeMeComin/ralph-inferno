#!/bin/bash
# go.sh - Go build verification plugin
# Usage: source this file, then call verify_go_build

verify_go_build() {
    if [ ! -f "go.mod" ]; then
        echo "[go] No go.mod found, skipping"
        return 0
    fi

    log "${CYAN:-}Running go build...${NC:-}"

    local output
    local exit_code=0
    output=$(go build ./... 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "${GREEN:-}✅ go build passed${NC:-}"
        return 0
    fi

    log "${RED:-}❌ go build failed${NC:-}"

    # Show errors
    echo "$output" | grep -E "(error|Error|ERROR|cannot)" | head -20

    return 1
}

# Run go tests
verify_go_tests() {
    if [ ! -f "go.mod" ]; then
        return 0
    fi

    log "${CYAN:-}Running go test...${NC:-}"

    local output
    local exit_code=0
    output=$(go test ./... 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "${GREEN:-}✅ go test passed${NC:-}"
        return 0
    fi

    log "${RED:-}❌ go test failed${NC:-}"
    echo "$output" | grep -E "(FAIL|error|Error)" | head -20

    return 1
}
