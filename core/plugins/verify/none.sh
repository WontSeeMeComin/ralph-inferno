#!/bin/bash
# none.sh - No-op verify plugin (skip build verification)
# Usage: source this file, then call verify_none

verify_none() {
    log "${YELLOW:-}Build verification disabled via config, skipping${NC:-}"
    return 0
}
