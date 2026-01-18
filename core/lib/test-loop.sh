#!/bin/bash
# test-loop.sh - Plugin-based testing with CR generation
# Source this file: source lib/test-loop.sh

TEST_LOOP_LOADED=true

# Track CR depth to prevent infinite loops
CR_DEPTH=${CR_DEPTH:-0}
MAX_CR_DEPTH=1  # Only allow 1 level of CR (no CR-of-CR)

# Get RALPH_DIR for plugin paths
_TEST_LOOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_DIR="${RALPH_DIR:-$(dirname "$_TEST_LOOP_DIR")}"

# Check if we're in a CR context
is_cr_spec() {
    local spec_name="$1"
    [[ "$spec_name" == CR-fix-* ]] || [[ "$spec_name" == CR-design-* ]]
}

# =============================================================================
# PLUGIN-BASED TEST RUNNER
# =============================================================================

# Get configured test plugin from .ralph/config.json
get_test_plugin() {
    local config_file=".ralph/config.json"
    if [ -f "$config_file" ]; then
        jq -r '.plugins.test // "auto"' "$config_file" 2>/dev/null || echo "auto"
    else
        echo "auto"
    fi
}

# Auto-detect test framework from project files
auto_detect_test_framework() {
    # Playwright
    if [ -f "playwright.config.ts" ] || [ -f "playwright.config.js" ]; then
        echo "playwright"
        return
    fi

    # Jest/Vitest
    if [ -f "jest.config.js" ] || [ -f "jest.config.ts" ] || [ -f "vitest.config.js" ] || [ -f "vitest.config.ts" ]; then
        echo "jest"
        return
    fi

    # Check package.json for test frameworks
    if [ -f "package.json" ]; then
        if grep -q '"playwright"' package.json 2>/dev/null; then
            echo "playwright"
            return
        fi
        if grep -q '"jest"\|"vitest"' package.json 2>/dev/null; then
            echo "jest"
            return
        fi
    fi

    # Python pytest
    if [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
        if [ -f "pyproject.toml" ] && grep -q "pytest" pyproject.toml 2>/dev/null; then
            echo "pytest"
            return
        fi
        if [ -f "pytest.ini" ]; then
            echo "pytest"
            return
        fi
    fi

    # No framework detected
    echo "none"
}

# Run tests using the configured plugin
run_tests() {
    local test_plugin=$(get_test_plugin)

    case "$test_plugin" in
        none)
            log "${YELLOW}Tests disabled via config${NC}"
            return 0
            ;;
        playwright)
            source "$RALPH_DIR/plugins/test/playwright.sh"
            run_playwright
            ;;
        jest)
            source "$RALPH_DIR/plugins/test/jest.sh"
            run_jest
            ;;
        pytest)
            source "$RALPH_DIR/plugins/test/pytest.sh"
            run_pytest
            ;;
        auto|*)
            auto_detect_and_run_tests
            ;;
    esac
}

# Auto-detect and run appropriate test framework
auto_detect_and_run_tests() {
    local detected=$(auto_detect_test_framework)

    case "$detected" in
        playwright)
            source "$RALPH_DIR/plugins/test/playwright.sh"
            run_playwright
            ;;
        jest)
            source "$RALPH_DIR/plugins/test/jest.sh"
            run_jest
            ;;
        pytest)
            source "$RALPH_DIR/plugins/test/pytest.sh"
            run_pytest
            ;;
        none|*)
            log "${YELLOW}No test framework detected, skipping tests${NC}"
            return 0
            ;;
    esac
}

# Legacy alias for backwards compatibility
run_e2e_tests() {
    run_tests
}

# =============================================================================
# CR GENERATION
# =============================================================================

# Generate CR spec from test failure
generate_cr() {
    local spec_name="$1"

    # Prevent CR-of-CR (infinite loop protection)
    if is_cr_spec "$spec_name"; then
        log "${RED}⚠️ CR failed - not generating CR-of-CR${NC}"
        log "${RED}Manual intervention needed${NC}"
        return 1
    fi

    local test_output=$(cat .test-output.log 2>/dev/null)
    local cr_file="specs/CR-fix-${spec_name}.md"

    log "${YELLOW}Generating CR: $cr_file${NC}"

    # Use LLM provider to generate CR markdown, then write it ourselves.
    # (This allows local inference providers that don't have file-system tools.)
    local prompt="Tests failed after running spec: $spec_name

Test output:
$test_output

Create a Change Request spec to fix this.

IMPORTANT:
- Output ONLY the Markdown content for the CR file (no commentary)
- Keep it concise but actionable

Use this format:
# CR: Fix test failure from $spec_name

**Problem:** <what failed>
**Root cause:** <why it likely failed>

## Fix
- <specific code changes needed>

## Done when
- [ ] Tests pass
- [ ] Build succeeds"

    llm_generate_to_file "$prompt" "$cr_file" "generate_cr" "execute" >/dev/null 2>&1 || true

    if [ -f "$cr_file" ]; then
        log "${GREEN}CR created: $cr_file${NC}"
        return 0
    fi

    log "${RED}Failed to create CR${NC}"
    return 1
}

# =============================================================================
# SCREENSHOTS (Plugin-based)
# =============================================================================

# Get the configured screenshot tool
get_screenshot_tool() {
    local config_file=".ralph/config.json"
    if [ -f "$config_file" ]; then
        jq -r '.plugins.screenshot // "auto"' "$config_file" 2>/dev/null || echo "auto"
    else
        echo "auto"
    fi
}

# Get the configured dev server URL from PRD or config
get_dev_server_url() {
    local config_file=".ralph/config.json"
    local prd_file=""

    # Try config first
    if [ -f "$config_file" ]; then
        local url=$(jq -r '.dev_server_url // ""' "$config_file" 2>/dev/null)
        if [ -n "$url" ] && [ "$url" != "null" ]; then
            echo "$url"
            return
        fi
    fi

    # Try to detect from PRD
    if [ -f "docs/PRD.md" ]; then
        prd_file="docs/PRD.md"
    elif [ -f "docs/prd.md" ]; then
        prd_file="docs/prd.md"
    fi

    if [ -n "$prd_file" ]; then
        local url=$(grep -E "dev.*url|localhost" "$prd_file" 2>/dev/null | grep -oE "http://[^ ]+" | head -1)
        if [ -n "$url" ]; then
            echo "$url"
            return
        fi
    fi

    # Default fallback (common dev server ports)
    if [ -f "package.json" ]; then
        # Try to detect from package.json scripts
        if grep -q "vite" package.json 2>/dev/null; then
            echo "http://localhost:5173"
            return
        fi
        if grep -q "next" package.json 2>/dev/null; then
            echo "http://localhost:3000"
            return
        fi
    fi

    # Generic fallback
    echo "http://localhost:3000"
}

# Take screenshots of the app
take_screenshots() {
    local output_dir="${1:-.screenshots}"
    mkdir -p "$output_dir"

    local screenshot_tool=$(get_screenshot_tool)

    case "$screenshot_tool" in
        none)
            log "${YELLOW}Screenshots disabled via config${NC}"
            return 0
            ;;
        playwright)
            if [ -f "$RALPH_DIR/plugins/test/playwright.sh" ]; then
                source "$RALPH_DIR/plugins/test/playwright.sh"
                take_playwright_screenshots "$output_dir" "$(get_dev_server_url)"
            fi
            ;;
        auto|*)
            # Auto-detect: use playwright if available
            if [ -f "playwright.config.ts" ] || [ -f "playwright.config.js" ]; then
                if [ -f "$RALPH_DIR/plugins/test/playwright.sh" ]; then
                    source "$RALPH_DIR/plugins/test/playwright.sh"
                    take_playwright_screenshots "$output_dir" "$(get_dev_server_url)"
                fi
            else
                log "${YELLOW}No screenshot tool available${NC}"
                return 0
            fi
            ;;
    esac
}

# =============================================================================
# DESIGN REVIEW (Optional)
# =============================================================================

# Run design review (requires vision-capable LLM)
run_design_review() {
    local spec_name="$1"
    local screenshot_dir=".screenshots"

    # Skip if no screenshots
    if [ ! -d "$screenshot_dir" ] || [ -z "$(ls -A $screenshot_dir 2>/dev/null)" ]; then
        log "${YELLOW}No screenshots for design review${NC}"
        return 0
    fi

    # Skip if no PRD with design system
    local prd_file=""
    if [ -f "docs/PRD.md" ]; then
        prd_file="docs/PRD.md"
    elif [ -f "docs/prd.md" ]; then
        prd_file="docs/prd.md"
    else
        return 0
    fi

    # Check if PRD has design system section
    if ! grep -q "## Design System" "$prd_file" 2>/dev/null; then
        return 0
    fi

    log "${CYAN}Running design review...${NC}"

    # Extract design system from PRD
    local design_system=$(sed -n '/## Design System/,/^## /p' "$prd_file" | head -50)

    # Build prompt for vision LLM
    local prompt="Review this screenshot against the design system.

DESIGN SYSTEM:
$design_system

Check:
1. Are colors correct? (primary, accent, background)
2. Is spacing consistent? (following the scale)
3. Is typography correct? (font, sizes)
4. Overall polish - would this pass a design review?

If there are issues, list them specifically.
If it looks good, say 'DESIGN_OK'.

Be concise - max 10 lines."

    # Pick first screenshot
    local screenshot=$(ls -1 "$screenshot_dir"/*.png 2>/dev/null | head -1)
    if [ -z "$screenshot" ]; then
        return 0
    fi

    local result
    if result=$(llm_generate_vision "$prompt" "$screenshot" "design_review" 2>/dev/null); then
        :
    else
        # Fallback: text-only review (no image support)
	    result=$(llm_generate "$prompt

NOTE: Vision not available. Provide a best-effort design/accessibility review based on the design system alone. If no issues, say 'DESIGN_OK'." "design_review_text" "vision" 2>/dev/null || true)
    fi

    if echo "$result" | grep -q "DESIGN_OK"; then
        log "${GREEN}✅ Design review passed${NC}"
        return 0
    fi

    log "${YELLOW}⚠️ Design issues found${NC}"
    echo "$result" | head -10

    # Save for potential CR
    echo "$result" > .design-review.log
    return 1
}

# Generate design CR from review
generate_design_cr() {
    local spec_name="$1"
    local review_output=$(cat .design-review.log 2>/dev/null)

    if [ -z "$review_output" ]; then
        return 1
    fi

    # Prevent CR-of-CR
    if is_cr_spec "$spec_name"; then
        log "${RED}⚠️ Design CR failed - not generating CR-of-CR${NC}"
        return 1
    fi

    local cr_file="specs/CR-design-${spec_name}.md"
    log "${YELLOW}Generating design CR: $cr_file${NC}"

    local prompt="Design review found issues after spec: $spec_name

Review feedback:
$review_output

Create a Change Request spec to fix the design issues.

IMPORTANT:
- Output ONLY the Markdown content for the CR file (no commentary)

Format:
# CR: Fix design issues from $spec_name

**Issues found:**
- <issue 1>
- <issue 2>

## Fix
- <specific CSS/component changes>

## Done when
- [ ] Design review passes
- [ ] Build succeeds"

    llm_generate_to_file "$prompt" "$cr_file" "generate_design_cr" "execute" >/dev/null 2>&1 || true

    if [ -f "$cr_file" ]; then
        log "${GREEN}Design CR created: $cr_file${NC}"
        return 0
    fi

    return 1
}
