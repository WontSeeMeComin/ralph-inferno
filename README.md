# 🔥 Ralph Inferno

```
🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥
🔥                                              🔥
🔥  ██████╗  █████╗ ██╗     ██████╗ ██╗  ██╗    🔥
🔥  ██╔══██╗██╔══██╗██║     ██╔══██╗██║  ██║    🔥
🔥  ██████╔╝███████║██║     ██████╔╝███████║    🔥
🔥  ██╔══██╗██╔══██║██║     ██╔═══╝ ██╔══██║    🔥
🔥  ██║  ██║██║  ██║███████╗██║     ██║  ██║    🔥
🔥  ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝    🔥
🔥                                              🔥
🔥          I N F E R N O   M O D E             🔥
🔥                                              🔥
🔥  Build while you sleep. Wake to working code 🔥
🔥                   🌙 → ☀️                     🔥
🔥                                              🔥
🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥
```

AI-driven autonomous development workflow.

## Requirements

**Local machine:**
- Node.js (for npx)
- (Optional) [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`) — required only if you want to run the `/ralph:*` slash commands inside Claude Code
- GitHub CLI (`gh`) - optional, for auto-detecting username

**VM (where Ralph runs):**
- A running VM/server (Hetzner, GCP, DigitalOcean, AWS, or your own)
- SSH access to the VM
- Git installed

If you run the VM loop in `agent_mode=claude` (default), the VM also needs the Claude Code CLI with either:
- Anthropic API key (`ANTHROPIC_API_KEY`), or
- Claude subscription (requires `claude login` on the VM)

If you run the VM loop in `agent_mode=llm`, Claude is not required on the VM, but your chosen LLM provider(s) must be reachable from the VM.

**Optional (multi-provider inference):**
- A reachable local inference server (for text-only steps like auto-CR generation)
  - **LM Studio** (OpenAI-compatible HTTP)
  - **Ollama** (native HTTP API)
- Or an API gateway provider:
  - **OpenRouter** (OpenAI-compatible HTTP; requires `OPENROUTER_API_KEY`)

**Optional:**
- Cloud CLI (`hcloud`, `gcloud`, `doctl`, `aws`) for VM management
- [ntfy.sh](https://ntfy.sh) for notifications

## Installation

```bash
npx ralph-inferno install
```

This will:
1. Show disclaimer (VM sandbox required)
2. Ask for your preferences (language, cloud provider, etc.)
3. Ask how Claude authenticates (subscription or API key)
4. Install Ralph core files to `.ralph/`
5. Create a `ralph` wrapper script

### Manual configuration (recommended if you want local inference)

After install, edit `.ralph/config.json`:

- Set `llm.agent_mode` to:
  - `claude` (default): VM uses Claude Code CLI for spec execution
  - `llm`: VM uses the local/OpenRouter agent loop for spec execution
- Optionally route providers by use-case:
  - `discover` / `plan` (PRD/spec generation)
  - `execute` (spec execution)
  - `vision` (design review)

Note: `lmstudio`/`ollama` only work if the VM can reach those endpoints. If you're running Ralph on a remote VM, OpenRouter is usually the simplest option for `execute`/`vision`.

Example `llm` section:

```json
{
  "llm": {
    "agent_mode": "llm",
    "provider": "auto",
    "use_case_providers": {
      "discover": "openrouter",
      "plan": "openrouter",
      "execute": "openrouter",
      "vision": "openrouter"
    },
    "openrouter": {
      "model": "openai/gpt-4o-mini",
      "use_case_models": {
        "plan": "anthropic/claude-3.5-sonnet"
      }
    }
  }
}
```

See: [docs/LLM-PROVIDERS.md](docs/LLM-PROVIDERS.md)

## Update

Update core files while preserving your config:

```bash
npx ralph-inferno update
```

## Workflow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           RALPH WORKFLOW                                     │
└─────────────────────────────────────────────────────────────────────────────┘

   YOUR IDEA
      │
      ▼
┌─────────────────┐
│ /ralph:discover │  ◄── Autonomous discovery loop
│                 │      Claude explores from all angles
│ Output: PRD.md  │      (Analyst, PM, UX, Architect, Business)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  /ralph:plan    │  ◄── Breaks down PRD into specs
│                 │
│ Output: specs/* │      (01-setup.md, 02-auth.md, etc.)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  /ralph:deploy  │  ◄── Push to GitHub, start on VM
│                 │      Choose mode: Quick/Standard/Inferno
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                     ON THE VM (AUTONOMOUS)                       │
│                                                                  │
│   ralph.sh runs specs → build → test → auto-fix → commit        │
│                                                                  │
└────────┬─────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────┐
│  /ralph:review  │  ◄── Open tunnels, test the app
└────────┬────────┘
         │
         ▼
┌─────────────────────┐
│ /ralph:change-      │  ◄── If bugs found, generate CR specs
│ request             │      Then run /ralph:deploy again
└─────────────────────┘
```

### Commands

| Command | Description |
|---------|-------------|
| `/ralph:discover` | Autonomous discovery loop, creates PRD with web research |
| `/ralph:plan` | Creates implementation plan + spec files |
| `/ralph:deploy` | Push to GitHub, choose mode, start Ralph on VM |
| `/ralph:review` | Open SSH tunnels, test the app |
| `/ralph:change-request` | Document bugs, generate CR specs for fixes |
| `/ralph:status` | Check Ralph's progress on VM |
| `/ralph:abort` | Stop Ralph on VM |

### Deploy Modes

When running `/ralph:deploy`, you choose a mode:

| Mode | What it does |
|------|--------------|
| **Quick** | Spec execution + build verify only |
| **Standard** | + Playwright E2E tests + auto-CR generation |
| **Inferno** | + Design review + parallel worktrees |

### Example Session

```bash
# 1. Install Ralph in your project
npx ralph-inferno install

# 2. In Claude Code:
/ralph:discover    # Autonomous discovery with web research
/ralph:plan        # Generate specs from PRD
/ralph:deploy      # Choose mode, send to VM

# You can keep using these slash commands in Claude Code.
# The multi-provider/local inference settings mainly affect:
# - VM execution (spec runner + design review)
# - CLI-only discovery/planning (below)

# 2b. Or: No Claude UI (CLI-only)
ralph-inferno discover my-app --idea "What are we building?"
ralph-inferno plan

# 3. Next morning:
/ralph:review      # Test what Ralph built

# 4. If bugs found:
/ralph:change-request  # Generate fix specs
/ralph:deploy          # Run fixes
```

## Safety

Ralph runs AI-generated code autonomously. For safety:

- **ALWAYS run on a disposable VM** - never on your local machine
- Review generated code before production
- Never store credentials in code

## Cloud Providers

Ralph supports multiple cloud providers for VM execution:

| Provider | CLI | Notes |
|----------|-----|-------|
| Hetzner | `hcloud` | Cheapest, great for Europe |
| Google Cloud | `gcloud` | Good free tier |
| DigitalOcean | `doctl` | Simple and reliable |
| AWS | `aws` | Enterprise option |
| SSH | - | Use your own server |

## Config File

Configuration is stored in `.ralph/config.json`:

```json
{
  "version": "1.0.1",
  "language": "en",
  "provider": "hcloud",
  "vm_name": "ralph-sandbox",
  "region": "fsn1",
  "github": {
    "username": "your-username"
  },
  "claude": {
    "auth_method": "subscription"
  },
  "llm": {
    "provider": "claude",
    "fallback_provider": "claude",
    "agent_mode": "claude",
	    "use_case_providers": {
	      "discover": "openrouter",
	      "plan": "openrouter",
	      "execute": "lmstudio",
	      "vision": "lmstudio"
	    },
    "timeout_seconds": 120,
    "max_retries": 2,
    "lmstudio": {
      "base_url": "http://localhost:1234",
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
  },
  "notifications": {
    "ntfy_enabled": true,
    "ntfy_topic": "ralph-notifications"
  }
}
```

### LLM Provider Selection

Ralph now supports multiple inference providers **for text-generation steps** (e.g. auto Change Requests):

- `claude` (default)
- `lmstudio` (OpenAI-compatible)
- `ollama` (native API)
- `openrouter` (OpenAI-compatible)
- `auto` (try LM Studio → Ollama → OpenRouter → Claude)

You can override config via environment variables:

- `RALPH_LLM_PROVIDER` (e.g. `lmstudio`)
- `RALPH_LLM_PROVIDER_DISCOVER` / `RALPH_LLM_PROVIDER_PLAN` / `RALPH_LLM_PROVIDER_EXECUTE` / `RALPH_LLM_PROVIDER_VISION`
- `RALPH_OPENROUTER_MODEL_PLAN` (and similar `*_MODEL_<USE_CASE>` overrides)
- `RALPH_AGENT_MODE` = `claude` (default) or `llm` (run specs via local/OpenRouter agent loop)
- `RALPH_LMSTUDIO_BASE_URL` (e.g. `http://192.168.12.239:1234`)
- `RALPH_LMSTUDIO_MODEL` (e.g. `qwen/qwen3-next-80b`)
- `RALPH_LMSTUDIO_VISION_MODEL` (e.g. `zai-org/glm-4.6v-flash`)
- `OPENROUTER_API_KEY` (for OpenRouter)

See: [docs/LLM-PROVIDERS.md](docs/LLM-PROVIDERS.md)

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - System overview and memory model
- [CLI Flags](docs/CLI-FLAGS.md) - All ralph.sh options
- [Token Optimization](docs/TOKEN-OPTIMIZATION.md) - Cost-saving strategies
- [LLM Providers](docs/LLM-PROVIDERS.md) - Multi-provider inference configuration

## Credits & Inspiration

Ralph Inferno builds on ideas from:

- [snarktank/ralph](https://github.com/snarktank/ralph) - Ryan Carson's original Ralph concept
- [how-to-build-a-coding-agent](https://github.com/ghuntley/how-to-build-a-coding-agent) - Geoffrey Huntley's agent patterns
- [claude-ralph](https://github.com/RobinOppenstam/claude-ralph) - Robin Oppenstam's implementation

## License

MIT
