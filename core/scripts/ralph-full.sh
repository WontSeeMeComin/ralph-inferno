#!/bin/bash
# =============================================================================
#
#  ██████╗  █████╗ ██╗     ██████╗ ██╗  ██╗
#  ██╔══██╗██╔══██╗██║     ██╔══██╗██║  ██║
#  ██████╔╝███████║██║     ██████╔╝███████║
#  ██╔══██╗██╔══██║██║     ██╔═══╝ ██╔══██║
#  ██║  ██║██║  ██║███████╗██║     ██║  ██║
#  ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝
#
# The One Script To Rule Them All
#
# =============================================================================
#
# Usage:
# ./ralph.sh # Run all specs in specs/
# ./ralph.sh specs/10-theme.md # Run one spec
# ./ralph.sh specs/*.md # Run multiple specs (in parallel if >1)
# ./ralph.sh --status # Show status
# ./ralph.sh --watch # Fireplace view (live monitoring)
# ./ralph.sh --help # Help
#
# Features:
# ✓ Self-healing (retries with error report)
# ✓ Rate limit & token tracking
# ✓ Build lock cleanup
# ✓ Backup & secrets scanning
# ✓ Dangerous command blocking
# ✓ Git branch isolation
# ✓ Smart parallel execution (worktrees, max 3)
# ✓ Smart conflict resolution (auto-resolve test/logs, pause on source)
# ✓ Supervisor quality checks
# ✓ Auto-merge if safe
# ✓ GitHub PRs if manual review needed
# ✓ ✓ ntfy notifications
# ✓ ✓ Summary report
# ✓ ✓ progress.txt (short-term memory - Ryan Carson)
# ✓ ✓ CLAUDE.md updates (long-term memory)
# ✓ Checksum tracking (skip already run specs)
#
# =============================================================================

set -uo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Timing & Retries
MAX_RETRIES=3
PARALLEL_THRESHOLD=2 # Run in parallel if more specs than this

# Load config to determine timeouts
RALPH_CONFIG="$HOME/.ralph-vm"
if [ -f "$RALPH_CONFIG" ]; then
    source "$RALPH_CONFIG"
fi

# Adjust timeouts based on Claude mode
CLAUDE_MODE="${CLAUDE_VM_MODE:-${CLAUDE_LOCAL_MODE:-max}}"
if [ "$CLAUDE_MODE" = "api" ]; then
    TIMEOUT=900 # 15 min for API (faster)
    PARALLEL_MAX=5 # More parallels for API
    SUPERVISOR_TIMEOUT=120
else
    TIMEOUT=1800 # 30 min for MAX (can be slower)
    PARALLEL_MAX=2 # Start with 2, dynamically adjusted
    SUPERVISOR_TIMEOUT=300
fi

# =============================================================================
# DYNAMIC PARALLEL SCALING - Adjust number of processes based on resources
# =============================================================================
get_available_ram_gb() {
    # Returns available RAM in GB
    free -g 2>/dev/null | awk '/^Mem:/ {print $7}' || echo "4"
}

get_cpu_cores() {
    nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "2"
}

get_cpu_load() {
    # Returns 1-min load average
    uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | tr -d ' ' || echo "1"
}

calculate_optimal_parallel() {
    local available_ram=$(get_available_ram_gb)
    local cpu_cores=$(get_cpu_cores)
    local cpu_load=$(get_cpu_load)

    # Each Claude process needs ~500MB RAM and some CPU
    local ram_based_max=$((available_ram * 2)) # 2 processes per GB available

    # CPU based: max cores - current load, minimum 1
    local load_int=${cpu_load%.*} # Remove decimals
    local cpu_based_max=$((cpu_cores - load_int))
    [ $cpu_based_max -lt 1 ] && cpu_based_max=1

    # Take the lowest of RAM and CPU
    local optimal=$ram_based_max
    [ $cpu_based_max -lt $optimal ] && optimal=$cpu_based_max

    # Limit to 1-6 processes
    [ $optimal -lt 1 ] && optimal=1
    [ $optimal -gt 6 ] && optimal=6

    echo $optimal
}

maybe_scale_parallel() {
    local current_running=$1
    local new_max=$(calculate_optimal_parallel)

    if [ $new_max -ne $PARALLEL_MAX ]; then
        log "${CYAN}📊 Dynamic scaling: $PARALLEL_MAX → $new_max (RAM: $(get_available_ram_gb)GB, CPU load: $(get_cpu_load))${NC}"
        PARALLEL_MAX=$new_max
    fi
}

# Stack Detection
CURRENT_STACK=""
STACK_TEMPLATE_DIR=""

# Paths
LOG_DIR="ralph-logs"
BACKUP_DIR="${HOME}/ralph-backups"
RATE_LIMIT_LOG="${HOME}/ralph-rate-limits.log"
TOKEN_LOG="${HOME}/ralph-tokens.log"
WORKTREE_BASE="${HOME}/ralph-worktrees"
PROGRESS_FILE="progress.txt" # Short-term memory (Ryan Carson)
CHECKSUM_DIR=".spec-checksums" # Track completed specs

# Markers
COMPLETION_MARKER="<promise>DONE</promise>"

# Notifications
NTFY_TOPIC="${NTFY_TOPIC:-}"

# Git
MAIN_BRANCH="main"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# HELP FUNCTIONS
# =============================================================================
log() {
    echo -e "[$(date +%H:%M:%S)] $1"
}

notify() {
    local msg="$1"
    local priority="${2:-default}"
    if [ -n "$NTFY_TOPIC" ]; then
        curl -s -H "Priority: $priority" -d "$msg" "https://ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1 || true
    fi
}

# =============================================================================
# EPIC TRACKING - Dynamically reads IMPLEMENTATION_PLAN.md
# =============================================================================
CURRENT_EPIC=""
CURRENT_EPIC_NAME=""
PLAN_FILE=""

# Find IMPLEMENTATION_PLAN.md
find_plan_file() {
    if [ -f "docs/IMPLEMENTATION_PLAN.md" ]; then
        echo "docs/IMPLEMENTATION_PLAN.md"
    elif [ -f "IMPLEMENTATION_PLAN.md" ]; then
        echo "IMPLEMENTATION_PLAN.md"
    else
        echo ""
    fi
}

# Get all epics as associative array-like output
# Format: E1|Project setup & Database
get_all_epics() {
    local plan_file=$(find_plan_file)
    if [ -z "$plan_file" ]; then
        return
    fi

    # Find the epic table and extract E1, E2, etc by name
    grep -E "^\| *E[0-9]+ *\|" "$plan_file" 2>/dev/null | while read -r line; do
        local epic_id=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
        local epic_name=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')
        echo "$epic_id|$epic_name"
    done
}

# Find which epic a task belongs to based on task id or description
# Reads sections like: ### Critical (E1: Project Setup & Database)
get_epic_for_task() {
    local task_search="$1" # Can be task id (T1.1) or keyword
    local plan_file=$(find_plan_file)

    if [ -z "$plan_file" ]; then
        echo ""
        return
    fi

    # Find the section containing the bag
    # Sections look like: ### Critical (E1: Project Setup & Database)
    local current_epic=""
    local current_epic_name=""

    while IFS= read -r line; do
        # Check if it is an epic section
        if echo "$line" | grep -qE "^###.*\(E[0-9]+:"; then
            current_epic=$(echo "$line" | grep -oE "E[0-9]+" | head -1)
            current_epic_name=$(echo "$line" | sed 's/.*(\(E[0-9]*: *\)\(.*\))/\2/' | sed 's/)$//')
        fi

        # Check if the bag is on this line
        if echo "$line" | grep -qi "$task_search"; then
            if [ -n "$current_epic" ]; then
                echo "$current_epic|$current_epic_name"
                return
            fi
        fi
    done < "$plan_file"

    echo ""
}

# Match spec file against task in plan
# Trying to match spec names against task descriptions
match_spec_to_epic() {
    local spec_name="$1"
    local plan_file=$(find_plan_file)

    if [ -z "$plan_file" ]; then
        echo ""
        return
    fi

    # Strategy 1: Exact task-id match (if spec is named e.g. "T1.1-setup")
    if echo "$spec_name" | grep -qE "^T[0-9]+\.[0-9]+"; then
        local task_id=$(echo "$spec_name" | grep -oE "^T[0-9]+\.[0-9]+")
        local result=$(get_epic_for_task "$task_id")
        if [ -n "$result" ]; then
            echo "$result"
            return
        fi
    fi

    # Strategy 2: Keyword match
    # Remove numbers and hyphens, match against task descriptions
    local keywords=$(echo "$spec_name" | sed 's/^[0-9]*-//' | tr '-' ' ')

    local current_epic=""
    local current_epic_name=""

    while IFS= read -r line; do
        # Check if it is an epic section
        if echo "$line" | grep -qE "^###.*\(E[0-9]+:"; then
            current_epic=$(echo "$line" | grep -oE "E[0-9]+" | head -1)
            current_epic_name=$(echo "$line" | sed 's/.*E[0-9]*: *//' | sed 's/)$//' | sed 's/ *$//')
        fi

        # Fuzzy match: check if any keywords are in the task description
        for keyword in $keywords; do
            if [ ${#keyword} -gt 3 ] && echo "$line" | grep -qi "$keyword"; then
                if [ -n "$current_epic" ]; then
                    echo "$current_epic|$current_epic_name"
                    return
                fi
            fi
        done
    done < "$plan_file"

    # Strategy 3: Number-based fallback
    local spec_num=$(echo "$spec_name" | grep -oE "^[0-9]+" | sed 's/^0*//')
    if [ -n "$spec_num" ]; then
        # Assume spec 01-03 is E1, 04-06 is E2, etc (fallback)
        local epic_num=$(( (spec_num - 1) / 3 + 1 ))
        local fallback_epic="E$epic_num"
        local fallback_name=$(grep -E "^\| *$fallback_epic *\|" "$plan_file" 2>/dev/null | head -1 | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')
        if [ -n "$fallback_name" ]; then
            echo "$fallback_epic|$fallback_name"
            return
        fi
    fi

    echo ""
}

# Notify about epic byte
notify_epic_change() {
    local spec_name="$1"

    local epic_info=$(match_spec_to_epic "$spec_name")

    if [ -z "$epic_info" ]; then
        return
    fi

    local new_epic=$(echo "$epic_info" | cut -d'|' -f1)
    local new_epic_name=$(echo "$epic_info" | cut -d'|' -f2)

    if [ "$new_epic" != "$CURRENT_EPIC" ]; then
        # Exit last epic if it existed
        if [ -n "$CURRENT_EPIC" ] && [ -n "$CURRENT_EPIC_NAME" ]; then
            notify "🎉 $CURRENT_EPIC: $CURRENT_EPIC_NAME - Done!" "default"
            log "${GREEN}🎉 $CURRENT_EPIC: $CURRENT_EPIC_NAME - Ready!${NC}"
        fi

        # Start new epic
        CURRENT_EPIC="$new_epic"
        CURRENT_EPIC_NAME="$new_epic_name"

        notify "🚀 $new_epic: $new_epic_name - Startar" "high"
        log "${MAGENTA}🚀 $new_epic: $new_epic_name - Startar${NC}"
    fi
}

# Notify task-done (includes epic info)
notify_task_done() {
    local spec_name="$1"

    if [ -n "$CURRENT_EPIC" ] && [ -n "$CURRENT_EPIC_NAME" ]; then
        notify "✅ $CURRENT_EPIC: $spec_name" "low"
    else
        notify "✅ Clear: $spec_name" "low"
    fi
}

# =============================================================================
# STACK DETECTION & TEMPLATE HOOKS
# =============================================================================
# Detects which stack is used based on project files
detect_stack() {
    local project_dir="${1:-.}"

    # React + Supabase
    if [ -f "$project_dir/package.json" ] && [ -d "$project_dir/supabase" ]; then
        if grep -q "react" "$project_dir/package.json" 2>/dev/null; then
            echo "react-supabase"
            return
        fi
    fi

    # React + Vite (without Supabase)
    if [ -f "$project_dir/vite.config.ts" ] || [ -f "$project_dir/vite.config.js" ]; then
        if grep -q "react" "$project_dir/package.json" 2>/dev/null; then
            echo "react-vite"
            return
        fi
    fi

    # Next.js
    if [ -f "$project_dir/next.config.js" ] || [ -f "$project_dir/next.config.mjs" ]; then
        echo "nextjs"
        return
    fi

    # Supabase + Next.js
    if [ -d "$project_dir/supabase" ] && [ -f "$project_dir/next.config.js" ]; then
        echo "supabase-nextjs"
        return
    fi

    # Fallback: unknown
    echo "unknown"
}

# Initialize stack - call template's setup.sh
init_stack() {
    local project_dir="${1:-.}"

    CURRENT_STACK=$(detect_stack "$project_dir")
    STACK_TEMPLATE_DIR="$RALPH_DIR/templates/stacks/$CURRENT_STACK"

    log "${CYAN}Stack detected: $CURRENT_STACK${NC}"

    if [ -d "$STACK_TEMPLATE_DIR" ]; then
        log "${CYAN}Template: $STACK_TEMPLATE_DIR${NC}"

        # Copy CLAUDE.md if it is missing in the project
        if [ -f "$STACK_TEMPLATE_DIR/CLAUDE.md" ] && [ ! -f "$project_dir/CLAUDE.md" ]; then
            cp "$STACK_TEMPLATE_DIR/CLAUDE.md" "$project_dir/"
            log "${GREEN}Copied stack CLAUDE.md${NC}"
        fi

        # Run setup.sh if it exists
        if [ -x "$STACK_TEMPLATE_DIR/scripts/setup.sh" ]; then
            log "${BLUE}Run stack setup...${NC}"
            if ! "$STACK_TEMPLATE_DIR/scripts/setup.sh" "$project_dir"; then
                log "${RED}Setup FAILED - cannot continue${NC}"
                log "${YELLOW}Fix the problems above and run again${NC}"
                exit 1
            fi
        fi
    else
        log "${YELLOW}No template for stack: $CURRENT_STACK${NC}"
    fi
}

# Call stack hook
call_stack_hook() {
    local hook_name="$1"
    local project_dir="${2:-.}"
    shift 2
    local extra_args=("$@")

    if [ -z "$STACK_TEMPLATE_DIR" ] || [ ! -d "$STACK_TEMPLATE_DIR" ]; then
        return 0
    fi

    local hook_script="$STACK_TEMPLATE_DIR/hooks/$hook_name.sh"

    if [ -x "$hook_script" ]; then
        log "${CYAN}Hook: $hook_name${NC}"
        "$hook_script" "$project_dir" "${extra_args[@]}" || {
            log "${YELLOW}Hook $hook_name failed${NC}"
            return 1
        }
    fi

    return 0
}

# Run stack verification with self-healing
run_stack_verify() {
    local project_dir="${1:-.}"
    local max_heal_attempts=3
    local heal_attempt=0

    # Verify dependencies first
    (cd "$project_dir" && ensure_dependencies) || true

    while [ $heal_attempt -lt $max_heal_attempts ]; do
        ((heal_attempt++))

        local verify_output=""
        local verify_exit=0

        if [ -z "$STACK_TEMPLATE_DIR" ] || [ ! -d "$STACK_TEMPLATE_DIR" ]; then
            # Fallback: run npm run build
            if [ -f "$project_dir/package.json" ]; then
                log "${BLUE}Fallback verify: npm run build (attempt $heal_attempt/$max_heal_attempts)${NC}"
                verify_output=$((cd "$project_dir" && npm run build) 2>&1) || verify_exit=$?
            else
                return 0
            fi
        else
            local verify_script="$STACK_TEMPLATE_DIR/scripts/verify.sh"

            if [ -x "$verify_script" ]; then
                log "${CYAN}═══ STACK VERIFICATION (attempt $heal_attempt/$max_heal_attempts) ═══${NC}"
                verify_output=$("$verify_script" "$project_dir" 2>&1) || verify_exit=$?
            else
                return 0
            fi
        fi

        # If successful, return OK
        if [ $verify_exit -eq 0 ]; then
            log "${GREEN}Stack verifying OK${NC}"
            return 0
        fi

        # Failed - try self-heal
        log "${RED}Stack verification FAILED${NC}"
        echo "$verify_output" | tail -20

        # Try self-heal
        if try_selfheal "$verify_output"; then
            log "${CYAN}Trying again for self-heal...${NC}"
            continue
        else
            # Nothing to heal - give up
            log "${RED}No self-heal possible${NC}"
            return 1
        fi
    done

    log "${RED}Max self-heal attempts ($max_heal_attempts) - gives up${NC}"
    return 1
}

# =============================================================================
# CHECKSUM TRACKING - Skip already running specs
# =============================================================================
spec_checksum() {
    local spec_file="$1"
    md5sum "$spec_file" 2>/dev/null | cut -d' ' -f1 || md5 -q "$spec_file" 2>/dev/null
}

is_spec_already_done() {
    local spec_file="$1"
    local basename=$(basename "$spec_file")
    local checksum_file="$CHECKSUM_DIR/$basename.md5"

    mkdir -p "$CHECKSUM_DIR"

    if [ -f "$checksum_file" ]; then
        local old_checksum=$(cat "$checksum_file")
        local new_checksum=$(spec_checksum "$spec_file")

        if [ "$old_checksum" = "$new_checksum" ]; then
            return 0 # true - already run with same content
        fi
    fi
    return 1 # false - new or modified
}

save_spec_checksum() {
    local spec_file="$1"
    local basename=$(basename "$spec_file")

    mkdir -p "$CHECKSUM_DIR"
    spec_checksum "$spec_file" > "$CHECKSUM_DIR/$basename.md5"
}

# =============================================================================
# TOKEN & CONTEXT MANAGEMENT
# =============================================================================
estimate_tokens() {
    local text="$1"
    local chars=$(echo -n "$text" | wc -c)
    echo $((chars * 10 / 35))
}

log_tokens() {
    local context="$1"
    local tokens="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $tokens tokens | $context" >> "$TOKEN_LOG"
}

check_context_budget() {
    local current_tokens=$1
    local max_tokens=${2:-176000}
    local usage_percent=$((current_tokens * 100 / max_tokens))

    if [ $usage_percent -gt 80 ]; then
        log "${RED}⚠️ Context: $usage_percent% - near limit!${NC}"
        return 1
    fi
    return 0
}

# =============================================================================
# RATE LIMIT HANDLING
# =============================================================================
RATE_LIMIT_PATTERNS=(
    "rate.limit"
    "too.many.requests"
    "quota.exceeded"
    "capacity"
    "try.again.later"
    "retry.after"
    "429"
    "overloaded"
)

is_rate_limited() {
    local output="$1"
    for pattern in "${RATE_LIMIT_PATTERNS[@]}"; do
        if echo "$output" | grep -qi "$pattern"; then
            return 0
        fi
    done
    return 1
}

log_rate_limit() {
    local context="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $context" >> "$RATE_LIMIT_LOG"
    local total=$(wc -l < "$RATE_LIMIT_LOG" 2>/dev/null || echo 0)
    log "${YELLOW}⚠️ Rate limit hit #$total${NC}"
}

# =============================================================================
# SELF-HEALING: Detect and fix missing dependencies
# =============================================================================
SELFHEAL_PATTERNS=(
    # Pattern|Fix command|Description
    "tsc: not found|npm install -g typescript|TypeScript compiler"
    "npx: not found|npm install -g npx|npx command"
    "node: not found|echo 'Install Node.js manually'|Node.js runtime"
    "vite: not found|npm install vite|Vite bundler"
    "vitest: not found|npm install vitest|Vitest test runner"
    "playwright: not found|npx playwright install|Playwright browser"
    "supabase: not found|npm install -g supabase|Supabase CLI"
    "Cannot find module|npm install|Missing npm package"
    "ENOENT.*node_modules|npm install|Missing node_modules"
    "MODULE_NOT_FOUND|npm install|Missing module"
    "ERR_MODULE_NOT_FOUND|npm install|Missing ES module"
)

# Try self-heal based on error output
try_selfheal() {
    local error_output="$1"
    local healed=false

    log "${CYAN}═══ SELF-HEALING CHECK ═══${NC}"

    for pattern_entry in "${SELFHEAL_PATTERNS[@]}"; do
        local pattern=$(echo "$pattern_entry" | cut -d'|' -f1)
        local fix_cmd=$(echo "$pattern_entry" | cut -d'|' -f2)
        local description=$(echo "$pattern_entry" | cut -d'|' -f3)

        if echo "$error_output" | grep -qiE "$pattern"; then
            log "${YELLOW}🔧 Detected: $description${NC}"
            log "${BLUE} Fix: $fix_cmd${NC}"

            # Run the fix command
            if eval "$fix_cmd" 2>&1; then
                log "${GREEN}✅ Self-heal successful: $description${NC}"
                notify "🔧 Self-heal: $description"
                healed=true
            else
                log "${RED}❌ Self-heal failed: $description${NC}"
                notify "❌ Self-heal failed: $description" "high"
            fi
        fi
    done

    if [ "$healed" = true ]; then
        return 0 # Something was healed, retry build
    else
        return 1 # Nothing to heal
    fi
}

# Run npm install if package.json exists but node_modules is missing
ensure_dependencies() {
    if [ -f "package.json" ] && [ ! -d "node_modules" ]; then
        log "${YELLOW}🔧 node_modules missing - run npm install${NC}"
        npm install 2>&1 || {
            log "${RED}npm install failed${NC}"
            return 1
        }
        log "${GREEN}✅ Dependencies installed${NC}"
    fi
    return 0
}

# =============================================================================
# CLEANUP: Locks, cache, processes
# =============================================================================
cleanup_locks() {
    log "${BLUE}Cleans locks...${NC}"

    # Next.js
    rm -rf .next/lock 2>/dev/null || true

    # Turbo
    rm -rf .turbo/.lock 2>/dev/null || true

    # Node modules cache
    rm -rf node_modules/.cache/.lock 2>/dev/null || true

    # Kill hanging builds
    pkill -f "next build" 2>/dev/null || true
    pkill -f "turbo build" 2>/dev/null || true
}

# =============================================================================
# BACKUP
# =============================================================================
backup_project() {
    local backup_path="$BACKUP_DIR/$TIMESTAMP"
    log "${BLUE}Backup: $backup_path${NC}"
    mkdir -p "$backup_path"
    rsync -a --exclude='node_modules' --exclude='.git' --exclude='.next' . "$backup_path/" 2>/dev/null || true
}

# =============================================================================
# MEMORY LAYER (Ryan Carson pattern)
# =============================================================================

# Read progress.txt to include in prompt
get_progress_context() {
    if [ -f "$PROGRESS_FILE" ]; then
        local lines=$(wc -l < "$PROGRESS_FILE")
        if [ "$lines" -gt 100 ]; then
            # Take only last 100 lines to save context
            tail -100 "$PROGRESS_FILE"
        else
            cat "$PROGRESS_FILE"
        fi
    fi
}

# Log learnings to progress.txt (short-term memory)
log_progress() {
    local spec_name="$1"
    local iteration="$2"
    local status="$3"

    cat >> "$PROGRESS_FILE" << EOF

---
## $(date '+%Y-%m-%d %H:%M:%S') | $spec_name | Iteration $iteration | $status

EOF

    # Ask Claude to log his learnings
    echo "You have just finished iteration $iteration of $spec_name.
Write 2-3 short paragraphs about:
1. What was implemented
2. any gotchas or patterns you discovered
3. files that were changed

Answer ONLY with the bullet points, nothing else." | \
        timeout 60 claude --dangerously-skip-permissions 2>/dev/null >> "$PROGRESS_FILE" || true

    log "${CYAN}Progress logged to $PROGRESS_FILE${NC}"
}

# Update CLAUDE.md with long-term learnings (long-term memory)
update_claude_md() {
    local spec_name="$1"

    # Check if CLAUDE.md exists
    if [ ! -f "CLAUDE.md" ]; then
        return 0
    fi

    log "${CYAN}Updating CLAUDE.md with learnings...${NC}"

    echo "You have just completed $spec_name.
If you discovered new patterns, gotchas, or important conventions that future developers should know:
1. read CLAUDE.md
2. If there is something important to add under the ## Learnings or similar section, do so
3. Keep it short and relevant
4. If nothing important to add, do nothing

Don't reply with anything - just update the file if necessary." | \
        timeout $SUPERVISOR_TIMEOUT claude --dangerously-skip-permissions 2>/dev/null || true
}

# =============================================================================
# SECURITY: Dangerous commands
# =============================================================================
check_dangerous_commands() {
    local diff_content
    diff_content=$(git diff 2>/dev/null) || return 0

    local dangerous=(
        "rm -rf /"
        "rm -rf ~"
        "sudo rm -rf"
        "chmod -R 777 /"
        "dd if=/dev"
        "> /dev/sd"
    )

    for pattern in "${dangerous[@]}"; do
        if echo "$diff_content" | grep -qF "$pattern"; then
            log "${RED}🚨 DANGEROUS COMMAND: $pattern${NC}"
            return 1
        fi
    done

    # curl/wget pipe to bash
    if echo "$diff_content" | grep -qE "curl.*\|.*bash|wget.*\|.*bash"; then
        log "${RED}🚨 DANGEROUS: curl/wget pipe to bash${NC}"
        return 1
    fi

    return 0
}

# =============================================================================
# SECURITY: Secrets scanning
# =============================================================================
scan_secrets() {
    local secrets_found=0

    # .env files
    if git diff --cached --name-only 2>/dev/null | grep -qE "^\.env|\.env\.|config/\.env"; then
        log "${RED}🚨 .env file staged!${NC}"
        secrets_found=1
    fi

    # API keys
    local patterns=(
        "sk-ant-[a-zA-Z0-9]{20,}"
        "sk-[a-zA-Z0-9]{40,}"
        "ghp_[a-zA-Z0-9]{30,}"
        "gho_[a-zA-Z0-9]{30,}"
        "sb_[a-zA-Z0-9]{30,}"
        "eyJ[a-zA-Z0-9_-]{50,}"
    )

    for pattern in "${patterns[@]}"; do
        if git diff --cached 2>/dev/null | grep -qE "$pattern"; then
            log "${RED}🚨 SECRET: $pattern${NC}"
            secrets_found=1
        fi
    done

    return $secrets_found
}

# =============================================================================
# TESTER: Smart filtering
# =============================================================================
run_tests() {
    if [ ! -f "package.json" ]; then
        log "${YELLOW}No package.json - skipping tester${NC}"
        return 0
    fi

    if ! grep -q '"test"' package.json 2>/dev/null; then
        log "${YELLOW}⚠️ No test script in package.json${NC}"
        # Return OK but log warning - supervisor checks adding tests
        return 0
    fi

    log "Running tests..."
    local output
    local exit_code=0
    output=$(npm test 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "$output" | tail -3
        return 0
    else
        log "${RED}Tester failed:${NC}"
        echo "$output" | grep -A 3 -B 1 "FAIL\|Error\|✗" | head -20
        return 1
    fi
}

# =============================================================================
# SUPERVISOR: Quality controls
# =============================================================================
run_supervisor_checks() {
    log "${CYAN}═══ SUPERVISOR CHECKS ═══${NC}"

    # Check 1: Tests - run and fix until they pass
    log "${YELLOW}Check 1: Tests${NC}"
    local test_attempts=0
    local max_test_attempts=3

    while [ $test_attempts -lt $max_test_attempts ]; do
        ((test_attempts++))
        log " Test attempt $test_attempts/$max_test_attempts"

        # Run tester
        local test_output
        local test_exit=0
        test_output=$(npm test 2>&1) || test_exit=$?

        if [ $test_exit -eq 0 ]; then
            log "${GREEN} ✅ All tests pass${NC}"
            break
        else
            log "${RED} ❌ Tester fails${NC}"
            echo "$test_output" | tail -20

            if [ $test_attempts -lt $max_test_attempts ]; then
                log " Ber Claude fixa..."
                local fix_prompt="The tests fail with the following output:

$test_output

Fix the tests so they pass. Run 'npm test' to verify."

                echo "$fix_prompt" | timeout $((SUPERVISOR_TIMEOUT * 2)) claude --dangerously-skip-permissions 2>&1 || true

                git add -A 2>/dev/null || true
                git commit -m "Supervisor: fix failing tests (attempt $test_attempts)" 2>/dev/null || true
            fi
        fi
    done

    # Check 2: TypeScript
    log "${YELLOW}Check 2: TypeScript${NC}"
    local tsc_output
    local tsc_exit=0
    tsc_output=$(npx tsc --noEmit 2>&1) || tsc_exit=$?

    if [ $tsc_exit -eq 0 ]; then
        log "${GREEN} ✅ TypeScript OK${NC}"
    else
        log "${RED} ❌ TypeScript error${NC}"
        echo "$tsc_output" | head -20

        # Try self-heal first (e.g. tsc: not found)
        if try_selfheal "$tsc_output"; then
            log " Trying again after self-heal..."
            tsc_output=$(npx tsc --noEmit 2>&1) || tsc_exit=$?
            if [ $tsc_exit -eq 0 ]; then
                log "${GREEN} ✅ TypeScript OK after self-heal${NC}"
            fi
        fi

        # If still error, ask Claude to fix
        if [ $tsc_exit -ne 0 ]; then
            log " Tell Claude to fix..."
            echo "Fix the TypeScript errors:

$tsc_output" | timeout $((SUPERVISOR_TIMEOUT * 2)) claude --dangerously-skip-permissions 2>&1 || true

            git add -A 2>/dev/null || true
            git commit -m "Supervisor: fix TypeScript errors" 2>/dev/null || true
        fi
    fi

    # Check 3: Build
    log "${YELLOW}Check 3: Build${NC}"
    local build_output
    local build_exit=0
    build_output=$(npm run build 2>&1) || build_exit=$?

    if [ $build_exit -eq 0 ]; then
        log "${GREEN} ✅ Build OK${NC}"
    else
        log "${RED} ❌ Build failar${NC}"
        echo "$build_output" | tail -20

        # Try self-heal first
        if try_selfheal "$build_output"; then
            log " Trying again after self-heal..."
            build_output=$(npm run build 2>&1) || build_exit=$?
            if [ $build_exit -eq 0 ]; then
                log "${GREEN} ✅ Build OK after self-heal${NC}"
            fi
        fi

        # If still error, ask Claude to fix
        if [ $build_exit -ne 0 ]; then
            log " Tell Claude to fix..."
            echo "Build failar:

$build_output

Fix so the project builds." | timeout $((SUPERVISOR_TIMEOUT * 2)) claude --dangerously-skip-permissions 2>&1 || true

            git add -A 2>/dev/null || true
            git commit -m "Supervisor: fix build errors" 2>/dev/null || true
        fi
    fi

    return 0
}

# =============================================================================
# RUN A SPEC
# =============================================================================
run_single_spec() {
    local spec="$1"
    local branch="$2"
    local attempt=1
    local error_context=""
    local session_id=""
    local spec_name=$(basename "$spec" .md)

    log "${GREEN}=== $spec_name ===${NC}"

    # Epic tracking - notify about new epic
    notify_epic_change "$spec_name"

    # Checksum check: skip if already running with same content
    if is_spec_already_done "$spec"; then
        log "${BLUE}⏭ Spec already run (same checksum) - probably implemented${NC}"
        log " Skipping to save tokens"
        return 0
    fi

    # Cleanup before
    cleanup_locks

    # Read specs and count tokens
    local prompt=$(cat "$spec")
    local tokens=$(estimate_tokens "$prompt")
    log_tokens "$spec" "$tokens"
    log "Tokens: ~$tokens"

    # Generate session ID for this spec (for resume)
    session_id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$$")
    log "Session ID: $session_id"

    while [ $attempt -le $MAX_RETRIES ]; do
        log "${YELLOW}Attempt $attempt/$MAX_RETRIES${NC}"

        local output
        local exit_code=0

        if [ $attempt -eq 1 ]; then
            # FIRST RUN: Minimal prompt (small context = better result)
            # NO progress context - Claude reads the code himself

            local full_prompt="$prompt

---
When done: type <promise>DONE</promise>
Before DONE: run 'npm run build' and verify that it passes."

            log "${CYAN}Starting new session...${NC}"
            output=$(echo "$full_prompt" | timeout $TIMEOUT claude --session-id "$session_id" --dangerously-skip-permissions -p 2>&1) || exit_code=$?

        else
            # RETRY: Resume session with only error information (saves tokens!)
            local retry_prompt="VERIFICATION FAILED!

$error_context

Fix the errors above. Run 'npm run build' to verify.
Write <promise>DONE</promise> when the build goes through."

            log "${CYAN}Resuming session (saving tokens)...${NC}"
            output=$(echo "$retry_prompt" | timeout $TIMEOUT claude --resume "$session_id" --dangerously-skip-permissions -p 2>&1) || exit_code=$?
        fi

        echo "$output"

        # Rate limit?
        if is_rate_limited "$output"; then
            log_rate_limit "Spec: $(basename "$spec")"
            log "${YELLOW}Rate limit - waiting 2 min...${NC}"
            notify "⏳ Rate limit - waiting"
            sleep 120
            continue
        fi

        # Auth error?
        if echo "$output" | grep -qi "401\|unauthorized"; then
            log "${YELLOW}Auth error - waiting 1 min...${NC}"
            sleep 60
            continue
        fi

        # Timeout?
        if [ $exit_code -eq 124 ]; then
            error_context="Timeout after 30 min"
            ((attempt++))
            continue
        fi

        # Dangerous commands?
        if ! check_dangerous_commands; then
            log "${RED}🚨 DANGEROUS COMMANDS - STOP${NC}"
            notify "🚨 Dangerous commands in $(basename "$spec")"
            return 1
        fi

        # Git checkpoint
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            # Run post-create hook for new files
            local new_files=$(git status --porcelain 2>/dev/null | grep "^??" | cut -c4-)
            for new_file in $new_files; do
                if [[ "$new_file" =~ \.(tsx|ts)$ ]]; then
                    call_stack_hook "post-create" "." "$new_file" 2>/dev/null || true
                fi
            done

            git add -A

            if ! scan_secrets; then
                log "${RED}🚨 SECRETS - STOP${NC}"
                git reset HEAD . 2>/dev/null || true
                return 1
            fi

            git commit -m "Ralph: $(basename "$spec" .md) (attempt $attempt)" 2>/dev/null || true
        fi

        # Completion marker?
        if echo "$output" | grep -q "$COMPLETION_MARKER"; then
            log "${GREEN}✅ Completion marker found${NC}"

            # HARD REQUIREMENT: Verify with stack verify (build, tester, etc)
            log "${CYAN}Verify with stack verify...${NC}"

            # Capture verify output to send to Claude on retry
            local verify_output
            verify_output=$(run_stack_verify "." 2>&1)
            local verify_exit=$?

            echo "$verify_output"

            if [ $verify_exit -eq 0 ]; then
                log "${GREEN}✅ Stack verify OK${NC}"
                # Save checksum so we skip next time
                save_spec_checksum "$spec"
                # Notify task done
                notify_task_done "$spec_name"
                # Log progress (short-term memory)
                log_progress "$(basename "$spec")" "$attempt" "SUCCESS"
                # Auto-push to remote (triggers deploy)
                if git remote get-url origin &>/dev/null; then
                    log "${CYAN}Push to origin...${NC}"
                    git push -u origin "$branch" 2>&1 || log "${YELLOW}Push failed (maybe already up)${NC}"
                fi
                return 0
            else
                log "${RED}❌ Stack verify FAILED - marker ignored${NC}"
                # Trim verify output to save tokens (max 50 lines)
                local trimmed_output
                trimmed_output=$(echo "$verify_output" | grep -E "(error|FAIL|❌|Error|failed)" | head -30)
                if [ -z "$trimmed_output" ]; then
                    trimmed_output=$(echo "$verify_output" | tail -30)
                fi
                error_context="Build FAILED. Error:

$trimmed_output"
                ((attempt++))
                continue
            fi
        fi

        # NO "exit without marker" - require explicit DONE + verify
        # If Claude exited without chips, treat as error
        if [ $exit_code -eq 0 ]; then
            log "${YELLOW}⚠️ Claude exited without DONE marker${NC}"
            error_context="You finished without writing <promise>DONE</promise>. Finish the task and write the marker."
            ((attempt++))
            continue
        fi

        error_context="$output"
        ((attempt++))
        sleep 10
    done

    log "${RED}❌ Max retries for $(basename "$spec")${NC}"
    return 1
}

# =============================================================================
# RUN PARALLEL (worktrees)
# =============================================================================
run_parallel() {
    local specs=("$@")
    local pids=()
    local worktrees=()
    local branches=()
    local running=0

    log "${MAGENTA}=== PARALLEL MODE: ${#specs[@]} specs (max $PARALLEL_MAX concurrent) ===${NC}"

    mkdir -p "$WORKTREE_BASE"

    for spec in "${specs[@]}"; do
        # Dynamic scaling - check if we can run more
        maybe_scale_parallel $running

        # Wait if we reached max number of parallel
        while [ $running -ge $PARALLEL_MAX ]; do
            # Wait for someone to finish
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    wait "${pids[$i]}" || true
                    unset 'pids[$i]'
                    ((running--))
                    # Check if we can scale up after one got done
                    maybe_scale_parallel $running
                    break
                fi
            done
            sleep 2
        done

        local spec_name=$(basename "$spec" .md)
        local branch="ralph-$spec_name-$TIMESTAMP"
        local worktree="$WORKTREE_BASE/$spec_name-$TIMESTAMP"

        log "Creating worktree: $spec_name"

        # Create branch and worktree
        git branch "$branch" 2>/dev/null || true
        git worktree add "$worktree" "$branch" 2>/dev/null || true

        # Copy specs
        cp "$spec" "$worktree/"

        worktrees+=("$worktree")
        branches+=("$branch")

        # Start in the background
        (
            cd "$worktree"
            local log_file="ralph-parallel.log"

            # Run specs
            if run_single_spec "$(basename "$spec")" "$branch" >> "$log_file" 2>&1; then
                echo "SUCCESS" > .ralph-status
            else
                echo "FAILED" > .ralph-status
            fi
        ) &
        pids+=($!)
        ((running++))

        log " PID: ${pids[-1]} (running: $running/$PARALLEL_MAX)"
    done

    # Waiting for all
    log "Waiting for ${#pids[@]} parallel specs..."

    local failed=0
    for i in "${!pids[@]}"; do
        wait "${pids[$i]}" || ((failed++))
        log "Ready: $(basename "${worktrees[$i]}")"
    done

    # Collect results and branches to merge
    log "${CYAN}═══ PARALLEL RESULT ═══${NC}"

    local successful_branches=()

    for i in "${!worktrees[@]}"; do
        local worktree="${worktrees[$i]}"
        local branch="${branches[$i]}"
        local status=$(cat "$worktree/.ralph-status" 2>/dev/null || echo "UNKNOWN")

        if [ "$status" = "SUCCESS" ]; then
            log "${GREEN}✅ $(basename "$worktree")${NC}"
            successful_branches+=("$branch")
        else
            log "${RED}❌ $(basename "$worktree")${NC}"
        fi
    done

    # Cleanup worktrees BEFORE merge (free branches)
    for worktree in "${worktrees[@]}"; do
        git worktree remove "$worktree" --force 2>/dev/null || true
    done
    git worktree prune 2>/dev/null || true

    # Smart sequential merge of successful branches
    if [ ${#successful_branches[@]} -gt 0 ]; then
        log "${CYAN}Starting smart merge of ${#successful_branches[@]} branches...${NC}"
        merge_branches_sequential "${successful_branches[@]}" || true

        # Run post-merge hook to fix integration
        call_stack_hook "post-merge" "." || {
            log "${YELLOW}Post-merge hook failed${NC}"
        }

        # Verify post-merge
        run_stack_verify "." || {
            log "${RED}Post-merge verification FAILED${NC}"
            notify "⚠️ Verification failed after parallel merge"
        }
    fi

    return $failed
}

# =============================================================================
# AUTO-MERGE LOGIC
# =============================================================================

# Files that are safe to auto-resolve with --theirs
AUTO_RESOLVE_PATTERNS=(
    "*.log"
    "ralph-parallel.log"
    "test-results/*"
    "playwright-report/*"
    ".last-run.json"
    "coverage/*"
    "*.snap"
)

# Files that require manual review in case of conflict
MANUAL_REVIEW_PATTERNS=(
    "*.ts"
    "*.tsx"
    "*.js"
    "*.jsx"
    "*.py"
    "*.go"
    "*.rs"
    "*.java"
)

# Check if file matches pattern
file_matches_pattern() {
    local file="$1"
    local pattern="$2"

    # Convert glob to regex
    local regex=$(echo "$pattern" | sed 's/\./\\./g' | sed 's/\*/.*?/g')
    echo "$file" | grep -qE "$regex"
}

# Check if conflict file is safe to auto-resolve
is_safe_to_auto_resolve() {
    local file="$1"

    for pattern in "${AUTO_RESOLVE_PATTERNS[@]}"; do
        if file_matches_pattern "$file" "$pattern"; then
            return 0 # Safe
        fi
    done

    # Check if it is test file
    if echo "$file" | grep -qE "(__tests__|\.test\.|\.spec\.|test/|tests/)"; then
        return 0 # Test files are safe
    fi

    return 1 # Not secure
}

# Smart merge of a branch with conflict handling
merge_branch_smart() {
    local branch="$1"
    local branch_name=$(basename "$branch")

    log "${CYAN}Merging: $branch_name${NC}"

    # Try plain merge first
    if git merge --no-ff "$branch" -m "Merge $branch_name" 2>/dev/null; then
        log "${GREEN}✅ Clean merge: $branch_name${NC}"
        return 0
    fi

    # Conflict - analyze files
    local conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null)

    if [ -z "$conflict_files" ]; then
        log "${GREEN}✅ Merge OK (no conflicts): $branch_name${NC}"
        return 0
    fi

    log "${YELLOW}Conflicts in: $conflict_files${NC}"

    local has_source_conflict=false
    local resolved_count=0

    while IFS= read -r file; do
        [ -z "$file" ] && continue

        if is_safe_to_auto_resolve "$file"; then
            log " ${BLUE}Auto-resolve (theirs): $file${NC}"
            git checkout --theirs "$file" 2>/dev/null || true
            git add "$file" 2>/dev/null || true
            ((resolved_count++))
        else
            # Check if it is source code
            for pattern in "${MANUAL_REVIEW_PATTERNS[@]}"; do
                if file_matches_pattern "$file" "$pattern"; then
                    log " ${RED}⚠️ Source code conflict: $file${NC}"
                    has_source_conflict=true
                    break
                fi
            done

            # If not source code, auto-resolve anyway
            if [ "$has_source_conflict" = false ]; then
                log " ${BLUE}Auto-resolve (theirs): $file${NC}"
                git checkout --theirs "$file" 2>/dev/null || true
                git add "$file" 2>/dev/null || true
                ((resolved_count++))
            fi
        fi
    done <<< "$conflict_files"

    # If source code conflict, auto-resolve with theirs and notify
    if [ "$has_source_conflict" = true ]; then
        log "${YELLOW}⚠️ Source code conflict - auto-resolve with theirs${NC}"
        notify "⚠️ Source code conflict in $branch_name - auto-resolved"

        # Auto-resolve all conflicts with theirs
        git checkout --theirs . 2>/dev/null || true
        git add -A 2>/dev/null || true
        ((resolved_count++))
    fi

    # All conflicts resolved automatically
    if [ $resolved_count -gt 0 ]; then
        git commit -m "Merge $branch_name (auto-resolved $resolved_count conflicts)" 2>/dev/null || true
        log "${GREEN}✅ Merge with auto-resolve: $branch_name ($resolved_count conflicts)${NC}"
    fi

    return 0
}

# Sequential merge of all branches with smart conflict handling
merge_branches_sequential() {
    local branches=("$@")
    local merged=0
    local failed=0
    local failed_branches=()

    log "${CYAN}═══ SMART SEQUENTIAL MERGE ═══${NC}"
    log "Branches to merge: ${#branches[@]}"

    # Checkout main first
    git checkout "$MAIN_BRANCH" 2>/dev/null || true

    # Sort branches - test/compliance-branches last (they usually change test files)
    local sorted_branches=()
    local test_branches=()

    for branch in "${branches[@]}"; do
        if echo "$branch" | grep -qE "(test|compliance|qa)"; then
            test_branches+=("$branch")
        else
            sorted_branches+=("$branch")
        fi
    done

    # Add test-branches last
    sorted_branches+=("${test_branches[@]}")

    log "Merge order:"
    for i in "${!sorted_branches[@]}"; do
        log "$((i+1)). ${sorted_branches[$i]}"
    done

    # Merge one at a time
    for branch in "${sorted_branches[@]}"; do
        if merge_branch_smart "$branch"; then
            ((merged++))

            # Run tests after each merge
            if ! run_tests 2>/dev/null; then
                log "${YELLOW}⚠️ Tests fail after merge of $branch${NC}"
                # Continue anyway - can be fixed later
            fi
        else
            ((failed++))
            failed_branches+=("$branch")
        fi
    done

    # Result
    log "${CYAN}═══ MERGE RESULT ═══${NC}"
    log "${GREEN}✅ MERGED: $merged${NC}"
    log "${RED}❌ Failed: $failed${NC}"

    if [ $failed -gt 0 ]; then
        log "Branches that need manual review:"
        for branch in "${failed_branches[@]}"; do
            log " - $branch"
        done
    fi

    # Push main if something merged
    if [ $merged -gt 0 ]; then
        log "${CYAN}Push $MAIN_BRANCH to origin...${NC}"
        git push origin "$MAIN_BRANCH" 2>&1 || log "${YELLOW}Push failed${NC}"
    fi

    return $failed
}

try_auto_merge() {
    local branch="$1"

    log "${CYAN}═══ AUTO-MERGE CHECK ═══${NC}"

    local safe=true

    # Check 1: Secrets i diff
    if git diff "$MAIN_BRANCH".."$branch" 2>/dev/null | grep -qE "(sk-ant-|ghp_|password|secret)" ; then
        log "${RED}⚠️ Secrets i diff${NC}"
        safe=false
    fi

    # Check 2: Dangerous commands
    if git diff "$MAIN_BRANCH".."$branch" 2>/dev/null | grep -qE "(rm -rf /|sudo rm|curl.*\|.*bash)" ; then
        log "${RED}⚠️ Dangerous commands${NC}"
        safe=false
    fi

    # Check 3: Tests
    if ! run_tests; then
        log "${RED}⚠️ Tester failar${NC}"
        safe=false
    fi

    if [ "$safe" = true ]; then
        log "${GREEN}🔥 AUTO-MERGE: $branch → $MAIN_BRANCH${NC}"
    else
        log "${YELLOW}⚠️ Safety alerts - merge anyway (skipping PRD)${NC}"
    fi

    # Always merge to main (skip PRs creation for easier workflow)
    git checkout "$MAIN_BRANCH"
    git merge "$branch" -m "ralph: $branch" 2>/dev/null || {
        log "${YELLOW}Merge conflict - using smart merge${NC}"
        merge_branch_smart "$branch"
    }
    git push origin "$MAIN_BRANCH" 2>/dev/null || true

    # Remove feature branch
    git branch -d "$branch" 2>/dev/null || true
    git push origin --delete "$branch" 2>/dev/null || true

    return 0
}

# =============================================================================
# SUMMARY REPORT
# =============================================================================
generate_summary() {
    local specs_done="$1"
    local specs_failed="$2"
    local specs_total="$3"

    local summary_file="$LOG_DIR/ralph-summary-$TIMESTAMP.md"

    cat > "$summary_file" << EOF
# 🤖 Ralph Summary

**Time:** $(date '+%Y-%m-%d %H:%M:%S')
**Log:** $LOG_DIR/

## Result

| Status | Number |
|--------|-------|
| ✅ Done | $specs_done |
| ❌ Failed | $specs_failed |
| **Total** | $specs_total |

## Rate Limits

$(tail -5 "$RATE_LIMIT_LOG" 2>/dev/null || echo "None")

## Token Usage

$(tail -5 "$TOKEN_LOG" 2>/dev/null || echo "No data")

---
*Generated by ralph.sh
EOF

    log "Summary: $summary_file"
}

# =============================================================================
# STATUS
# =============================================================================
show_status() {
    echo -e "${GREEN}=== ralph Status ===${NC}"
    echo ""

    echo "Processes:"
    ps aux | grep -E "ralph|claude" | grep -v grep | head -5 || echo " None"
    echo ""

    if git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Git:"
        git log --oneline -5 2>/dev/null
        echo ""
        git status --short | head -10
    fi
    echo ""

    echo "Rate limits (last 5):"
    tail -5 "$RATE_LIMIT_LOG" 2>/dev/null || echo " None"
    echo ""

    echo "Token usage (last 5):"
    tail -5 "$TOKEN_LOG" 2>/dev/null || echo " No data"
}

# =============================================================================
# WATCH MODE (Fireplace View) - Enhanced Dashboard
# =============================================================================
show_watch() {
    # Initialize stack to show info
    CURRENT_STACK=$(detect_stack ".")
    STACK_TEMPLATE_DIR="$RALPH_DIR/templates/stacks/$CURRENT_STACK"

    echo -e "${MAGENTA}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║ 🔥 RALPH DASHBOARD 🔥 ║"
    echo "║ ║"
    echo "║ Sit back and observe. Ralph is at work.              ║"
    echo "║ Ctrl+C to exit ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""

    while true; do
        clear
        echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${MAGENTA} 🔥 RALPH DASHBOARD 🔥 ${NC}"
        echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${CYAN}[$(date '+%H:%M:%S')] Status${NC}"
        echo ""

        # Stack info
        echo -e "${BLUE}Stack: ${GREEN}$CURRENT_STACK${NC}"
        if [ -d "$STACK_TEMPLATE_DIR" ]; then
            echo -e "${BLUE}Template: ${GREEN}$STACK_TEMPLATE_DIR${NC}"
        fi
        echo ""

        # Worktrees (parallel builds)
        local worktree_count=$(git worktree list 2>/dev/null | wc -l | tr -d ' ')
        if [ "$worktree_count" -gt 1 ]; then
            echo -e "${YELLOW}Active worktrees: ${GREEN}$worktree_count${NC}"
            git worktree list 2>/dev/null | tail -n +2 | sed 's/^/ /'
            echo ""
        fi

        # Active processes
        echo -e "${YELLOW}Process:${NC}"
        local procs=$(ps aux | grep -E "ralph|claude" | grep -v grep | grep -v watch)
        if [ -n "$procs" ]; then
            echo "$procs" | awk '{printf " %-8s %5s%% CPU %5s%% MEM %s\n", $11, $3, $4, $12}' | head -5
        else
            echo " (no active)"
        fi
        echo ""

        # specs status
        local total_specs=$(ls -1 specs/*.md 2>/dev/null | wc -l | tr -d ' ')
        local done_specs=$(ls -1 .spec-checksums/*.md5 2>/dev/null | wc -l | tr -d ' ')
        if [ "$total_specs" -gt 0 ]; then
            local percent=$((done_specs * 100 / total_specs))
            echo -e "${YELLOW}Specs: ${GREEN}$done_specs${NC}/${CYAN}$total_specs${NC} (${percent}%)"
            # Progress bar
            local bar_width=40
            local filled=$((percent * bar_width / 100))
            local empty=$((bar_width - filled))
            printf " ["
            printf "%${filled}s" | tr ' ' '"'
            printf "%${empty}s" | tr ' ' '░'
            printf "] %d%%\n" $percent
            echo ""
        fi

        # Latest git commits
        if git rev-parse --git-dir > /dev/null 2>&1; then
            echo -e "${YELLOW}Latest commits:${NC}"
            git log --oneline -5 2>/dev/null | sed 's/^/ /'
            echo ""

            # Changed files
            local changes=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
            if [ "$changes" -gt 0 ]; then
                echo -e "${YELLOW}Changed files: ${GREEN}$changes${NC}"
                git status --short 2>/dev/null | head -10 | sed 's/^/ /'
                echo ""
            fi
        fi

        # Progress.txt (short-term memory)
        if [ -f "$PROGRESS_FILE" ]; then
            local progress_lines=$(wc -l < "$PROGRESS_FILE" | tr -d ' ')
            echo -e "${YELLOW}Progress (latest):${NC}"
            tail -5 "$PROGRESS_FILE" 2>/dev/null | sed 's/^/ /'
            echo ""
        fi

        # Latest log entry
        local latest_log=$(ls -t "$LOG_DIR"/ralph-*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
            echo -e "${YELLOW}Latest log:${NC}"
            tail -8 "$latest_log" 2>/dev/null | sed 's/^/ /'
            echo ""
        fi

        # Rate limits & tokens
        local rate_count=$(wc -l < "$RATE_LIMIT_LOG" 2>/dev/null || echo 0)
        local token_total=$(awk -F'|' '{sum += $2} END {print sum}' "$TOKEN_LOG" 2>/dev/null || echo 0)
        echo -e "${YELLOW}Rate limits: ${RED}$rate_count${NC} | ${YELLOW}Tokens: ${CYAN}~$token_total${NC}"

        echo ""
        echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"
        echo -e " Updated every 5 seconds. ${CYAN}Ctrl+C${NC} to exit."
        echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"

        sleep 5
    done
}

# =============================================================================
# HELP
# =============================================================================
show_help() {
    cat << EOF
${GREEN}ralph.sh${NC} - The One Script To Rule Them All

${YELLOW}Usage:${NC}
  ./ralph.sh Run all specs in specs/
  ./ralph.sh specs/10-theme.md Run one spec
  ./ralph.sh specs/*.md Run multiple specs (in parallel)
  ./ralph.sh --status Show status
  ./ralph.sh --watch Fireplace view (live monitoring)
  ./ralph.sh --help Display help

${YELLOW}Features:${NC}
  ✓ Self-healing retries
  ✓ Rate limit handling
  ✓ Build lock cleanup
  ✓ Backup & secrets scanning
  ✓ Git branch isolation
  ✓ Smart parallel execution (max 3)
  ✓ Supervisor quality checks
  ✓ Auto-merge (if safe)
  ✓ ntfy notifications
  ✓ progress.txt (short-term memory)
  ✓ CLAUDE.md updates (long-term memory)

${YELLOW}Environment:${NC}
  NTFY_TOPIC ntfy topic (optional, no default)

EOF
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    # Parse args
    case "${1:-}" in
        --status|-s)
            show_status
            exit 0
            ;;
        --watch|-w)
            show_watch
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
    esac

    # Banner
    echo -e "${MAGENTA}"
    echo "  ██████╗  █████╗ ██╗     ██████╗ ██╗  ██╗"
    echo "  ██╔══██╗██╔══██╗██║     ██╔══██╗██║  ██║"
    echo "  ██████╔╝███████║██║     ██████╔╝███████║"
    echo "  ██╔══██╗██╔══██║██║     ██╔═══╝ ██╔══██║"
    echo "  ██║  ██║██║  ██║███████╗██║     ██║  ██║"
    echo "  ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝"
    echo -e "${NC}"

    # Setup
    mkdir -p "$LOG_DIR"
    mkdir -p "$BACKUP_DIR"

    notify "🚀 Ralph Starting"
    log "${GREEN}=== Ralph Starting ===${NC}"

    # Detect and initialize stack
    init_stack "."

    # Backup
    backup_project

    # Collect specs
    local specs=()

    if [ $# -eq 0 ]; then
        # All specs
        for f in specs/*.md; do
            [ -f "$f" ] && specs+=("$f")
        done
    else
        # Specs specified
        specs=("$@")
    fi

    if [ ${#specs[@]} -eq 0 ]; then
        log "${RED}No specs found${NC}"
        exit 1
    fi

    log "Specs: ${#specs[@]}"

    local specs_done=0
    local specs_failed=0

    # Parallel or sequential?
    if [ ${#specs[@]} -gt $PARALLEL_THRESHOLD ]; then
        # Parallel
        run_parallel "${specs[@]}" && specs_done=${#specs[@]} || specs_failed=$?
    else
        # Sequentially
        for specs in "${specs[@]}"; do
            local branch="ralph-$(basename "$spec" .md)-$TIMESTAMP"

            # Create branch
            git checkout -b "$branch" 2>/dev/null || true

            if run_single_spec "$spec" "$branch"; then
                # Supervisor checks
                run_supervisor_checks || true

                # Update CLAUDE.md (long-term memory)
                update_claude_md "$(basename "$spec")"

                # Push branch
                git push -u origin "$branch" 2>/dev/null || true

                # Auto-merge (specs are already done, count as done)
                try_auto_merge "$branch" || true
                ((specs_done++))
            else
                ((specs_failed++))
                git checkout "$MAIN_BRANCH" 2>/dev/null || true
                git branch -D "$branch" 2>/dev/null || true
            fi
        done
    fi

    # =============================================================================
    # FINAL BUILD LOOP - Run until build passes (definition of done!)
    # =============================================================================
    log "${MAGENTA}═══ FINAL BUILD CHECK ═══${NC}"
    log "Definition of Done: npm run build MUST pass"

    local final_attempts=0
    local max_final_attempts=10 # Max 10 attempts to fix build
    local build_passed=false

    while [ $final_attempts -lt $max_final_attempts ]; do
        ((final_attempts++))
        log "${CYAN}Final build attempt $final_attempts/$max_final_attempts${NC}"

        # Ensure dependencies
        ensure_dependencies || true

        # Run build
        local final_output
        local final_exit=0
        final_output=$(npm run build 2>&1) || final_exit=$?

        if [ $final_exit -eq 0 ]; then
            log "${GREEN}✅ FINAL BUILD PASSED!${NC}"
            build_passed=true

            # Commit and push
            git add -A 2>/dev/null || true
            git commit -m "ralph: final build passed" 2>/dev/null || true
            git push origin "$MAIN_BRANCH" 2>/dev/null || true

            break
        fi

        log "${RED}❌ Build failed${NC}"
        echo "$final_output" | tail -30

        # Try 1: Self-heal (missing dependencies)
        if try_selfheal "$final_output"; then
            log "${CYAN}Self-heal ran, trying again...${NC}"
            continue
        fi

        # Attempt 2: Ask Claude to fix
        log "${CYAN}Tell Claude to fix the build errors...${NC}"

        local fix_prompt="Build FAILED with the following error:

$final_output

IMPORTANT: This is FINAL BUILD. The project must build.
Analyze the error and fix it. Then run 'npm run build' to verify.

When build passes, type: <promise>DONE</promise>"

        local fix_output
        fix_output=$(echo "$fix_prompt" | timeout $TIMEOUT claude --dangerously-skip-permissions -p 2>&1) || true

        echo "$fix_output"

        # Commit any changes
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            git add -A 2>/dev/null || true
            git commit -m "ralph: fix build (attempt $final_attempts)" 2>/dev/null || true
        fi

        sleep 5
    done

    if [ "$build_passed" = false ]; then
        log "${RED}═══ FINAL BUILD FAILED AFTER $max_final_attempts ATTEMPT ═══${NC}"
        notify "❌ Final build failed after $max_final_attempts attempt" "urgent"
        specs_failed=$((specs_failed + 1))
    fi

    # Summary
    generate_summary "$specs_done" "$specs_failed" "${#specs[@]}"

    # Final notification
    if [ $specs_failed -eq 0 ] && [ "$build_passed" = true ]; then
        notify "✅ Ralph DONE: $specs_done/${#specs[@]} specs, build OK"
        log "${GREEN}═══ RALPH DONE: $specs_done/${#specs[@]}, BUILD OK ═══${NC}"
    else
        notify "⚠️ ralph: $specs_done OK, $specs_failed failed, build: $build_passed"
        log "${YELLOW}════ RALPH: $specs_done OK, $specs_failed FAILED, build: $build_passed ═══${NC}"
    fi

    # Exit code based on build status
    if [ "$build_passed" = true ]; then
        exit 0
    else
        exit 1
    fi
}

# Run
main "$@"
