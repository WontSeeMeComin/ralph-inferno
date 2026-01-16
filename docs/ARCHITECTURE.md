# Ralph Architecture

## Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           THREE LOOPS                                        │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│   OUTER LOOP     │    │   MIDDLE LOOP    │    │   INNER LOOP     │
│   (Your Machine) │ →  │   (Orchestrator) │ →  │   (Per Spec)     │
├──────────────────┤    ├──────────────────┤    ├──────────────────┤
│ /ralph:discover  │    │ ralph.sh         │    │ Claude runs spec │
│ /ralph:plan      │    │ --orchestrate    │    │ npm run build    │
│ /ralph:deploy    │    │                  │    │ playwright test  │
│ /ralph:review    │    │ Retries specs    │    │ Auto-CR on fail  │
│                  │    │ until all pass   │    │ Design review    │
└──────────────────┘    └──────────────────┘    └──────────────────┘
       YOU                   VM (auto)              VM (auto)
```

## Three Modes

| Mode | Flag | What it does |
|------|------|--------------|
| **Quick** | (none) | Spec → build → commit |
| **Standard** | `--orchestrate` | + E2E tests + auto-CR |
| **Inferno** | `--orchestrate --parallel` | + design review + parallel |

## Inner Loop (per spec)

```bash
run_spec() {
    # 1. Claude runs spec
    claude -p --dangerously-skip-permissions < "$spec"

    # 2. Verify build
    npm run build || retry

    # 3. Run E2E tests (Standard/Inferno mode)
    npx playwright test || generate_cr && retry

    # 4. Design review (Inferno mode)
    take_screenshots
    claude --vision "Check against design system" || generate_design_cr && retry

    # 5. Commit & mark done
    git commit && mark_spec_done "$spec"
}
```

### Multi-provider inference

Ralph now includes a small provider abstraction in `lib/llm.sh`.

- **Claude** remains the default and safest option.
- **LM Studio / Ollama / OpenRouter** can be configured for text-generation steps (e.g. auto Change Request generation) and will gracefully fall back when unavailable.

## Middle Loop (Orchestrator)

```bash
# orchestrator.sh
MAX_ITERATIONS=3

while [ $iteration -lt $MAX_ITERATIONS ]; do
    ralph.sh  # Run all specs

    if all_specs_done; then
        notify "✅ Complete!"
        exit 0
    fi

    ((iteration++))
done

notify "⚠️ Needs help"
```

## Memory Model (Ryan Carson)

| Type | File | Purpose |
|------|------|---------|
| Short-term | Spec itself | What Claude should do NOW |
| Medium-term | Checksums | Which specs are done |
| Long-term | Git commits | All code built |

**Fresh context per iteration** = Each spec starts with empty Claude session.

## File Structure

```
.ralph/
├── scripts/
│   ├── ralph.sh          # Main entry point
│   ├── orchestrator.sh   # Middle loop (--orchestrate)
│   └── ralph-full.sh     # Legacy full mode
│
├── lib/
│   ├── spec-utils.sh     # next_spec, mark_done, checksums
│   ├── verify.sh         # verify_build
│   ├── test-loop.sh      # E2E tests + CR generation + design review
│   ├── notify.sh         # ntfy notifications
│   ├── git-utils.sh      # commit, push, safety checks
│   ├── rate-limit.sh     # Handle rate limits
│   ├── llm.sh            # Multi-provider LLM wrapper
│   ├── llm-config.sh     # Centralized provider settings + env overrides
│   ├── tokens.sh         # Cost tracking
│   └── parallel.sh       # Worktree management
│
├── .claude/commands/
│   ├── ralph:discover.md # Discovery loop
│   ├── ralph:plan.md     # Generate specs
│   ├── ralph:deploy.md   # Push & start VM
│   ├── ralph:review.md   # Test via tunnel
│   ├── ralph:change-request.md  # Bug → CR specs
│   ├── ralph:status.md   # Check progress
│   └── ralph:abort.md    # Stop Ralph
│
└── templates/
    ├── PRD-template.md
    ├── SPEC-template.md
    └── stacks/react-supabase/
```

## Features by Mode

| Feature | Quick | Standard | Inferno |
|---------|-------|----------|---------|
| Spec execution | ✅ | ✅ | ✅ |
| Build verify | ✅ | ✅ | ✅ |
| E2E tests | ❌ | ✅ | ✅ |
| Auto-CR generation | ❌ | ✅ | ✅ |
| Design review | ❌ | ❌ | ✅ |
| Parallel worktrees | ❌ | ❌ | ✅ |
| Loop protection | ✅ | ✅ | ✅ |
| ntfy notifications | ✅ | ✅ | ✅ |

## References

- [snarktank/ralph](https://github.com/snarktank/ralph) - Ryan Carson
- [claude-ralph](https://github.com/RobinOppenstam/claude-ralph) - Robin Oppenstam
- [how-to-build-a-coding-agent](https://github.com/ghuntley/how-to-build-a-coding-agent) - Geoffrey Huntley
