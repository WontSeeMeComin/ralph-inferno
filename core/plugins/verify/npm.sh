#!/bin/bash
# npm.sh - npm/Node.js build verification plugin
# Usage: source this file, then call verify_npm_build

verify_npm_build() {
    if [ ! -f "package.json" ]; then
        echo "[npm] No package.json found, skipping"
        return 0
    fi

    # Check if build script exists
    if ! grep -q '"build"' package.json 2>/dev/null; then
        echo "[npm] No build script in package.json, skipping"
        return 0
    fi

    log "${CYAN:-}Running npm build...${NC:-}"

    local output
    local exit_code=0
    output=$(npm run build 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "${GREEN:-}✅ npm build passed${NC:-}"
        return 0
    fi

    log "${RED:-}❌ npm build failed${NC:-}"

    # Only show errors (saves tokens)
    echo "$output" | grep -E "(error|Error|ERROR|FAIL|failed|Failed|✗|❌)" | head -20

    return 1
}

# Check and install dependencies
ensure_npm_deps() {
    if [ -f "package.json" ] && [ ! -d "node_modules" ]; then
        echo "[npm] Installing dependencies..."
        npm install 2>&1
    fi
}
