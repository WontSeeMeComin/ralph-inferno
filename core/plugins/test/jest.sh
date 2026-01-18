#!/bin/bash
# jest.sh - Jest/Vitest test runner plugin
# Usage: source this file, then call run_jest

run_jest() {
    # Check for jest/vitest config
    local has_jest=false

    if [ -f "jest.config.js" ] || [ -f "jest.config.ts" ] || [ -f "jest.config.mjs" ]; then
        has_jest=true
    elif [ -f "vitest.config.js" ] || [ -f "vitest.config.ts" ] || [ -f "vitest.config.mjs" ]; then
        has_jest=true
    elif grep -q '"jest"' package.json 2>/dev/null; then
        has_jest=true
    elif grep -q '"vitest"' package.json 2>/dev/null; then
        has_jest=true
    fi

    if [ "$has_jest" = false ]; then
        echo "[jest] No jest/vitest config found, skipping"
        return 0
    fi

    log "${CYAN:-}Running Jest/Vitest tests...${NC:-}"

    local output
    local exit_code=0
    output=$(npm test 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "${GREEN:-}✅ Jest/Vitest tests passed${NC:-}"
        return 0
    fi

    log "${RED:-}❌ Jest/Vitest tests failed${NC:-}"
    echo "$output" > .test-output.log

    # Show summary of failures
    echo "$output" | grep -E "(FAIL|failed|Failed|✗|❌|Error)" | head -10

    return 1
}
