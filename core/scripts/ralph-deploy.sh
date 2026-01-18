#!/bin/bash
#
# ralph-handoff.sh - Complete pipeline: Discovery → VM → Ralph
#
# Flow:
# 1. run discovery locally (Claude Code)
# 2. generate PRD + Skills
# 3. push to VM
# 4. start ralph on VM
# 5. monitor progress
# Pull results when done
#
# Usage:
# ./ralph-handoff.sh <project-name> [options]
#
# Options:
# --input <file> Start from meeting transcript
# --skip-discovery Skip discovery, use existing project
# --watch Watch VM progress after handoff
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Args
PROJECT_NAME="${1:-}"
INPUT_FILE=""
SKIP_DISCOVERY=false
WATCH_MODE=false
OVERNIGHT_MODE=false

# ntfy topic for notifications
NTFY_TOPIC="${NTFY_TOPIC:-}"

if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: $0 <project-name> [options]"
    echo ""
    echo "Options:"
    echo " --input <file> Start from meeting transcript"
    echo " --skip-discovery Skip discovery, use existing project"
    echo " --watch Watch VM progress after handoff"
    echo " --overnight Night mode: auto-stop VM, notify when done"
    echo ""
    echo "Examples:"
    echo " $0 my-app # Full pipeline"
    echo " $0 my-app --input meeting.md # From transcript"
    echo " $0 my-app --overnight # Fire and forget"
    exit 1
fi

shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --input)
            shift
            INPUT_FILE="${1:-}"
            ;;
        --skip-discovery)
            SKIP_DISCOVERY=true
            ;;
        --watch)
            WATCH_MODE=true
            ;;
        --overnight)
            OVERNIGHT_MODE=true
            ;;
        *) ;;
    esac
    shift || true
done

# Helper: Send notification
notify() {
    local msg="$1"
    if [ -n "$NTFY_TOPIC" ]; then
        curl -s -d "$msg" "https://ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1 || true
    fi
}

PROJECT_DIR="./$PROJECT_NAME"

# ═══════════════════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${MAGENTA}"
cat << 'EOF'
  ╔═══════════════════════════════════════════════════════════╗
  ║                                                           ║
  ║     ██████╗  █████╗ ██╗     ██████╗ ██╗  ██╗              ║
  ║     ██╔══██╗██╔══██╗██║     ██╔══██╗██║  ██║              ║
  ║     ██████╔╝███████║██║     ██████╔╝███████║              ║
  ║     ██╔══██╗██╔══██║██║     ██╔═══╝ ██╔══██║              ║
  ║     ██║  ██║██║  ██║███████╗██║     ██║  ██║              ║
  ║     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝              ║
  ║                                                           ║
  ║ H A N D O F F P I P E L I N E ║
  ║                                                           ║
  ║ Discovery (local) → VM (cloud) → Ralph ║
  ║                                                           ║
  ╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "Project: ${GREEN}$PROJECT_NAME${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 1: DISCOVERY (local)
# ═══════════════════════════════════════════════════════════════
if [ "$SKIP_DISCOVERY" = false ]; then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN} STEP 1: DISCOVERY (local)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    DISCOVER_ARGS="$PROJECT_NAME"
    if [ -n "$INPUT_FILE" ]; then
        DISCOVER_ARGS="$DISCOVER_ARGS --input $INPUT_FILE"
    fi

    "$SCRIPT_DIR/ralph-discover.sh" $DISCOVER_ARGS

    echo ""
    echo -e "${GREEN}✓ Discovery ready${NC}"
fi

# Verify project exists
if [ ! -d "$PROJECT_DIR" ]; then
    echo -e "${RED}Project missing: $PROJECT_DIR${NC}"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# STEP 2: VALIDATE PROJECT
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN} STEP 2: VALIDATE PROJECT${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check required files
REQUIRED_FILES=(
    "CLAUDE.md"
    "docs/prd.md"
)

MISSING=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$PROJECT_DIR/$file" ]; then
        echo -e " ${GREEN}✓${NC} $file"
    else
        echo -e " ${RED}✗${NC} $file (missing)"
        MISSING=$((MISSING + 1))
    fi
done

# Count specs
SPEC_COUNT=$(ls -1 "$PROJECT_DIR/specs"/*.md 2>/dev/null | wc -l | tr -d ' ')
echo -e " ${BLUE}○${NC} Specs: $SPEC_COUNT"

if [ $MISSING -gt 0 ]; then
    echo ""
    echo -e "${RED}Missing files. Run discovery first.${NC}"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# STEP 3: PUSH TO VM
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN} STEP 3: PUSH TO VM${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Start VM if not running
echo -e "${BLUE}Start VM...${NC}"
"$SCRIPT_DIR/vm-sync.sh" start 2>/dev/null || true
sleep 5

# Push project
echo -e "${BLUE}Push project to VM...${NC}"
"$SCRIPT_DIR/vm-sync.sh" push "$PROJECT_DIR"

# Push secrets file if it exists (for MCP API keys)
if [ -f "$PROJECT_DIR/.ralph/secrets.env" ]; then
    echo -e "${BLUE}Push secrets to VM...${NC}"
    "$SCRIPT_DIR/vm-sync.sh" push "$PROJECT_DIR/.ralph/secrets.env"
    echo -e "${GREEN}✓ Secrets uploaded${NC}"
elif [ -f ".ralph/secrets.env" ]; then
    # Try from current directory if project doesn't have one
    echo -e "${BLUE}Push secrets to VM...${NC}"
    "$SCRIPT_DIR/vm-sync.sh" ssh "mkdir -p ~/workspace/.ralph"
    "$SCRIPT_DIR/vm-sync.sh" push ".ralph/secrets.env" "~/workspace/.ralph/secrets.env"
    echo -e "${GREEN}✓ Secrets uploaded${NC}"
else
    echo -e "${YELLOW}⚠ No .ralph/secrets.env found - MCP tools may be limited${NC}"
fi

echo -e "${GREEN}✓ Project uploaded to VM${NC}"

# ═══════════════════════════════════════════════════════════════
# STEP 4: START RALPH ON VM
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN} STEP 4: START RALPH ON VM${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}Starting ralph on VM...${NC}"
echo ""

# Run Ralph on VM in background (nohup)
"$SCRIPT_DIR/vm-sync.sh" run "specs/*.md" &
RALPH_PID=$!

echo -e "${GREEN}✓ Ralph startat (PID: $RALPH_PID)${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 5: MODE-SPECIFIC HANDLING
# ═══════════════════════════════════════════════════════════════
if [ "$OVERNIGHT_MODE" = true ]; then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN} OVERNIGHT MODE${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    notify "Ralph startat: $PROJECT_NAME (overnight mode)"

    # Create overnight wrapper script on VM
    OVERNIGHT_SCRIPT="#!/bin/bash
cd ~/workspace
echo 'ralph overnight started: \$(date)' > ralph-overnight.log

# Run Ralph
./scripts/ralph.sh specs/*.md >> ralph-overnight.log 2>&1
EXIT_CODE=\$?

echo 'ralph finished: \$(date)' >> ralph-overnight.log
echo 'Exit code: '\$EXIT_CODE >> ralph-overnight.log

# Notify
curl -s -d \"ralph finished: $PROJECT_NAME (exit: \$EXIT_CODE)\" https://ntfy.sh/$NTFY_TOPIC || true

# Generate summary
SPECS_DONE=\$(grep -c 'DONE' ralph-overnight.log || echo 0)
SPECS_FAILED=\$(grep -c 'FAILED\\|Error' ralph-overnight.log || echo 0)
curl -s -d \"Specs: \$SPECS_DONE done, \$SPECS_FAILED issues\" https://ntfy.sh/$NTFY_TOPIC || true

# Stop VM to save money
echo 'Stopping VM...' >> ralph-overnight.log
sudo shutdown -h +5 'Ralph complete. VM stopping in 5 minutes.'
"

    # Push overnight script to VM
    echo "$OVERNIGHT_SCRIPT" | "$SCRIPT_DIR/vm-sync.sh" ssh "cat > ~/workspace/overnight.sh && chmod +x ~/workspace/overnight.sh"

    # Start overnight script in background with nohup
    "$SCRIPT_DIR/vm-sync.sh" ssh "cd ~/workspace && nohup ./overnight.sh > /dev/null 2>&1 &"

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN} OVERNIGHT HANDOFF READY!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Ralph is now running autonomously on the VM."
    echo ""
    echo -e "${YELLOW}What's happening:${NC}"
    echo -e " 1. Ralph is running all specs"
    echo -e " 2. You will get notification when done (ntfy.sh/$NTFY_TOPIC)"
    echo -e " 3. VM is automatically stopped (saves money)"
    echo ""
    echo -e "${YELLOW}Tomorrow:${NC}"
    echo -e " ${CYAN}./scripts/vm-sync.sh start${NC} # Start VM"
    echo -e " ${CYAN}./scripts/vm-sync.sh pull $PROJECT_NAME${NC} # Get results"
    echo -e " ${CYAN}cat $PROJECT_NAME/ralph-overnight.log${NC} # View log"
    echo ""
    echo -e "${BLUE}Sov gott!${NC}"
    echo ""

elif [ "$WATCH_MODE" = true ]; then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN} WATCH MODE${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Watching VM progress... (Ctrl+C to exit)${NC}"
    echo ""

    # Wait for Ralph to finish
    wait $RALPH_PID || true

    echo ""
    echo -e "${GREEN}✓ Ralph ready!${NC}"
    echo ""

    # Pull results
    echo -e "${BLUE}Pulling results...${NC}"
    "$SCRIPT_DIR/vm-sync.sh" pull "$PROJECT_DIR"

    # Stop VM to save money
    read -p "Stop VM to save money? [Y/n]: " STOP_VM
    STOP_VM=${STOP_VM:-y}
    if [[ "$STOP_VM" =~ ^[Yy] ]]; then
        "$SCRIPT_DIR/vm-sync.sh" stop
    fi
else
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN} HANDOFF READY!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Ralph is now running on VM in the background."
    echo ""
    echo -e "${YELLOW}Commands:${NC}"
    echo -e " ${CYAN}./scripts/vm-sync.sh ssh${NC} # SSH to VM"
    echo -e " ${CYAN}./scripts/vm-sync.sh pull $PROJECT_NAME${NC} # Get results"
    echo -e " ${CYAN}./scripts/vm-sync.sh stop${NC} # Stop VM"
    echo ""
fi
