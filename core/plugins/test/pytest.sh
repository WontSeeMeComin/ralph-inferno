#!/bin/bash
# pytest.sh - pytest test runner plugin
# Usage: source this file, then call run_pytest

run_pytest() {
    # Check for pytest indicators
    local has_pytest=false

    if [ -f "pytest.ini" ]; then
        has_pytest=true
    elif [ -f "pyproject.toml" ] && grep -q "pytest" pyproject.toml 2>/dev/null; then
        has_pytest=true
    elif [ -f "setup.cfg" ] && grep -q "pytest" setup.cfg 2>/dev/null; then
        has_pytest=true
    elif [ -d "tests" ] && ls tests/*.py 2>/dev/null | head -1 | grep -q .; then
        has_pytest=true
    fi

    if [ "$has_pytest" = false ]; then
        echo "[pytest] No pytest config found, skipping"
        return 0
    fi

    log "${CYAN:-}Running pytest...${NC:-}"

    local output
    local exit_code=0
    output=$(pytest -v 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "${GREEN:-}✅ pytest passed${NC:-}"
        return 0
    fi

    log "${RED:-}❌ pytest failed${NC:-}"
    echo "$output" > .test-output.log

    # Show summary of failures
    echo "$output" | grep -E "(FAILED|ERROR|failed|error)" | head -10

    return 1
}
