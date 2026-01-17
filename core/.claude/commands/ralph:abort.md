# /ralph:abort - Stop Ralph on VM

Stop ralph gracefully on VM.

## Usage
```
/ralph:abort
/ralph:abort --force     # Kill without waiting
```

## Instructions

**STEP 1: READ VM CONFIG**
```bash
source ~/.ralph-vm
```

**STEP 2: STOP RALPH**
```bash
ssh $VM_USER@$VM_IP << 'EOF'
echo "=== STOPPING RALPH ==="

# Find Ralph processes
PIDS=$(pgrep -f "ralph.sh|orchestrator.sh|claude" | tr '\n' ' ')

if [ -z "$PIDS" ]; then
    echo "⏹️ Ralph is not running"
    exit 0
fi

echo "Found PIDs: $PIDS"

# Graceful stop first (SIGTERM)
echo "Sending SIGTERM..."
kill $PIDS 2>/dev/null || true

# Wait max 10 seconds
for i in {1..10}; do
    sleep 1
    if ! pgrep -f "ralph.sh" > /dev/null; then
        echo "✅ Ralph stopped gracefully"
        exit 0
    fi
    echo "Waiting... ($i/10)"
done

# Force kill if still running
echo "⚠️ Force killing..."
kill -9 $PIDS 2>/dev/null || true

echo "✅ Ralph stopped (forced)"
EOF
```

**STEP 3: SHOW STATUS**
```bash
# Show what was saved
ssh $VM_USER@$VM_IP << 'EOF'
cd ~/projects/$(ls -t ~/projects | head -1)

echo ""
echo "=== SAVED PROGRESS ==="

if [ -d ".spec-checksums" ]; then
    done=$(ls -1 .spec-checksums/*.md5 2>/dev/null | wc -l | tr -d ' ')
    echo "✅ Completed specs: $done"
fi

# Show last commit
echo ""
echo "Last commit:"
git log -1 --oneline
EOF
```

**OUTPUT:**
```
=== STOPPING RALPH ===
Found PIDs: 12345 12346
Sending SIGTERM...
✅ Ralph stopped gracefully

=== SAVED PROGRESS ===
✅ Completed specs: 15
Last commit: abc123 Ralph: 15-user-profile
```

**IF --force FLAG:**
Skip graceful, run directly:
```bash
ssh $VM_USER@$VM_IP "pkill -9 -f 'ralph.sh|orchestrator.sh|claude'"
```
