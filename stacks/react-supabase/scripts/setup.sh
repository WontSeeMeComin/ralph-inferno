#!/bin/bash
# setup.sh - React + Supabase stack setup
#
# Automatically run by ralph at project start
# REQUIREMENT: Docker must run for Supabase

set -e

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

echo "🚀 React + Supabase Setup"
echo "========================="

# 1. Install dependencies if package.json exists
if [ -f "package.json" ]; then
    if [ ! -d "node_modules" ]; then
        echo "📦 Installing npm dependencies..."
        npm install
    fi
fi

# 2. Check Docker (REQUIRED)
echo "🐳 Checking Docker..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not installed"
    echo "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker info > /dev/null 2>&1; then
    echo "⚠️ Docker not running - trying to start..."

    # Try to start Docker
    if command -v systemctl &> /dev/null; then
        sudo systemctl start docker 2>/dev/null || true
        sleep 3
    fi

    # Check again
    if ! docker info > /dev/null 2>&1; then
        echo "❌ Could not start Docker"
        echo " Start Docker manually and run setup again"
        exit 1
    fi
fi
echo " ✅ Docker OK"

# 3. Playwright for E2E tests
echo "🎭 Checking Playwright..."
if [ ! -f "playwright.config.ts" ] && [ ! -f "playwright.config.js" ]; then
    echo " 📦 Installing Playwright..."
    npm install -D @playwright/test
    npx playwright install chromium --with-deps 2>/dev/null || npx playwright install chromium

    # Create minimal config if missing
    cat > playwright.config.ts << 'EOF'
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  use: {
    baseURL: 'http://localhost:5173',
    headless: true,
  },
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: true,
  },
});
EOF

    # Create e2e folder (Claude should create real tests)
    mkdir -p e2e
    cat > e2e/.gitkeep << 'EOF'
# E2E tests should be created by Claude
# See CLAUDE.md for E2E test requirements
# Tests should verify the entire user flow, not just that the page loads
EOF
    echo " ✅ Playwright installed (Claude creates E2E tests)"
else
    echo " ✅ Playwright config exists"
fi

# 3. Supabase setup
if [ -d "supabase" ] || [ -f "supabase/config.toml" ]; then
    echo "📊 Starting Supabase..."

    # Start if not already running
    if ! supabase status > /dev/null 2>&1; then
        supabase start
    fi

    # Get credentials
    API_URL=$(supabase status 2>/dev/null | grep -E "API URL|Project URL" | awk '{print $NF}' | head -1)
    ANON_KEY=$(supabase status 2>/dev/null | grep -E "anon key|Publishable" | awk '{print $NF}' | head -1)

    if [ -z "$API_URL" ]; then
        API_URL="http://127.0.0.1:54321"
    fi

    # Update .env
    if [ -n "$ANON_KEY" ]; then
        echo "📝 Updating .env..."

        # Delete old SUPABASE lines
        if [ -f ".env" ]; then
            grep -v "SUPABASE" .env > .env.tmp 2>/dev/null || true
            mv .env.tmp .env
        fi

        echo "VITE_SUPABASE_URL=$API_URL" >> .env
        echo "VITE_SUPABASE_ANON_KEY=$ANON_KEY" >> .env

        echo "✅ .env configured"
    fi

    # Run migrations if available
    if [ -d "supabase/migrations" ] && [ -n "$(ls supabase/migrations/*.sql 2>/dev/null)" ]; then
        echo "📊 Run database migration..."
        supabase db reset --no-seed 2>/dev/null || supabase db reset
    fi
fi

# 4. ntfy for notifications
echo "📣 Checking ntfy..."
RALPH_CONFIG="$HOME/.ralph-vm"
if [ -f "$RALPH_CONFIG" ]; then
    source "$RALPH_CONFIG"
fi

if [ -z "${NTFY_TOPIC:-}" ]; then
    # Generate unique topic based on project + timestamp
    PROJECT_NAME=$(basename "$PROJECT_DIR")
    RANDOM_SUFFIX=$(head -c 4 /dev/urandom | xxd -p)
    NTFY_TOPIC="ralph-${PROJECT_NAME}-${RANDOM_SUFFIX}"

    echo " 📝 Creating ntfy topic: $NTFY_TOPIC"
    echo "NTFY_TOPIC=$NTFY_TOPIC" >> "$RALPH_CONFIG"

    echo " 💡 Subscribe to: https://ntfy.sh/$NTFY_TOPIC"
    echo " 📱 Or in the ntfy app: $NTFY_TOPIC"
else
    echo " ✅ ntfy topic: $NTFY_TOPIC"
fi

# Send test note
if command -v curl &> /dev/null; then
    curl -s -d "ralph setup ready for $(basename $PROJECT_DIR)" "ntfy.sh/${NTFY_TOPIC}" > /dev/null 2>&1 || true
fi

echo ""
echo "✅ Setup ready!"
echo ""
echo "📣 ntfy: https://ntfy.sh/${NTFY_TOPIC}"
