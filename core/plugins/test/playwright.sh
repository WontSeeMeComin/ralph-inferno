#!/bin/bash
# playwright.sh - Playwright test runner plugin
# Usage: source this file, then call run_playwright

run_playwright() {
    local reporter="${1:-line}"

    # Check for playwright config
    if [ ! -f "playwright.config.ts" ] && [ ! -f "playwright.config.js" ]; then
        echo "[playwright] No playwright.config found, skipping"
        return 0
    fi

    log "${CYAN:-}Running Playwright E2E tests...${NC:-}"

    local output
    local exit_code=0
    output=$(npx playwright test --reporter="$reporter" 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "${GREEN:-}✅ Playwright tests passed${NC:-}"
        return 0
    fi

    log "${RED:-}❌ Playwright tests failed${NC:-}"
    echo "$output" > .test-output.log

    # Show summary of failures
    echo "$output" | grep -E "(✘|Error|FAIL|failed)" | head -10

    return 1
}

# Take screenshots using Playwright
take_playwright_screenshots() {
    local output_dir="${1:-.screenshots}"
    local url="${2:-http://localhost:5173}"

    mkdir -p "$output_dir"

    log "${CYAN:-}Taking screenshots with Playwright...${NC:-}"

    node -e "
const { chromium } = require('@playwright/test');
(async () => {
    const browser = await chromium.launch();
    const page = await browser.newPage();
    await page.goto('$url');
    await page.screenshot({ path: '$output_dir/home.png', fullPage: true });
    await browser.close();
})();
" 2>/dev/null || true

    local count=$(ls -1 "$output_dir"/*.png 2>/dev/null | wc -l | tr -d ' ')
    log "Captured $count screenshot(s)"
}
