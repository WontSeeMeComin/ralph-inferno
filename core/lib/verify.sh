#!/bin/bash
# verify.sh - Plugin-based build verification with self-healing
# Source this file: source lib/verify.sh

# Also source selfheal if not already loaded
_VERIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_DIR="${RALPH_DIR:-$(dirname "$_VERIFY_DIR")}"
[ -z "${SELFHEAL_LOADED:-}" ] && source "$_VERIFY_DIR/selfheal.sh"

# =============================================================================
# PLUGIN-BASED BUILD VERIFICATION
# =============================================================================

# Get configured verify plugin from .ralph/config.json
get_verify_plugin() {
    local config_file=".ralph/config.json"
    if [ -f "$config_file" ]; then
        jq -r '.plugins.verify // "auto"' "$config_file" 2>/dev/null || echo "auto"
    else
        echo "auto"
    fi
}

# Auto-detect build system from project files
auto_detect_build_system() {
    # Node.js/npm
    if [ -f "package.json" ]; then
        echo "npm"
        return
    fi

    # Rust/Cargo
    if [ -f "Cargo.toml" ]; then
        echo "cargo"
        return
    fi

    # Go
    if [ -f "go.mod" ]; then
        echo "go"
        return
    fi

    # Make
    if [ -f "Makefile" ] || [ -f "makefile" ]; then
        echo "make"
        return
    fi

    # No build system detected
    echo "none"
}

# Verify build using the configured plugin
verify_build() {
    local max_attempts=${1:-3}
    local attempt=0
    local verify_plugin=$(get_verify_plugin)

    # Ensure dependencies first (generic)
    ensure_deps || true

    while [ $attempt -lt $max_attempts ]; do
        ((attempt++))

        local exit_code=0

        case "$verify_plugin" in
            none)
                log "${YELLOW:-}Build verification disabled via config${NC:-}"
                return 0
                ;;
            npm)
                source "$RALPH_DIR/plugins/verify/npm.sh"
                verify_npm_build || exit_code=$?
                ;;
            cargo)
                source "$RALPH_DIR/plugins/verify/cargo.sh"
                verify_cargo_build || exit_code=$?
                ;;
            go)
                source "$RALPH_DIR/plugins/verify/go.sh"
                verify_go_build || exit_code=$?
                ;;
            make)
                source "$RALPH_DIR/plugins/verify/make.sh"
                verify_make_build || exit_code=$?
                ;;
            auto|*)
                auto_detect_and_verify || exit_code=$?
                ;;
        esac

        if [ $exit_code -eq 0 ]; then
            return 0
        fi

        # Try self-heal if we have error output
        if [ -f ".build-output.log" ]; then
            local output=$(cat .build-output.log 2>/dev/null)
            if try_selfheal "$output"; then
                continue
            fi
        fi

        # No self-heal possible, fail
        return 1
    done

    return 1
}

# Auto-detect and verify with appropriate build system
auto_detect_and_verify() {
    local detected=$(auto_detect_build_system)

    case "$detected" in
        npm)
            source "$RALPH_DIR/plugins/verify/npm.sh"
            verify_npm_build
            ;;
        cargo)
            source "$RALPH_DIR/plugins/verify/cargo.sh"
            verify_cargo_build
            ;;
        go)
            source "$RALPH_DIR/plugins/verify/go.sh"
            verify_go_build
            ;;
        make)
            source "$RALPH_DIR/plugins/verify/make.sh"
            verify_make_build
            ;;
        none|*)
            log "${YELLOW:-}No build system detected, skipping build verification${NC:-}"
            return 0
            ;;
    esac
}

# =============================================================================
# TEST VERIFICATION (Uses test-loop.sh)
# =============================================================================

# Verify tests pass (delegates to test-loop.sh if loaded)
verify_tests() {
    # Check if test-loop is loaded
    if [ -n "${TEST_LOOP_LOADED:-}" ]; then
        run_tests
        return $?
    fi

    # Fallback: basic test detection
    local verify_plugin=$(get_verify_plugin)

    case "$verify_plugin" in
        npm)
            if [ -f "package.json" ] && grep -q '"test"' package.json 2>/dev/null; then
                local output
                output=$(npm test 2>&1) || {
                    echo "$output" | grep -E "(FAIL|failed|Failed|✗|❌|Error)" | head -30
                    return 1
                }
            fi
            ;;
        cargo)
            if [ -f "Cargo.toml" ]; then
                cargo test 2>&1 || return 1
            fi
            ;;
        go)
            if [ -f "go.mod" ]; then
                go test ./... 2>&1 || return 1
            fi
            ;;
        make)
            if [ -f "Makefile" ] || [ -f "makefile" ]; then
                if grep -qE "^test:" Makefile makefile 2>/dev/null; then
                    make test 2>&1 || return 1
                fi
            fi
            ;;
    esac

    return 0
}

# Full verification (build + tests)
verify_all() {
    verify_build || return 1
    verify_tests || return 1
    return 0
}

# =============================================================================
# DEPENDENCY MANAGEMENT
# =============================================================================

# Ensure dependencies are installed (generic)
ensure_deps() {
    local detected=$(auto_detect_build_system)

    case "$detected" in
        npm)
            if [ -f "package.json" ] && [ ! -d "node_modules" ]; then
                echo "[verify] Installing npm dependencies..."
                npm install 2>&1
            fi
            ;;
        cargo)
            # Cargo fetches dependencies automatically during build
            ;;
        go)
            if [ -f "go.mod" ]; then
                echo "[verify] Downloading go modules..."
                go mod download 2>&1 || true
            fi
            ;;
        make)
            # Make has no standard dependency management
            ;;
    esac
}
