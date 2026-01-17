#!/bin/bash
# verify.sh - Verification for React + Supabase stack
#
# Runs at HARD STOP to ensure everything is working
# Exit 0 = OK, Exit 1 = Error

set -e

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

# Use project folder for temp files (avoid /tmp permission issues)
TEMP_DIR="${PROJECT_DIR}/.ralph-temp"
mkdir -p "$TEMP_DIR"

echo "🔍 Verifying React + Supabase project..."
echo ""

ERRORS=0

# 1. Build-test
echo "1️⃣ Build-test..."
if npm run build > "$TEMP_DIR/build.log" 2>&1; then
    echo " ✅ Build OK"
else
    echo " ❌ Build FAILED"
    tail -20 "$TEMP_DIR/build.log"
    ERRORS=$((ERRORS + 1))
fi

# 2. TypeScript error
echo "2️⃣ TypeScript-check..."
if npx tsc --noEmit > "$TEMP_DIR/tsc.log" 2>&1; then
    echo " ✅ TypeScript OK"
else
    echo " ❌ TypeScript error"
    tail -10 "$TEMP_DIR/tsc.log"
    ERRORS=$((ERRORS + 1))
fi

# 3. Check that all index.ts have correct exports
echo "3️⃣ Export-check..."
MISSING_EXPORTS=0

for dir in src/components/*/; do
    if [ -d "$dir" ]; then
        index_file="$dir/index.ts"
        if [ -f "$index_file" ]; then
            # Find all .tsx files in the folder (exclude .test.tsx files)
            for component in "$dir"*.tsx; do
                if [ -f "$component" ]; then
                    # Skip test files
                    case "$component" in
                        *.test.tsx|*.spec.tsx) continue ;;
                    esac
                    name=$(basename "$component" .tsx)
                    if ! grep -q "export.*$name" "$index_file" 2>/dev/null; then
                        echo " ⚠️ Missing export: $name in $index_file"
                        MISSING_EXPORTS=$((MISSING_EXPORTS + 1))
                    fi
                fi
            done
        fi
    fi
done

if [ $MISSING_EXPORTS -eq 0 ]; then
    echo " ✅ All components exported"
else
    echo " ❌ $MISSING_EXPORTS was missing exports"
    ERRORS=$((ERRORS + 1))
fi

# 4. Supabase connection (REQUIRED - must run)
echo "4️⃣ Supabase-check..."
if [ -f ".env" ]; then
    source .env 2>/dev/null || true
    if [ -n "$VITE_SUPABASE_URL" ] && [ "$VITE_SUPABASE_URL" != "│" ]; then
        if curl -s "$VITE_SUPABASE_URL/rest/v1/" -H "apikey: $VITE_SUPABASE_ANON_KEY" > /dev/null 2>&1; then
            echo " ✅ Supabase connection OK"
        else
            echo " ❌ Supabase not responding - run 'supabase start'"
            ERRORS=$((ERRORS + 1))
        fi
    else
        echo " ❌ VITE_SUPABASE_URL not set - run setup.sh"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo " ❌ No .env file - run setup.sh"
    ERRORS=$((ERRORS + 1))
fi

# 5. Dev-server test
echo "5️⃣ Dev-server test..."
npm run dev > "$TEMP_DIR/dev.log" 2>&1 &
DEV_PID=$!
sleep 5

if curl -s http://localhost:5173 > /dev/null 2>&1; then
    echo " ✅ Dev-server OK"
else
    echo " ❌ Dev-server not responding"
    ERRORS=$((ERRORS + 1))
fi

# 6. E2E tests with Playwright (if available)
echo "6️⃣ E2E tests..."
if [ -f "playwright.config.ts" ] || [ -f "playwright.config.js" ]; then
    # Install browsers if missing
    if ! npx playwright --version > /dev/null 2>&1; then
        echo " 📦 Installing Playwright..."
        npm install -D @playwright/test
        npx playwright install chromium
    fi

    # Run E2E tests (dev server is already running)
    if npx playwright test --reporter=list > "$TEMP_DIR/e2e.log" 2>&1; then
        echo " ✅ E2E tests OK"
    else
        echo " ❌ E2E tests FAILED"
        tail -30 "$TEMP_DIR/e2e.log"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo " ⚠️ No E2E tests (playwright.config missing)"
    echo " 💡 Create E2E tests for full verification"
fi

# Close dev server
kill $DEV_PID 2>/dev/null || true

# Clean temp files
rm -rf "$TEMP_DIR" 2>/dev/null || true

# Result
echo ""
echo "================================"
if [ $ERRORS -eq 0 ]; then
    echo "✅ VERIFICATION OK"
    exit 0
else
    echo "❌ VERIFICATION FAILED ($ERRORS errors)"
    exit 1
fi
