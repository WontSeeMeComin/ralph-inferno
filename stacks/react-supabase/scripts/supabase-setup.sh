#!/bin/bash
# supabase-setup.sh - Automatic Supabase setup for ralph projects
#
# Run this at the beginning of E1 if the project uses Supabase

set -e

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

echo "🔧 Supabase Setup"
echo "================="

# Check if Supabase is already initialized
if [ -d "supabase" ] && [ -f "supabase/config.toml" ]; then
    echo "✅ Supabase already initialized"
else
    echo "📦 Initializing Supabase..."
    supabase init
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Start Docker first."
    exit 1
fi

# Check if Supabase is already running
if supabase status > /dev/null 2>&1; then
    echo "✅ Supabase is already running"
else
    echo "🚀 Starting local Supabase..."
    supabase start
fi

# Get credentials
echo ""
echo "📋 Supabase Status:"
supabase status

# Extract credentials
API_URL=$(supabase status | grep "API URL" | awk {print })
ANON_KEY=$(supabase status | grep "anon key" | awk {print })

if [ -z "$API_URL" ]; then
    API_URL="http://127.0.0.1:54321"
fi

if [ -z "$ANON_KEY" ]; then
    ANON_KEY=$(supabase status | grep "Publishable" | awk {print })
fi

# Create/update .env
echo ""
echo "📝 Updating .env..."

if [ -f ".env" ]; then
    # Backup existing
    cp .env .env.backup
    # Delete old Supabase variables
    grep -v "SUPABASE" .env > .env.tmp || true
    mv .env.tmp .env
fi

cat >> .env << ENVEOF
QUICK_SUPABASE_URL=$API_URL
VITE_SUPABASE_ANON_KEY=$ANON_KEY
ENVEOF

echo "✅ .env updated with:"
echo "VITE_SUPABASE_URL=$API_URL"
echo "VITE_SUPABASE_ANON_KEY=$ANON_KEY"

# Run migration if schema exists
if [ -f "supabase/schema.sql" ]; then
    echo ""
    echo "📊 Run database migration..."
    
    # Create migration file if it does not exist
    MIGRATION_FILE="supabase/migrations/$(date +%Y%m%d%H%M%S)_init.sql"
    if [ ! -d "supabase/migrations" ] || [ -z "$(ls supabase/migrations/*.sql 2>/dev/null)" ]; then
        mkdir -p supabase/migrations
        cp supabase/schema.sql "$MIGRATION_FILE"
        echo " Created migration: $MIGRATION_FILE"
    fi
    
    supabase db reset
    echo "✅ Database migrated"
fi

echo ""
echo "🎉 Supabase setup ready!"
echo ""
echo "Next steps:"
echo " - Launch your app: npm run dev"
echo " - Supabase Studio: http://127.0.0.1:54323"
echo " - Mailpit (for auth emails): http://127.0.0.1:54324"
