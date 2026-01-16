#!/bin/bash
# llm-smoke-test.sh - Quick validation of configured LLM provider
#
# Usage examples:
#   RALPH_LLM_PROVIDER=lmstudio RALPH_LMSTUDIO_BASE_URL=http://192.168.12.239:1234 ./llm-smoke-test.sh
#   RALPH_LLM_PROVIDER=ollama RALPH_OLLAMA_HOST=http://localhost:11434 ./llm-smoke-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

source "$LIB_DIR/llm.sh"

echo "[llm-smoke] config file: ${CONFIG_FILE:-.ralph/config.json}"
echo "[llm-smoke] requested provider: $(llm_provider)"
echo "[llm-smoke] selected provider:  $(llm_select_provider)"

echo "[llm-smoke] testing generation..."

PROMPT="Return exactly the string: OK"
OUT=$(llm_generate "$PROMPT" "smoke_test" || true)

echo "[llm-smoke] output (first 200 chars):"
echo "$OUT" | head -c 200
echo ""

if echo "$OUT" | grep -q "OK"; then
  echo "[llm-smoke] PASS"
  exit 0
fi

echo "[llm-smoke] FAIL (did not see 'OK')"
exit 1
