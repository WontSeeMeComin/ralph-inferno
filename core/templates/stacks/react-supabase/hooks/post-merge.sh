#!/bin/bash
# post-merge.sh - Run after parallel worktree merge
#
# Ensures that all components are properly integrated

set -e

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

echo "🔗 Post-merge integration check..."
echo ""

ISSUES=0

# 1. Find all components missing exports
echo "Checking exports..."
for dir in src/components/*/; do
    if [ -d "$dir" ]; then
        index_file="${dir}index.ts"

        # Create index.ts if it is missing
        if [ ! -f "$index_file" ]; then
            touch "$index_file"
            echo " Created $index_file"
        fi

        # Check each component
        for component in "$dir"*.tsx; do
            if [ -f "$component" ]; then
                name=$(basename "$component" .tsx)

                # Skip index
                if [ "$name" = "index" ]; then
                    continue
                fi

                # Add export if missing
                if ! grep -q "export.*$name" "$index_file" 2>/dev/null; then
                    echo "export { $name } from './$name'" >> "$index_file"
                    echo " ✅ Add export for $name"
                    ISSUES=$((ISSUES + 1))
                fi
            fi
        done
    fi
done

# 2. Same for hooks
if [ -d "src/hooks" ]; then
    index_file="src/hooks/index.ts"
    if [ ! -f "$index_file" ]; then
        touch "$index_file"
    fi

    for hook in src/hooks/*.ts; do
        if [ -f "$hook" ]; then
            name=$(basename "$hook" .ts)
            if [ "$name" = "index" ]; then
                continue
            fi

            if ! grep -q "$name" "$index_file" 2>/dev/null; then
                echo "export * from './$name'" >> "$index_file"
                echo " ✅ Add export for $name hook"
                ISSUES=$((ISSUES + 1))
            fi
        fi
    done
fi

# 3. Same for contexts
if [ -d "src/contexts" ]; then
    index_file="src/contexts/index.ts"
    if [ ! -f "$index_file" ]; then
        touch "$index_file"
    fi

    for ctx in src/contexts/*.tsx; do
        if [ -f "$ctx" ]; then
            name=$(basename "$ctx" .tsx)
            if [ "$name" = "index" ]; then
                continue
            fi

            if ! grep -q "$name" "$index_file" 2>/dev/null; then
                echo "export * from './$name'" >> "$index_file"
                echo " ✅ Add export for $name context"
                ISSUES=$((ISSUES + 1))
            fi
        fi
    done
fi

echo ""
if [ $ISSUES -gt 0 ]; then
    echo "🔧 Fixed $ISSUES missing exports"

    # Run build to verify
    echo ""
    echo "Verifying build..."
    if npm run build > /dev/null 2>&1; then
        echo "✅ Build OK after fixes"
    else
        echo "❌ Build FAILED - manual fix needed"
        exit 1
    fi
else
    echo "✅ All exports OK"
fi
