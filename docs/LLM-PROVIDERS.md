# LLM Providers (Multi-Provider Inference)

Ralph Inferno supports multiple inference backends **in addition to Claude**.

Today this is primarily used for **text-generation steps** (e.g. auto Change Request generation), while keeping existing Claude-based workflows intact.

It can also be used to run:
- **Discovery/Planning** (`ralph-inferno discover|plan`) without the Claude UI
- **Spec execution** (agent mode) without the Claude Code CLI

## Providers

| Provider | Use case | Protocol |
|---|---|---|
| `claude` | Default, safest fallback | Claude Code CLI |
| `lmstudio` | Local inference via LM Studio | OpenAI-compatible HTTP (`/v1/chat/completions`) |
| `ollama` | Local inference via Ollama | Native HTTP (`/api/chat`) |
| `openrouter` | API gateway for many models | OpenAI-compatible HTTP |
| `auto` | Try local first, then gateways, then Claude | Health-check based |

## Config (`.ralph/config.json`)

Add/update the `llm` section:

```json
{
  "llm": {
    "provider": "auto",
    "fallback_provider": "claude",
    "agent_mode": "llm",
    "use_case_providers": {
      "discover": "openrouter",
      "plan": "openrouter",
      "execute": "lmstudio",
      "vision": "lmstudio"
    },
    "timeout_seconds": 120,
    "max_retries": 2,
    "lmstudio": {
      "base_url": "http://192.168.12.239:1234",
      "model": "qwen/qwen3-next-80b",
      "vision_model": "zai-org/glm-4.6v-flash"
    },
    "ollama": {
      "host": "http://localhost:11434",
      "model": "qwen3"
    },
    "openrouter": {
      "base_url": "https://openrouter.ai/api/v1",
      "model": "openai/gpt-4o-mini"
    }
  }
}
```

### LM Studio notes

- `base_url` can be either:
  - `http://host:1234` (Ralph will append `/v1`), or
  - `http://host:1234/v1`

## Environment variable overrides

Environment variables always override JSON config:

- `RALPH_LLM_PROVIDER` = `auto|lmstudio|ollama|openrouter|claude`
- `RALPH_LLM_PROVIDER_DISCOVER` / `RALPH_LLM_PROVIDER_PLAN` / `RALPH_LLM_PROVIDER_EXECUTE` / `RALPH_LLM_PROVIDER_VISION`
- `RALPH_AGENT_MODE` = `claude|llm`
- `RALPH_LLM_FALLBACK_PROVIDER` = `claude|openrouter|ollama|lmstudio`
- `RALPH_LLM_TIMEOUT_SECONDS` (default `120`)
- `RALPH_LLM_MAX_RETRIES` (default `2`)

### LM Studio

- `RALPH_LMSTUDIO_BASE_URL`
- `RALPH_LMSTUDIO_MODEL`
- `RALPH_LMSTUDIO_VISION_MODEL` (default: `zai-org/glm-4.6v-flash`)

### Ollama

- `RALPH_OLLAMA_HOST`
- `RALPH_OLLAMA_MODEL`

### OpenRouter

- `OPENROUTER_API_KEY` (or `RALPH_OPENROUTER_API_KEY`)
- `RALPH_OPENROUTER_BASE_URL`
- `RALPH_OPENROUTER_MODEL`

## Smoke test

Use the included script to validate connectivity:

```bash
RALPH_LLM_PROVIDER=lmstudio \
RALPH_LMSTUDIO_BASE_URL=http://192.168.12.239:1234 \
RALPH_LMSTUDIO_MODEL=qwen/qwen3-next-80b \
./.ralph/scripts/llm-smoke-test.sh
```

The script will print the selected provider and a short response.

## Running specs without Claude

To run Ralph specs without the Claude Code CLI, enable agent mode:

```bash
export RALPH_AGENT_MODE=llm
export RALPH_LLM_PROVIDER=lmstudio   # or ollama/openrouter/auto
```

In this mode, the inner loop uses `scripts/agent-run.mjs` (a lightweight tool loop) to read/edit files and run commands.

## Running discover/plan without the Claude UI

```bash
ralph-inferno discover "my-app" --idea "A small app that ..."
ralph-inferno plan
```

These commands use the same prompt logic as the `/ralph:discover` and `/ralph:plan` slash commands, but run via the configured non-Claude providers.
