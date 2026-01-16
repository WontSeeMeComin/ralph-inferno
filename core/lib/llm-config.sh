#!/bin/bash
# llm-config.sh - Centralized LLM/provider configuration
# Source this file: source lib/llm-config.sh

LLM_CONFIG_LOADED=1

# Config file (JSON) written by ralph-inferno install/update
CONFIG_FILE="${RALPH_CONFIG:-.ralph/config.json}"

# Read from JSON config with optional default
_cfg_json() {
    local jq_expr="$1"        # e.g. '.llm.provider'
    local default_value="${2:-}"

    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC2016
        local val
        val=$(jq -r "$jq_expr // empty" "$CONFIG_FILE" 2>/dev/null || true)
        if [ -n "$val" ] && [ "$val" != "null" ]; then
            echo "$val"
            return 0
        fi
    fi

    echo "$default_value"
}

_cfg_env_or_json() {
    local env_name="$1"
    local jq_expr="$2"
    local default_value="${3:-}"

    # Indirect expansion: ${!env_name}
    local env_val="${!env_name:-}"
    if [ -n "$env_val" ]; then
        echo "$env_val"
        return 0
    fi

    _cfg_json "$jq_expr" "$default_value"
}

# Provider selection
llm_provider() {
    # auto | lmstudio | ollama | openrouter | claude
    _cfg_env_or_json "RALPH_LLM_PROVIDER" ".llm.provider" "claude"
}

llm_fallback_provider() {
    _cfg_env_or_json "RALPH_LLM_FALLBACK_PROVIDER" ".llm.fallback_provider" "claude"
}

# Timeouts / retries
llm_timeout_seconds() {
    _cfg_env_or_json "RALPH_LLM_TIMEOUT_SECONDS" ".llm.timeout_seconds" "120"
}

llm_max_retries() {
    _cfg_env_or_json "RALPH_LLM_MAX_RETRIES" ".llm.max_retries" "2"
}

# Agent mode (how specs are executed)
llm_agent_mode() {
    # claude | llm
    _cfg_env_or_json "RALPH_AGENT_MODE" ".llm.agent_mode" "claude"
}

# LM Studio (OpenAI-compatible)
llm_lmstudio_base_url() {
    _cfg_env_or_json "RALPH_LMSTUDIO_BASE_URL" ".llm.lmstudio.base_url" "http://localhost:1234"
}

llm_lmstudio_model() {
    _cfg_env_or_json "RALPH_LMSTUDIO_MODEL" ".llm.lmstudio.model" "qwen/qwen3-next-80b"
}

# OpenRouter (OpenAI-compatible)
llm_openrouter_base_url() {
    _cfg_env_or_json "RALPH_OPENROUTER_BASE_URL" ".llm.openrouter.base_url" "https://openrouter.ai/api/v1"
}

llm_openrouter_model() {
    _cfg_env_or_json "RALPH_OPENROUTER_MODEL" ".llm.openrouter.model" "openai/gpt-4o-mini"
}

llm_openrouter_api_key() {
    # Prefer OPENROUTER_API_KEY but allow a Ralph-prefixed override
    if [ -n "${RALPH_OPENROUTER_API_KEY:-}" ]; then
        echo "$RALPH_OPENROUTER_API_KEY"
        return 0
    fi
    if [ -n "${OPENROUTER_API_KEY:-}" ]; then
        echo "$OPENROUTER_API_KEY"
        return 0
    fi
    _cfg_json ".llm.openrouter.api_key" ""
}

# Ollama (native HTTP)
llm_ollama_host() {
    _cfg_env_or_json "RALPH_OLLAMA_HOST" ".llm.ollama.host" "http://localhost:11434"
}

llm_ollama_model() {
    _cfg_env_or_json "RALPH_OLLAMA_MODEL" ".llm.ollama.model" "qwen3"
}

# Guardrails: keep existing Claude workflows safe by default.
llm_allow_non_claude_code() {
    # If set to 1/true, allow using non-Claude providers for code/spec execution.
    local v="${RALPH_LLM_ALLOW_CODE:-}"
    [ "$v" = "1" ] || [ "$v" = "true" ] || [ "$v" = "TRUE" ]
}
