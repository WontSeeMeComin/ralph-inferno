#!/bin/bash
# llm.sh - Multi-provider LLM inference wrapper (LM Studio, Ollama, OpenRouter, Claude)
# Source this file: source lib/llm.sh

LLM_LOADED=1

# Avoid clobbering Ralph's global LIB_DIR variable.
LLM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LLM_LIB_DIR/llm-config.sh"

_llm_log() {
    if declare -f log >/dev/null 2>&1; then
        log "$1"
    else
        echo "$1"
    fi
}

_llm_sleep_backoff() {
    local attempt="$1"
    # 1, 2, 4, 8...
    local seconds=$((2 ** (attempt - 1)))
    [ "$seconds" -gt 30 ] && seconds=30
    sleep "$seconds"
}

_llm_normalize_openai_base_url() {
    local base="$1"
    # Allow users to pass either http://host:1234 or http://host:1234/v1
    if echo "$base" | grep -q "/v1$"; then
        echo "$base"
    else
        echo "${base%/}/v1"
    fi
}

llm_healthcheck_lmstudio() {
    local base
    base=$(_llm_normalize_openai_base_url "$(llm_lmstudio_base_url)")
    curl -sS --connect-timeout 1 --max-time 3 "$base/models" >/dev/null 2>&1
}

llm_healthcheck_openrouter() {
    local key
    key="$(llm_openrouter_api_key)"
    [ -n "$key" ] || return 1
    local base
    base=$(_llm_normalize_openai_base_url "$(llm_openrouter_base_url)")
    curl -sS --connect-timeout 2 --max-time 5 \
        -H "Authorization: Bearer $key" \
        "$base/models" >/dev/null 2>&1
}

llm_healthcheck_ollama() {
    local host
    host="$(llm_ollama_host)"
    curl -sS --connect-timeout 1 --max-time 3 "$host/api/tags" >/dev/null 2>&1
}

llm_healthcheck_claude() {
    command -v claude >/dev/null 2>&1
}

llm_select_provider() {
    local requested
    requested="$(llm_provider)"

    case "$requested" in
        lmstudio)
            llm_healthcheck_lmstudio && echo "lmstudio" || echo "$(llm_fallback_provider)"
            ;;
        ollama)
            llm_healthcheck_ollama && echo "ollama" || echo "$(llm_fallback_provider)"
            ;;
        openrouter)
            llm_healthcheck_openrouter && echo "openrouter" || echo "$(llm_fallback_provider)"
            ;;
        claude)
            echo "claude"
            ;;
        auto|*)
            # Prefer local first
            llm_healthcheck_lmstudio && echo "lmstudio" && return 0
            llm_healthcheck_ollama && echo "ollama" && return 0
            llm_healthcheck_openrouter && echo "openrouter" && return 0
            echo "claude"
            ;;
    esac
}

_llm_openai_chat() {
    local base_url="$1"   # normalized /v1
    local api_key="$2"    # may be empty for local
    local model="$3"
    local prompt="$4"

    local timeout_s
    timeout_s="$(llm_timeout_seconds)"

    # Build JSON request using jq for correct escaping
    local body
    body=$(jq -n --arg model "$model" --arg prompt "$prompt" ' {
        model: $model,
        messages: [ { role: "user", content: $prompt } ],
        temperature: 0.2
      } ')

    local headers=(-H "Content-Type: application/json")
    if [ -n "$api_key" ]; then
        headers+=(-H "Authorization: Bearer $api_key")
    fi

    curl -sS --fail-with-body \
        --connect-timeout 5 --max-time "$timeout_s" \
        "${headers[@]}" \
        -d "$body" \
        "$base_url/chat/completions"
}

_llm_ollama_chat() {
    local host="$1"
    local model="$2"
    local prompt="$3"
    local timeout_s
    timeout_s="$(llm_timeout_seconds)"

    local body
    body=$(jq -n --arg model "$model" --arg prompt "$prompt" '{
        model: $model,
        stream: false,
        messages: [ { role: "user", content: $prompt } ]
      }')

    curl -sS --fail-with-body \
        --connect-timeout 5 --max-time "$timeout_s" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "$host/api/chat"
}

llm_generate() {
    # Generates plain text (returns on stdout)
    local prompt="$1"
    local purpose="${2:-generic}" # for logs

    local provider
    provider="$(llm_select_provider)"

    local retries
    retries="$(llm_max_retries)"
    local attempt=1

    while [ $attempt -le $((retries + 1)) ]; do
        local raw exit_code=0

        case "$provider" in
            lmstudio)
                local base
                base=$(_llm_normalize_openai_base_url "$(llm_lmstudio_base_url)")
                raw=$(_llm_openai_chat "$base" "" "$(llm_lmstudio_model)" "$prompt" 2>&1) || exit_code=$?
                if [ $exit_code -eq 0 ]; then
                    echo "$raw" | jq -r '.choices[0].message.content // empty'
                    return 0
                fi
                ;;

            openrouter)
                local base key
                base=$(_llm_normalize_openai_base_url "$(llm_openrouter_base_url)")
                key="$(llm_openrouter_api_key)"
                raw=$(_llm_openai_chat "$base" "$key" "$(llm_openrouter_model)" "$prompt" 2>&1) || exit_code=$?
                if [ $exit_code -eq 0 ]; then
                    echo "$raw" | jq -r '.choices[0].message.content // empty'
                    return 0
                fi
                ;;

            ollama)
                local host
                host="$(llm_ollama_host)"
                raw=$(_llm_ollama_chat "$host" "$(llm_ollama_model)" "$prompt" 2>&1) || exit_code=$?
                if [ $exit_code -eq 0 ]; then
                    echo "$raw" | jq -r '.message.content // empty'
                    return 0
                fi
                ;;

            claude|*)
                # Claude Code CLI (agentic) - use as safe fallback
                local timeout_s
                timeout_s="$(llm_timeout_seconds)"
                raw=$(echo "$prompt" | timeout "$timeout_s" claude --dangerously-skip-permissions -p 2>&1) || exit_code=$?
                if [ $exit_code -eq 0 ]; then
                    echo "$raw"
                    return 0
                fi
                ;;
        esac

        # Retry handling
        _llm_log "[llm] $purpose failed (provider=$provider, attempt=$attempt, exit=$exit_code)"

        # If rate-limit helper exists, prefer it
        if declare -f is_rate_limited >/dev/null 2>&1 && declare -f handle_rate_limit >/dev/null 2>&1; then
            if is_rate_limited "$raw"; then
                handle_rate_limit "llm:$purpose:$provider" 120
                attempt=$((attempt + 1))
                continue
            fi
        fi

        _llm_sleep_backoff "$attempt"
        attempt=$((attempt + 1))
    done

    return 1
}

llm_generate_to_file() {
    local prompt="$1"
    local file_path="$2"
    local purpose="${3:-write_file}"

    local content
    content=$(llm_generate "$prompt" "$purpose") || return 1

    mkdir -p "$(dirname "$file_path")"
    printf "%s\n" "$content" > "$file_path"
}
