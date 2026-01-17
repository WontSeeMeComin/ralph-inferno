#!/bin/bash
# post-create.sh - Run after a new file is created
#
# Automatically adds exports to index.ts for new components/hooks
#
# Usage: post-create.sh <created-file>

set -e

FILE="$1"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    exit 0
fi

# Only handle .tsx and .ts files (not index.ts)
if [[ ! "$FILE" =~ \.(tsx|ts)$ ]] || [[ "$FILE" =~ index\.ts$ ]]; then
    exit 0
fi

DIR=$(dirname "$FILE")
BASENAME=$(basename "$FILE")
NAME="${BASENAME%.*}"  # Remove extension
INDEX_FILE="$DIR/index.ts"

# Check if it is a component/hook folder
if [[ "$DIR" =~ src/components/ ]] || [[ "$DIR" =~ src/hooks ]] || [[ "$DIR" =~ src/contexts ]]; then

    # Create index.ts if it does not exist
    if [ ! -f "$INDEX_FILE" ]; then
        touch "$INDEX_FILE"
    fi

    # Check if the export already exists
    if grep -q "export.*{.*$NAME.*}" "$INDEX_FILE" 2>/dev/null || \
       grep -q "export \* from './$NAME'" "$INDEX_FILE" 2>/dev/null; then
        # Already exported
        exit 0
    fi

    # Add export
    # Use named export for .tsx, namespace for .ts
    if [[ "$FILE" =~ \.tsx$ ]]; then
        echo "export { $NAME } from './$NAME'" >> "$INDEX_FILE"
    else
        # For hooks/utilities, export everything
        echo "export * from './$NAME'" >> "$INDEX_FILE"
    fi

    echo "📦 Auto-exported $NAME in $INDEX_FILE"
fi
