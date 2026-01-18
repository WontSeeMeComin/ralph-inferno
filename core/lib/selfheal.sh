#!/bin/bash
# selfheal.sh - Auto-fix common build issues
# Source this file: source lib/selfheal.sh

SELFHEAL_LOADED=1

# =============================================================================
# KNOWN PATTERNS AND FIXES
# Format: pattern|fix_command|description
# =============================================================================

SELFHEAL_PATTERNS=(
    # Node.js / npm - core
    "tsc: not found|npm install -g typescript|TypeScript compiler"
    "npx: not found|npm install -g npx|npx command"
    "Cannot find module|npm install|Missing npm package"
    "ENOENT.*node_modules|npm install|Missing node_modules"
    "MODULE_NOT_FOUND|npm install|Missing module"
    "ERR_MODULE_NOT_FOUND|npm install|Missing ES module"
    "peer dep missing|npm install|Missing peer dependency"

    # Node.js / npm - common tools (only heal if project needs them)
    "vite: not found|npm install vite|Vite bundler"
    "vitest: not found|npm install vitest|Vitest test runner"
    "playwright: not found|npx playwright install|Playwright browsers"
    "jest: not found|npm install jest|Jest test runner"

    # Python
    "ModuleNotFoundError|pip install -r requirements.txt|Missing Python module"
    "No module named|pip install -r requirements.txt|Missing Python module"
    "pytest: not found|pip install pytest|pytest"

    # Rust / Cargo
    "error\\[E0433\\]|cargo build|Unresolved import"
    "could not find.*in.*dependencies|cargo build|Missing Cargo dependency"

    # Go
    "cannot find package|go mod download|Missing Go package"
    "missing go.sum entry|go mod tidy|Missing go.sum entry"
)

# =============================================================================
# SELFHEAL FUNCTIONS
# =============================================================================

# Try to self-heal based on error output
try_selfheal() {
    local error_output="$1"
    local healed=false

    for pattern_entry in "${SELFHEAL_PATTERNS[@]}"; do
        local pattern=$(echo "$pattern_entry" | cut -d'|' -f1)
        local fix_cmd=$(echo "$pattern_entry" | cut -d'|' -f2)
        local description=$(echo "$pattern_entry" | cut -d'|' -f3)

        if echo "$error_output" | grep -qiE "$pattern"; then
            echo "[selfheal] Detected: $description"
            echo "[selfheal] Running: $fix_cmd"

            if eval "$fix_cmd" 2>&1; then
                echo "[selfheal] Fixed: $description"
                healed=true
            else
                echo "[selfheal] Failed to fix: $description"
            fi
        fi
    done

    [ "$healed" = true ]
}

# Ensure dependencies exist (generic, delegates to verify.sh)
ensure_deps() {
    # Node.js
    if [ -f "package.json" ] && [ ! -d "node_modules" ]; then
        echo "[selfheal] Installing npm dependencies..."
        npm install 2>&1
        return
    fi

    # Python
    if [ -f "requirements.txt" ] && [ ! -d ".venv" ] && [ ! -d "venv" ]; then
        echo "[selfheal] Installing Python dependencies..."
        pip install -r requirements.txt 2>&1
        return
    fi

    # Go
    if [ -f "go.mod" ]; then
        echo "[selfheal] Downloading Go modules..."
        go mod download 2>&1
        return
    fi
}

# =============================================================================
# EXTENSIBILITY - Load custom selfheal patterns
# =============================================================================

# Load additional patterns from project-specific file
load_custom_patterns() {
    local custom_file=".ralph/selfheal-patterns.sh"
    if [ -f "$custom_file" ]; then
        echo "[selfheal] Loading custom patterns from $custom_file"
        source "$custom_file"
    fi
}

# Call on load
load_custom_patterns 2>/dev/null || true
