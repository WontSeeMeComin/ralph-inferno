# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Ralph Inferno

Ralph Inferno is an AI-driven autonomous development workflow tool. It runs on a disposable VM to execute AI-generated code safely, processing spec files sequentially while you sleep. The workflow: discover (PRD) → plan (specs) → deploy to VM → autonomous build/test/fix loop.

## Build/Test Commands

```bash
# Install dependencies
npm install

# Test CLI locally
node bin/ralph-inferno.js install   # Install Ralph in a project
node bin/ralph-inferno.js update    # Update core files
node bin/ralph-inferno.js discover  # Generate PRD via LLM
node bin/ralph-inferno.js plan      # Generate specs from PRD

# Smoke test LLM providers
./.ralph/scripts/llm-smoke-test.sh
```

No test suite exists currently (`npm test` exits with error).

## Architecture

Ralph uses a three-loop architecture:

1. **Outer Loop (your machine)**: Claude Code slash commands (`/ralph:discover`, `/ralph:plan`, `/ralph:deploy`, `/ralph:review`)
2. **Middle Loop (orchestrator.sh)**: Retry specs until all pass, auto-generate CRs on failure
3. **Inner Loop (per spec)**: Run spec via agent → verify build → E2E tests → design review → commit

### Key Directories

```
bin/                    # CLI entry point (ralph-inferno.js)
cli/                    # CLI commands (install.js, update.js, discover.js, plan.js)
core/
├── scripts/           # Main execution scripts
│   ├── ralph.sh       # Entry point (~310 lines, clean loop)
│   ├── orchestrator.sh# Middle loop with retries
│   ├── agent-run.mjs  # LLM agent loop (non-Claude execution)
│   └── ralph-full.sh  # Legacy monolithic mode
├── lib/               # Shell libraries
│   ├── llm.sh         # Multi-provider LLM wrapper
│   ├── llm-config.sh  # Provider settings + env overrides
│   ├── spec-utils.sh  # next_spec, mark_done, checksums
│   ├── test-loop.sh   # E2E tests + CR generation + design review
│   └── ...            # notify, git-utils, verify, tokens, etc.
├── .claude/commands/  # Slash command definitions (ralph:*.md)
└── templates/         # PRD, SPEC, CLAUDE.md templates
```

### Agent Modes

- `agent_mode=claude` (default): Uses Claude Code CLI for spec execution
- `agent_mode=llm`: Uses `agent-run.mjs` with LM Studio/Ollama/OpenRouter

### Deploy Modes

| Mode | Flag | Features |
|------|------|----------|
| Quick | (none) | Spec + build verify only |
| Standard | `--orchestrate` | + E2E tests + auto-CR |
| Inferno | `--orchestrate --parallel` | + design review + parallel worktrees |

## LLM Provider Configuration

Providers can be configured per use-case in `.ralph/config.json`:

```json
{
  "llm": {
    "agent_mode": "llm",
    "use_case_providers": {
      "discover": "openrouter",
      "plan": "openrouter",
      "execute": "lmstudio",
      "vision": "lmstudio"
    }
  }
}
```

Environment overrides: `RALPH_LLM_PROVIDER`, `RALPH_AGENT_MODE`, `RALPH_LMSTUDIO_BASE_URL`, `OPENROUTER_API_KEY`, etc.

## Memory Model

- **Short-term**: Spec file content (what to do now)
- **Medium-term**: `.spec-checksums/*.md5` (which specs are done)
- **Long-term**: Git commits (all code built)

Each spec runs with fresh Claude context.

## Slash Commands (for Claude Code users)

| Command | Purpose |
|---------|---------|
| `/ralph:discover` | Autonomous discovery → PRD |
| `/ralph:plan` | PRD → implementation specs |
| `/ralph:deploy` | Push to GitHub, start on VM |
| `/ralph:review` | Open tunnels, test app |
| `/ralph:change-request` | Document bugs → CR specs |
| `/ralph:status` | Check VM progress |
| `/ralph:abort` | Stop Ralph on VM |
