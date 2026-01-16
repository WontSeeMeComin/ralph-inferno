#!/usr/bin/env node
// agent-run.mjs - Lightweight local/OpenRouter coding agent for running a Ralph spec
// No external deps (Node 18+).

import fs from 'node:fs/promises'
import path from 'node:path'
import os from 'node:os'
import crypto from 'node:crypto'
import { spawnSync } from 'node:child_process'

const COMPLETION_MARKER = '<promise>DONE</promise>'

function die(msg, code = 1) {
  console.error(msg)
  process.exit(code)
}

function run(cmd, { cwd = process.cwd(), timeoutMs = 0 } = {}) {
  const res = spawnSync('bash', ['-lc', cmd], {
    cwd,
    encoding: 'utf8',
    maxBuffer: 50 * 1024 * 1024,
    timeout: timeoutMs > 0 ? timeoutMs : undefined,
  })
  return {
    exitCode: res.status ?? 0,
    stdout: res.stdout ?? '',
    stderr: res.stderr ?? '',
    signal: res.signal ?? null,
  }
}

async function readConfig() {
  const configPath = process.env.RALPH_CONFIG || path.join('.ralph', 'config.json')
  try {
    const raw = await fs.readFile(configPath, 'utf8')
    return { path: configPath, json: JSON.parse(raw) }
  } catch {
    return { path: configPath, json: {} }
  }
}

function envOr(obj, envName, getter, fallback) {
  const v = process.env[envName]
  if (v !== undefined && v !== '') return v
  const jv = getter(obj)
  if (jv !== undefined && jv !== null && String(jv) !== '') return String(jv)
  return fallback
}

function normalizeOpenAIBaseUrl(base) {
  const b = String(base || '').replace(/\/$/, '')
  return b.endsWith('/v1') ? b : `${b}/v1`
}

function useCaseSuffix(useCase) {
  return String(useCase || '')
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '_')
}

function useCaseEnv(baseKey, useCase) {
  const s = useCaseSuffix(useCase)
  return s ? `${baseKey}_${s}` : baseKey
}

function modelFor({ provider, config, useCase }) {
  if (provider === 'ollama') {
    return (
      process.env[useCaseEnv('RALPH_OLLAMA_MODEL', useCase)] ||
      config.llm?.ollama?.use_case_models?.[useCase] ||
      process.env.RALPH_OLLAMA_MODEL ||
      config.llm?.ollama?.model ||
      'qwen3'
    )
  }

  if (provider === 'lmstudio') {
    return (
      process.env[useCaseEnv('RALPH_LMSTUDIO_MODEL', useCase)] ||
      config.llm?.lmstudio?.use_case_models?.[useCase] ||
      process.env.RALPH_LMSTUDIO_MODEL ||
      config.llm?.lmstudio?.model ||
      'qwen/qwen3-next-80b'
    )
  }

  if (provider === 'openrouter') {
    return (
      process.env[useCaseEnv('RALPH_OPENROUTER_MODEL', useCase)] ||
      config.llm?.openrouter?.use_case_models?.[useCase] ||
      process.env.RALPH_OPENROUTER_MODEL ||
      config.llm?.openrouter?.model ||
      'openai/gpt-4o-mini'
    )
  }

  return null
}

async function llmChat({ provider, config, messages, timeoutSeconds, useCase }) {
  if (provider === 'ollama') {
    const host = envOr(config, 'RALPH_OLLAMA_HOST', (c) => c.llm?.ollama?.host, 'http://localhost:11434')
    const model = modelFor({ provider, config, useCase })
    const resp = await fetch(`${host.replace(/\/$/, '')}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, stream: false, messages }),
      signal: AbortSignal.timeout(timeoutSeconds * 1000),
    })
    const text = await resp.text()
    if (!resp.ok) throw new Error(`Ollama error ${resp.status}: ${text.slice(0, 500)}`)
    const json = JSON.parse(text)
    return json?.message?.content ?? ''
  }

  if (provider === 'lmstudio' || provider === 'openrouter') {
    const base = provider === 'lmstudio'
      ? envOr(config, 'RALPH_LMSTUDIO_BASE_URL', (c) => c.llm?.lmstudio?.base_url, 'http://localhost:1234')
      : envOr(config, 'RALPH_OPENROUTER_BASE_URL', (c) => c.llm?.openrouter?.base_url, 'https://openrouter.ai/api/v1')

    const model = modelFor({ provider, config, useCase })

    const url = `${normalizeOpenAIBaseUrl(base)}/chat/completions`

    const headers = { 'Content-Type': 'application/json' }
    if (provider === 'openrouter') {
      const key = process.env.RALPH_OPENROUTER_API_KEY || process.env.OPENROUTER_API_KEY || config.llm?.openrouter?.api_key
      if (!key) throw new Error('OpenRouter requires OPENROUTER_API_KEY (or RALPH_OPENROUTER_API_KEY)')
      headers.Authorization = `Bearer ${key}`
      // Optional analytics headers
      if (process.env.OPENROUTER_HTTP_REFERER) headers['HTTP-Referer'] = process.env.OPENROUTER_HTTP_REFERER
      if (process.env.OPENROUTER_X_TITLE) headers['X-Title'] = process.env.OPENROUTER_X_TITLE
    }

    const resp = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify({ model, messages, temperature: 0.2 }),
      signal: AbortSignal.timeout(timeoutSeconds * 1000),
    })
    const text = await resp.text()
    if (!resp.ok) throw new Error(`OpenAI-compatible error ${resp.status}: ${text.slice(0, 500)}`)
    const json = JSON.parse(text)
    return json?.choices?.[0]?.message?.content ?? ''
  }

  throw new Error(`Unsupported provider: ${provider}`)
}

async function selectProvider(config) {
  const requested = (process.env.RALPH_LLM_PROVIDER || config.llm?.provider || 'claude').toLowerCase()

  async function healthOpenAI(base, headers = {}) {
    try {
      const url = `${normalizeOpenAIBaseUrl(base)}/models`
      const r = await fetch(url, { headers, signal: AbortSignal.timeout(3000) })
      return r.ok
    } catch {
      return false
    }
  }

  async function healthOllama(host) {
    try {
      const r = await fetch(`${host.replace(/\/$/, '')}/api/tags`, { signal: AbortSignal.timeout(3000) })
      return r.ok
    } catch {
      return false
    }
  }

  const auto = async () => {
    const lmBase = envOr(config, 'RALPH_LMSTUDIO_BASE_URL', (c) => c.llm?.lmstudio?.base_url, 'http://localhost:1234')
    if (await healthOpenAI(lmBase)) return 'lmstudio'

    const ollamaHost = envOr(config, 'RALPH_OLLAMA_HOST', (c) => c.llm?.ollama?.host, 'http://localhost:11434')
    if (await healthOllama(ollamaHost)) return 'ollama'

    const orBase = envOr(config, 'RALPH_OPENROUTER_BASE_URL', (c) => c.llm?.openrouter?.base_url, 'https://openrouter.ai/api/v1')
    const key = process.env.RALPH_OPENROUTER_API_KEY || process.env.OPENROUTER_API_KEY || config.llm?.openrouter?.api_key
    if (key) {
      if (await healthOpenAI(orBase, { Authorization: `Bearer ${key}` })) return 'openrouter'
    }

    return null
  }

  if (requested === 'auto') return (await auto())
  if (['lmstudio', 'ollama', 'openrouter'].includes(requested)) return requested
  return null
}

function stripToJsonObject(text) {
  // Remove common code fences and grab the first {...} block.
  const t = String(text || '').replace(/```[a-zA-Z]*\n?/g, '').replace(/```/g, '').trim()
  const start = t.indexOf('{')
  const end = t.lastIndexOf('}')
  if (start === -1 || end === -1 || end <= start) throw new Error('No JSON object found')
  return t.slice(start, end + 1)
}

async function main() {
  const argv = process.argv.slice(2)
  let specPath = null
  let useCase = 'execute'
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--use-case' || a === '--usecase') {
      useCase = argv[i + 1]
      i++
      continue
    }
    if (!specPath) {
      specPath = a
      continue
    }
  }

  if (!specPath) die('Usage: agent-run.mjs <spec-file> [--use-case execute|plan|discover|vision]')

  const spec = await fs.readFile(specPath, 'utf8').catch(() => null)
  if (spec == null) die(`Spec not found: ${specPath}`)

  const { json: config, path: cfgPath } = await readConfig()

  const provider = await (async () => {
    const uc = String(useCase || 'execute')
    const envKey = `RALPH_LLM_PROVIDER_${uc.toUpperCase().replace(/[^A-Z0-9]/g, '_')}`
    const requested = (
      process.env[envKey] ||
      process.env.RALPH_LLM_PROVIDER ||
      config.llm?.use_case_providers?.[uc] ||
      config.llm?.provider ||
      'claude'
    ).toLowerCase()

    // Agent runner is designed to work without Claude. If requested=claude, treat as auto.
    if (requested === 'claude') {
      process.env.RALPH_LLM_PROVIDER = 'auto'
    } else {
      process.env.RALPH_LLM_PROVIDER = requested
    }
    return await selectProvider(config)
  })()
  if (!provider) {
    die(
      `No non-Claude provider available. Configure one of: LM Studio, Ollama, OpenRouter.\n` +
      `Config: ${cfgPath}`
    )
  }

  const timeoutSeconds = Number(envOr(config, 'RALPH_LLM_TIMEOUT_SECONDS', (c) => c.llm?.timeout_seconds, '120'))
  const maxSteps = Number(process.env.RALPH_AGENT_MAX_STEPS || 30)

  const sessionId = crypto.randomUUID?.() ?? crypto.randomBytes(16).toString('hex')
  console.log(`[agent] session=${sessionId} useCase=${useCase} provider=${provider} spec=${specPath}`)

  const toolSpec = {
    read_file: { path: 'string', start_line: 'number?', end_line: 'number?' },
    list_dir: { path: 'string' },
    search: { pattern: 'string', path: 'string?' },
    write_file: { path: 'string', content: 'string' },
    apply_patch: { patch: 'string (git apply format)' },
    run: { cmd: 'string' },
    done: { summary: 'string' },
  }

  const system = `You are Ralph, an autonomous coding agent running in a disposable sandbox repo.

You MUST complete the provided spec.

You can only communicate by returning EXACTLY ONE JSON object per turn.

CRITICAL:
- Your JSON MUST include an "action" key.
- The action MUST be one of: ${Object.keys(toolSpec).join(', ')}

Allowed actions and schemas:
${JSON.stringify(toolSpec, null, 2)}

Example valid response:
{"action":"read_file","path":"package.json","start_line":1,"end_line":120}

Rules:
- Always respond with a single JSON object (no markdown, no commentary).
- Prefer apply_patch over rewriting whole files.
- After changes, run 'npm run build'. For apps with Playwright config, run 'npx playwright test'.
- When fully complete, respond with {"action":"done","summary":"..."}.
`

  const messages = [
    { role: 'system', content: system },
    {
      role: 'user',
      content:
        `SPEC FILE: ${specPath}\n\n` +
        `${spec}\n\n` +
        (process.env.RALPH_AGENT_EXTRA_CONTEXT
          ? `\n\n---\nADDITIONAL CONTEXT (from previous failures):\n${process.env.RALPH_AGENT_EXTRA_CONTEXT}\n`
          : '') +
        `\nRemember: reply with a single JSON tool action.`,
    },
  ]

  for (let step = 1; step <= maxSteps; step++) {
    let modelText
    try {
      modelText = await llmChat({ provider, config, messages, timeoutSeconds, useCase })
    } catch (e) {
      console.log(`[agent] model error: ${String(e).slice(0, 500)}`)
      process.exit(2)
    }

    let action
    try {
      action = JSON.parse(stripToJsonObject(modelText))
    } catch (e) {
      messages.push({
        role: 'assistant',
        content: modelText,
      })
      messages.push({
        role: 'user',
        content:
          `Your response was not valid JSON. Reply again with EXACTLY ONE JSON object tool action. Error: ${String(e).slice(0, 200)}`,
      })
      continue
    }

    const act = action?.action
    if (typeof act !== 'string' || act.length === 0) {
      if (process.env.RALPH_AGENT_DEBUG) {
        console.log('[agent] invalid response (missing action). raw:')
        console.log(String(modelText).slice(0, 1000))
      }

      messages.push({ role: 'assistant', content: modelText })
      messages.push({
        role: 'user',
        content:
          'INVALID RESPONSE: missing required key "action". Reply again with EXACTLY ONE JSON object that includes "action" and follows the schema.',
      })
      continue
    }

    console.log(`[agent] step ${step}: ${act}`)

    const respond = (payload) => {
      messages.push({ role: 'assistant', content: JSON.stringify(action) })
      messages.push({ role: 'user', content: JSON.stringify(payload).slice(0, 15000) })
    }

    if (act === 'read_file') {
      const p = action.path
      const start = Number(action.start_line || 1)
      const end = Number(action.end_line || start + 200)
      try {
        const raw = await fs.readFile(p, 'utf8')
        const lines = raw.split('\n')
        const slice = lines.slice(start - 1, end).map((l, i) => `${start + i}: ${l}`)
        respond({ ok: true, action: 'read_file', path: p, start_line: start, end_line: end, content: slice.join('\n') })
      } catch (e) {
        respond({ ok: false, action: 'read_file', error: String(e) })
      }
      continue
    }

    if (act === 'list_dir') {
      const p = action.path
      try {
        const entries = await fs.readdir(p, { withFileTypes: true })
        respond({
          ok: true,
          action: 'list_dir',
          path: p,
          entries: entries
            .slice(0, 200)
            .map((e) => ({ name: e.name, type: e.isDirectory() ? 'dir' : 'file' })),
        })
      } catch (e) {
        respond({ ok: false, action: 'list_dir', error: String(e) })
      }
      continue
    }

    if (act === 'search') {
      const pattern = action.pattern
      const p = action.path || '.'
      const res = run(`grep -R -n -- "${pattern.replaceAll('"', '\\"')}" "${p.replaceAll('"', '\\"')}" | head -50 || true`)
      respond({ ok: true, action: 'search', path: p, pattern, stdout: res.stdout, stderr: res.stderr })
      continue
    }

    if (act === 'run') {
      const cmd = action.cmd
      const res = run(cmd)
      respond({ ok: res.exitCode === 0, action: 'run', cmd, exitCode: res.exitCode, stdout: res.stdout, stderr: res.stderr })
      continue
    }

    if (act === 'write_file') {
      const p = action.path
      const content = String(action.content ?? '')
      await fs.mkdir(path.dirname(p), { recursive: true }).catch(() => {})
      await fs.writeFile(p, content, 'utf8')
      respond({ ok: true, action: 'write_file', path: p, bytes: Buffer.byteLength(content) })
      continue
    }

    if (act === 'apply_patch') {
      const patchText = String(action.patch ?? '')
      const tmp = path.join(os.tmpdir(), `ralph-patch-${sessionId}.patch`)
      await fs.writeFile(tmp, patchText, 'utf8')
      const res = run(`git apply --whitespace=nowarn "${tmp}"`, { timeoutMs: 60_000 })
      respond({ ok: res.exitCode === 0, action: 'apply_patch', exitCode: res.exitCode, stdout: res.stdout, stderr: res.stderr })
      continue
    }

    if (act === 'done') {
      console.log(`[agent] done: ${action.summary || ''}`)
      console.log(COMPLETION_MARKER)
      process.exit(0)
    }

    respond({ ok: false, error: `Unknown action: ${act}` })
  }

  console.log('[agent] max steps reached without completion')
  process.exit(3)
}

main().catch((e) => {
  console.error(String(e))
  process.exit(1)
})
