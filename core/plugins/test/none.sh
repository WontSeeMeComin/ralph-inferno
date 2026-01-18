#!/bin/bash
# none.sh - No-op test plugin (skip all tests)
# Usage: source this file, then call run_no_tests

run_no_tests() {
    log "${YELLOW:-}Tests disabled via config, skipping${NC:-}"
    return 0
}
