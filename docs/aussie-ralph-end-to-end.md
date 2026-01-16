# Ralph Inferno: End-to-end checklist (Host Claude Code → VM local inference → Browser)

Goal: Generate PRD/specs on the Mac (Claude Code), then have the VM build/run the React site **using only local inference via LM Studio**, and view it in a browser.

---

## 0) What gets created / where things run

- **Host (Mac + Claude Code UI)**: `/ralph:discover`, `/ralph:plan`, `/ralph:deploy`, `/ralph:review`
- **VM (Ubuntu)**: runs `./.ralph/scripts/ralph.sh --orchestrate` (Standard mode)
- **Repo path on VM (GitHub deploy)**: `~/projects/<repo-name>/`
  - Log file: `~/projects/<repo-name>/ralph-deploy.log`

Ralph’s inner loop commits AND pushes to `origin` per spec (so host can `git pull`).

---

## 1) One-time prereqs

### 1.1 Host (Mac)
- You can run Claude Code in the project repo.
- You have a GitHub repo (public or private) and a remote `origin` set.
- Create `~/.ralph-vm` (used by `/ralph:deploy`):

```bash
cat > ~/.ralph-vm <<'EOF'
VM_IP=192.168.64.4
VM_USER=ubuntu
EOF
```

### 1.2 VM (Ubuntu)
- `git`, `node` (Node 18+), and `gh` installed.
- `gh auth login` completed.
- Ensure **git push/pull works non-interactively** (recommended):

```bash
gh auth setup-git
gh config set -h github.com git_protocol https
```

- Ensure LM Studio is reachable from VM:

```bash
curl http://192.168.12.239:1234/v1/models
```

---

## 2) Create the project repo (host)

You can start with an **empty repo** (recommended). Ralph will create the Vite/React app via specs.

1) Create repo folder + init git + set origin.
2) Install Ralph into that repo:

```bash
npx ralph-inferno install
```

This creates:
- `.ralph/` (scripts + config)
- `ralph` wrapper script
- `.claude/commands/` in the project root (so Claude Code can run `/ralph:*`).

---

## 3) Configure “VM uses only local inference” (project config)

Edit **project** file: `.ralph/config.json` (this is the most reliable way because `/ralph:deploy` starts Ralph via non-interactive SSH).

Set (minimum):
- `llm.agent_mode`: `"llm"`
- `llm.provider`: `"lmstudio"`
- `llm.fallback_provider`: `"lmstudio"` (prevents Claude/OpenRouter fallback)
- `llm.lmstudio.base_url`: `"http://192.168.12.239:1234/v1"`
- `llm.lmstudio.model`: (one of your `/v1/models` ids)
- `llm.use_case_providers.execute`: `"lmstudio"`

Optional:
- `llm.use_case_providers.vision`: `"lmstudio"` (if you ever use Inferno design review)

Then commit these config changes on the host.

---

## 4) Generate PRD + specs (host, in Claude Code)

From inside the repo in Claude Code:
1) `/ralph:discover`  → produces PRD / context
2) `/ralph:plan`      → produces `specs/*.md`

Make sure spec #1 bootstraps the app (Vite + React + Tailwind/shadcn, creates `package.json`, and ensures `npm run build` passes).

---

## 5) Deploy + run Standard mode (host)

Run:
- `/ralph:deploy`
- Choose **Standard** mode (this runs `--orchestrate`)

What happens:
1) Host commits + pushes to `origin`.
2) VM clones/pulls into `~/projects/<repo-name>/`.
3) VM starts Ralph with `nohup ... > ralph-deploy.log &`.

---

## 6) Track progress (host or VM)

### 6.1 Tail logs (host)
```bash
ssh ubuntu@192.168.64.4 'tail -f ~/projects/<repo-name>/ralph-deploy.log'
```

### 6.2 Status commands (VM)
```bash
cd ~/projects/<repo-name>
./ralph --status      # specs done/total
./ralph --cost        # token/cost summary
./ralph --watch       # live dashboard
```

### 6.3 Pull results back to host
Because Ralph pushes commits, on host:
```bash
git pull
```

---

## 7) Run and view the site

### Option A: SSH tunnel (recommended)
On host:
```bash
ssh -N -L 5173:localhost:5173 ubuntu@192.168.64.4
```
On VM (in repo):
```bash
npm install
npm run dev -- --host 127.0.0.1 --port 5173
```
Open: http://localhost:5173

### Option B: Direct to VM IP
On VM:
```bash
npm run dev -- --host 0.0.0.0 --port 5173
```
Open: http://192.168.64.4:5173

---

## 8) Environment variables (optional overrides)

Env vars override `.ralph/config.json`. Use these mainly for debugging/temporary changes.

### Core routing
- `RALPH_AGENT_MODE=claude|llm`
- `RALPH_LLM_PROVIDER=auto|lmstudio|ollama|openrouter|claude`
- `RALPH_LLM_FALLBACK_PROVIDER=claude|openrouter|ollama|lmstudio`
- `RALPH_LLM_TIMEOUT_SECONDS=120`
- `RALPH_LLM_MAX_RETRIES=2`
- `RALPH_LLM_PROVIDER_DISCOVER` / `..._PLAN` / `..._EXECUTE` / `..._VISION`

### LM Studio
- `RALPH_LMSTUDIO_BASE_URL=http://host:1234` OR `http://host:1234/v1`
- `RALPH_LMSTUDIO_MODEL=<id>` (default model for all LM Studio use-cases)
- Per-use-case overrides (optional; override the default above):
  - `RALPH_LMSTUDIO_MODEL_DISCOVER=<id>`
  - `RALPH_LMSTUDIO_MODEL_PLAN=<id>`
  - `RALPH_LMSTUDIO_MODEL_EXECUTE=<id>`
- `RALPH_LMSTUDIO_VISION_MODEL=<id>`

### Ollama
- `RALPH_OLLAMA_HOST=http://localhost:11434`
- `RALPH_OLLAMA_MODEL=<id>`
- `RALPH_OLLAMA_MODEL_DISCOVER|PLAN|EXECUTE=<id>`

### OpenRouter
- `OPENROUTER_API_KEY=<key>` (or `RALPH_OPENROUTER_API_KEY`)
- `RALPH_OPENROUTER_BASE_URL=https://openrouter.ai/api/v1`
- `RALPH_OPENROUTER_MODEL=<id>`
- `RALPH_OPENROUTER_MODEL_DISCOVER|PLAN|EXECUTE|VISION=<id>`

### Claude (only if you want cloud fallback)
- `ANTHROPIC_API_KEY=<key>` (or do `claude login` when using Claude Code CLI)

### Suggested `~/.bashrc` snippet (VM)
Put this at the end of `/home/ubuntu/.bashrc` for interactive sessions:
```bash
export RALPH_AGENT_MODE=llm
export RALPH_LLM_PROVIDER=lmstudio
export RALPH_LLM_FALLBACK_PROVIDER=lmstudio
export RALPH_LMSTUDIO_BASE_URL="http://192.168.12.239:1234/v1"
export RALPH_LMSTUDIO_MODEL="<your-model-id>"
```

NOTE: `/ralph:deploy` starts Ralph via non-interactive SSH; rely on `.ralph/config.json` for the real source of truth.

