#!/bin/bash
# cargo.sh - Rust/Cargo build verification plugin
# Usage: source this file, then call verify_cargo_build

verify_cargo_build() {
    if [ ! -f "Cargo.toml" ]; then
        echo "[cargo] No Cargo.toml found, skipping"
        return 0
    fi

    log "${CYAN:-}Running cargo build...${NC:-}"

    local output
    local exit_code=0
    output=$(cargo build --release 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "${GREEN:-}✅ cargo build passed${NC:-}"
        return 0
    fi

    log "${RED:-}❌ cargo build failed${NC:-}"

    # Show errors
    echo "$output" | grep -E "(error|Error|ERROR)" | head -20

    return 1
}

# Run cargo tests
verify_cargo_tests() {
    if [ ! -f "Cargo.toml" ]; then
        return 0
    fi

    log "${CYAN:-}Running cargo test...${NC:-}"

    local output
    local exit_code=0
    output=$(cargo test 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "${GREEN:-}✅ cargo test passed${NC:-}"
        return 0
    fi

    log "${RED:-}❌ cargo test failed${NC:-}"
    echo "$output" | grep -E "(FAILED|error|Error)" | head -20

    return 1
}
