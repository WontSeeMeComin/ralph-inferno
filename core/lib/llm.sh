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

_llm_base64_file() {
    local file_path="$1"
    # GNU coreutils: base64 -w 0, macOS/BSD: base64 with no wrap by default
    if base64 -w 0 "$file_path" >/dev/null 2>&1; then
        base64 -w 0 "$file_path"
    else
        base64 "$file_path" | tr -d '\n'
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

_llm_select_provider_impl() {
    local requested="$1"
    local fallback="$2"

    _select_auto() {
        # Prefer local first
        llm_healthcheck_lmstudio && echo "lmstudio" && return 0
        llm_healthcheck_ollama && echo "ollama" && return 0
        llm_healthcheck_openrouter && echo "openrouter" && return 0
        llm_healthcheck_claude && echo "claude" && return 0
        echo "claude"
    }

    case "$requested" in
        lmstudio)
            if llm_healthcheck_lmstudio; then
                echo "lmstudio"
            elif [ "$fallback" = "ollama" ] && llm_healthcheck_ollama; then
                echo "ollama"
            elif [ "$fallback" = "openrouter" ] && llm_healthcheck_openrouter; then
                echo "openrouter"
            elif [ "$fallback" = "claude" ] && llm_healthcheck_claude; then
                echo "claude"
            else
                _select_auto
            fi
            ;;
        ollama)
            if llm_healthcheck_ollama; then
                echo "ollama"
            elif [ "$fallback" = "lmstudio" ] && llm_healthcheck_lmstudio; then
                echo "lmstudio"
            elif [ "$fallback" = "openrouter" ] && llm_healthcheck_openrouter; then
                echo "openrouter"
            elif [ "$fallback" = "claude" ] && llm_healthcheck_claude; then
                echo "claude"
            else
                _select_auto
            fi
            ;;
        openrouter)
            if llm_healthcheck_openrouter; then
                echo "openrouter"
            elif [ "$fallback" = "lmstudio" ] && llm_healthcheck_lmstudio; then
                echo "lmstudio"
            elif [ "$fallback" = "ollama" ] && llm_healthcheck_ollama; then
                echo "ollama"
            elif [ "$fallback" = "claude" ] && llm_healthcheck_claude; then
                echo "claude"
            else
                _select_auto
            fi
            ;;
        claude)
            # Don't hard-fail if Claude isn't installed; fall back.
            if llm_healthcheck_claude; then
                echo "claude"
            else
                _select_auto
            fi
            ;;
        auto|*)
            _select_auto
            ;;
    esac
}

llm_select_provider() {
    _llm_select_provider_impl "$(llm_provider)" "$(llm_fallback_provider)"
}

llm_select_provider_for_use_case() {
    local use_case="${1:-}"
    _llm_select_provider_impl "$(llm_provider_for_use_case "$use_case")" "$(llm_fallback_provider_for_use_case "$use_case")"
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

_llm_openai_chat_with_image() {
    local base_url="$1"   # normalized /v1
    local api_key="$2"    # may be empty for local
    local model="$3"
    local prompt="$4"
    local image_path="$5"

    local timeout_s
    timeout_s="$(llm_timeout_seconds)"

    local b64
    b64=$(_llm_base64_file "$image_path")

    # OpenAI-compatible multimodal message
    local body
    body=$(jq -n --arg model "$model" --arg prompt "$prompt" --arg b64 "$b64" ' {
        model: $model,
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: $prompt },
              { type: "image_url", image_url: { url: ("data:image/png;base64," + $b64) } }
            ]
          }
        ],
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

_llm_ollama_chat_with_image() {
    local host="$1"
    local model="$2"
    local prompt="$3"
    local image_path="$4"
    local timeout_s
    timeout_s="$(llm_timeout_seconds)"

    local b64
    b64=$(_llm_base64_file "$image_path")

    local body
    body=$(jq -n --arg model "$model" --arg prompt "$prompt" --arg b64 "$b64" '{
        model: $model,
        stream: false,
        messages: [ { role: "user", content: $prompt, images: [ $b64 ] } ]
      }')

    curl -sS --fail-with-body \
        --connect-timeout 5 --max-time "$timeout_s" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "$host/api/chat"
}

llm_generate_vision() {
    # Generates plain text from a prompt + image
    local prompt="$1"
    local image_path="$2"
    local purpose="${3:-vision}"
    local use_case="${4:-vision}"

    [ -f "$image_path" ] || return 1

    local provider
    provider="$(llm_select_provider_for_use_case "$use_case")"

    local retries
    retries="$(llm_max_retries)"
    local attempt=1

    while [ $attempt -le $((retries + 1)) ]; do
        local raw exit_code=0

        case "$provider" in
            lmstudio)
                local base
                base=$(_llm_normalize_openai_base_url "$(llm_lmstudio_base_url)")
                raw=$(_llm_openai_chat_with_image "$base" "" "$(llm_lmstudio_vision_model)" "$prompt" "$image_path" 2>&1) || exit_code=$?
                if [ $exit_code -eq 0 ]; then
                    echo "$raw" | jq -r '.choices[0].message.content // empty'
                    return 0
                fi
                ;;

            openrouter)
                local base key
                base=$(_llm_normalize_openai_base_url "$(llm_openrouter_base_url)")
                key="$(llm_openrouter_api_key)"
                raw=$(_llm_openai_chat_with_image "$base" "$key" "$(llm_openrouter_model)" "$prompt" "$image_path" 2>&1) || exit_code=$?
                if [ $exit_code -eq 0 ]; then
                    echo "$raw" | jq -r '.choices[0].message.content // empty'
                    return 0
                fi
                ;;

            ollama)
                local host
                host="$(llm_ollama_host)"
                raw=$(_llm_ollama_chat_with_image "$host" "$(llm_ollama_model)" "$prompt" "$image_path" 2>&1) || exit_code=$?
                if [ $exit_code -eq 0 ]; then
                    echo "$raw" | jq -r '.message.content // empty'
                    return 0
                fi
                ;;

            claude|*)
                return 1
                ;;
        esac

        _llm_log "[llm] $purpose failed (provider=$provider, attempt=$attempt, exit=$exit_code)"
        _llm_sleep_backoff "$attempt"
        attempt=$((attempt + 1))
    done

    return 1
}

llm_generate() {
    # Generates plain text (returns on stdout)
    local prompt="$1"
    local purpose="${2:-generic}" # for logs
    local use_case="${3:-execute}"

    local provider
    provider="$(llm_select_provider_for_use_case "$use_case")"

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
    local use_case="${4:-execute}"

    local content
    content=$(llm_generate "$prompt" "$purpose" "$use_case") || return 1

    mkdir -p "$(dirname "$file_path")"
    printf "%s\n" "$content" > "$file_path"
}
