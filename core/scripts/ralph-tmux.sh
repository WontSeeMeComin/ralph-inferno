#!/bin/bash
# ralph-tmux.sh - Ralph with TMUX context scraping
#
# "LLMs know how to run TMUX. Think of loop backs.
# all the ways the LLM can automatically scrape context."
# - Geoffrey Huntley
#
# Creates TMUX session with:
# - Pane 0: Dev server (npm run dev)
# - Pane 1: Ralph loop with context from pane 0
#
# Usage: ./ralph-tmux.sh <spec file> [dev command]

set -e

SPEC_FILE="${1:-spec.md}"
DEV_CMD="${2:-npm run dev}"
SESSION="ralph-dev-$$"
MAX_ITERATIONS="${3:-30}"
COMPLETION_MARKER="<promise>DONE</promise>"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Ralph TMUX Mode ===${NC}"
echo "Session: $SESSION"
echo "Spec: $SPEC_FILE"
echo "Dev cmd: $DEV_CMD"
echo ""

# Verify specs exist
if [ ! -f "$SPEC_FILE" ]; then
    echo -e "${RED}Error: Spec file '$SPEC_FILE' not found${NC}"
    exit 1
fi

# Create TMUX session
tmux new-session -d -s "$SESSION" -x 200 -y 50

# Split horizontally
tmux split-window -h -t "$SESSION"

# Pane 0 (left): Dev server
tmux send-keys -t "$SESSION:0.0" "$DEV_CMD 2>&1 | tee /tmp/ralph-dev-$$.log" Enter

# Wait for the server to start
sleep 3

# Pane 1 (right): Ralph loop with context scraping
tmux send-keys -t "$SESSION:0.1" "
SPEC_FILE='$SPEC_FILE'
MAX_ITERATIONS=$MAX_ITERATIONS
COMPLETION_MARKER='$COMPLETION_MARKER'
BASE_PROMPT=\$(cat \"\$SPEC_FILE\")

echo '=== Ralph with TMUX Context ==='
echo ''

for i in \$(seq 1 \$MAX_ITERATIONS); do
    echo \"--- Iteration \$i/\$MAX_ITERATIONS ---\"

    # Scrape context from dev server (last 30 lines)
    DEV_CONTEXT=\$(tail -30 /tmp/ralph-dev-$$.log 2>/dev/null || echo 'No dev output')

    # Build prompt with context
    PROMPT=\"\$BASE_PROMPT

## Current server output (last 30 lines):
\\\`\\\`\\\`
\$DEV_CONTEXT
\\\`\\\`\\\`

If there are errors in the server output, fix them.\"

    # Run Claude
    # IMPORTANT: Use pipe instead of --print which hangs!
    OUTPUT=\$(echo \"\$PROMPT\" | claude --dangerously-skip-permissions 2>&1)
    echo \"\$OUTPUT\"

    # Check completion
    if echo \"\$OUTPUT\" | grep -q \"\$COMPLETION_MARKER\"; then
        echo ''
        echo '✅ Completion marker found!'
        echo \"Ralph ready after \$i iterations\"
        break
    fi

    sleep 2
done

echo ''
echo 'Press Enter to end the TMUX session'
read
tmux kill-session -t $SESSION
" Enter

# Info
echo -e "${GREEN}TMUX session started!${NC}"
echo ""
echo "Commands:"
echo " tmux attach -t $SESSION # Show the session"
echo " tmux kill-session -t $SESSION # Terminate"
echo ""
echo -e "${YELLOW}Tip: Pane 0 = dev server, Pane 1 = ralph${NC}"
echo ""

# Ask for attach
read -p "Attach to session? (y/n): " choice
if [ "$choice" = "y" ]; then
    tmux attach -t "$SESSION"
fi
