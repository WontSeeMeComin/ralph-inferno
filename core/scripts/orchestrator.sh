#!/bin/bash
# =============================================================================
# orchestrator.sh - Middle Loop Orchestrator
#
# Run the full spec cycle with automatic self-healing:
# specs → build → E2E test → CR on error → retry
#
# Usage:
# ./orchestrator.sh # Run all specs with test loop
# ./orchestrator.sh --max=5 # Max 5 iterations
#
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/notify.sh"

# Config
MAX_ITERATIONS=${MAX_ITERATIONS:-3}
ITERATION=0

# Parse args
for arg in "$@"; do
    case $arg in
        --max=*)
            MAX_ITERATIONS="${arg#*=}"
            shift
            ;;
    esac
done

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "[$(date +%H:%M:%S)] $1"; }

# Check if all specs are done
all_specs_done() {
    local total=$(ls -1 specs/*.md 2>/dev/null | grep -v "^specs/CR-" | wc -l | tr -d ' ')
    local done=$(ls -1 .spec-checksums/*.md5 2>/dev/null | wc -l | tr -d ' ')
    [ "$done" -ge "$total" ] && [ "$total" -gt 0 ]
}

# Check for failed specs (not done after ralph.sh run)
has_failures() {
    local incomplete=$(ls -1 specs/*.md 2>/dev/null | while read spec; do
        local name=$(basename "$spec" .md)
        [ ! -f ".spec-checksums/${name}.md5" ] && echo "$spec"
    done | grep -v "^specs/CR-" | wc -l | tr -d ' ')
    [ "$incomplete" -gt 0 ]
}

# Start services if needed (Supabase, dev server)
start_services() {
    # Check if Supabase project
    if [ -f "supabase/config.toml" ]; then
        log "${CYAN}Starting Supabase...${NC}"
        supabase start 2>/dev/null || true
    fi
}

# Main orchestration loop
main() {
    log "${CYAN}╔════════════════════════════════════════╗${NC}"
    log "${CYAN}║ RALPH ORCHESTRATOR STARTING ║${NC}"
    log "${CYAN}╚════════════════════════════════════════╝${NC}"

    # Verify specs exist before starting
    local total_specs=$(ls -1 specs/*.md 2>/dev/null | grep -v "^specs/CR-" | wc -l | tr -d ' ')
    if [ "$total_specs" -eq 0 ]; then
        log "${RED}No specs found in specs/*.md${NC}"
        notify "❌ Orchestrator: No specs found"
        return 1
    fi

    notify "🎬 Orchestrator starting (max $MAX_ITERATIONS iterations)"

    start_services

    while [ $ITERATION -lt $MAX_ITERATIONS ]; do
        ((ITERATION++))
        log ""
        log "${YELLOW}━━━ ITERATION $ITERATION/$MAX_ITERATIONS ━━━${NC}"

        # Run ralph (includes test-loop with E2E + CR)
        "$SCRIPT_DIR/ralph.sh"
        local exit_code=$?

        # Check if done
        if all_specs_done; then
            log ""
            log "${GREEN}╔════════════════════════════════════════╗${NC}"
            log "${GREEN}║ ✅ ALL SPECS COMPLETE ║${NC}"
            log "${GREEN}╚════════════════════════════════════════╝${NC}"
            notify "✅ Orchestrator complete! All specs done in $ITERATION iteration(s)"
            return 0
        fi

        # Check if we made progress or are stuck
        if [ $exit_code -ne 0 ] && ! has_failures; then
            log "${RED}Ralph exited with error but no failures detected${NC}"
        fi

        log "${YELLOW}Some specs incomplete, retrying...${NC}"
        sleep 5
    done

    # Max iterations reached
    log ""
    log "${RED}╔════════════════════════════════════════╗${NC}"
    log "${RED}║ ⚠️ MAX ITERATIONS REACHED ║${NC}"
    log "${RED}╚════════════════════════════════════════╝${NC}"

    # Show what's still incomplete
    log ""
    log "Incomplete specs:"
    ls -1 specs/*.md 2>/dev/null | while read spec; do
        local name=$(basename "$spec" .md)
        [ ! -f ".spec-checksums/${name}.md5" ] && echo " ❌ $name"
    done | grep -v "CR-"

    notify "⚠️ Orchestrator stopped after $MAX_ITERATIONS iterations. Manual intervention needed."
    return 1
}

main "$@"
