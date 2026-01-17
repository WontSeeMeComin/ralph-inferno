#!/usr/bin/env node
// agent-run.mjs - Lightweight local/OpenRouter coding agent for running a Ralph spec
// Supports both native OpenAI tool calling and JSON-in-text formats.
// No external deps (Node 18+).

import fs from 'node:fs/promises'
import path from 'node:path'
import os from 'node:os'
import crypto from 'node:crypto'

import { log, die, run, envOr, COMPLETION_MARKER } from './agent-lib/utils.mjs'
import { readConfig, modelFor, selectProvider } from './agent-lib/config.mjs'
import { loadToolSchema, loadModelCapabilities, getModelCapabilities } from './agent-lib/schemas.mjs'
import { llmChat } from './agent-lib/llm.mjs'
import { parseNativeToolCall, parseJsonTextResponse } from './agent-lib/parsers.mjs'
import { buildSystemPromptNative, buildSystemPromptJsonText } from './agent-lib/prompts.mjs'

// ============================================================================
// Tool Execution
// ============================================================================

async function executeToolAction(action, sessionId, respond) {
  const act = action.action

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
    return true
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
    return true
  }

  if (act === 'search') {
    const pattern = action.pattern
    const p = action.path || '.'
    const res = run(`grep -R -n -- "${pattern.replaceAll('"', '\\"')}" "${p.replaceAll('"', '\\"')}" | head -50 || true`)
    respond({ ok: true, action: 'search', path: p, pattern, stdout: res.stdout, stderr: res.stderr })
    return true
  }

  if (act === 'run') {
    const cmd = action.cmd
    log(`run: ${cmd.slice(0, 80)}${cmd.length > 80 ? '...' : ''}`)
    const res = run(cmd)
    log(`  -> exit=${res.exitCode}`)
    respond({ ok: res.exitCode === 0, action: 'run', cmd, exitCode: res.exitCode, stdout: res.stdout, stderr: res.stderr })
    return true
  }

  if (act === 'write_file') {
    const p = action.path
    const content = String(action.content ?? '')
    log(`write: ${p} (${Buffer.byteLength(content)} bytes)`)
    await fs.mkdir(path.dirname(p), { recursive: true }).catch(() => {})
    await fs.writeFile(p, content, 'utf8')
    respond({ ok: true, action: 'write_file', path: p, bytes: Buffer.byteLength(content) })
    return true
  }

  if (act === 'apply_patch') {
    const patchText = String(action.patch ?? '')
    const tmp = path.join(os.tmpdir(), `ralph-patch-${sessionId}.patch`)
    await fs.writeFile(tmp, patchText, 'utf8')
    const res = run(`git apply --whitespace=nowarn "${tmp}"`, { timeoutMs: 60_000 })
    respond({ ok: res.exitCode === 0, action: 'apply_patch', exitCode: res.exitCode, stdout: res.stdout, stderr: res.stderr })
    return true
  }

  if (act === 'done') {
    log(`=== DONE: ${action.summary || '(no summary)'} ===`)
    console.log(COMPLETION_MARKER)
    process.exit(0)
  }

  // Unknown action
  log(`unknown action: ${act}`)
  respond({ ok: false, error: `Unknown action: ${act}` })
  return true
}

// ============================================================================
// Main Agent Loop
// ============================================================================

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

  // Load CLAUDE.md for project context (critical for non-Claude agents)
  const claudeMd = await fs.readFile('CLAUDE.md', 'utf8').catch(() => null)

  // Load git context
  const gitLog = run('git log --oneline -20 2>/dev/null || true').stdout.trim()
  const gitDiff = run('git diff HEAD~5 --stat 2>/dev/null || true').stdout.trim()

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

  // Load model capabilities and determine tool format
  const model = modelFor({ provider, config, useCase })
  const capabilities = await loadModelCapabilities()
  const { toolFormat, thinkingTags } = getModelCapabilities(model, config, provider, capabilities)

  // Load appropriate tool schema
  const nativeTools = toolFormat === 'native' ? await loadToolSchema('native') : null
  const jsonTextSchema = toolFormat === 'json_text' ? await loadToolSchema('json_text') : null

  const timeoutSeconds = Number(envOr(config, 'RALPH_LLM_TIMEOUT_SECONDS', (c) => c.llm?.timeout_seconds, '120'))

  const sessionId = crypto.randomUUID?.() ?? crypto.randomBytes(16).toString('hex')
  log(`=== AGENT START ===`)
  log(`spec: ${specPath}`)
  log(`provider: ${provider} | model: ${model}`)
  log(`toolFormat: ${toolFormat} | thinkingTags: ${thinkingTags ? thinkingTags.join('...') : 'none'}`)
  log(`timeout: ${timeoutSeconds}s | steps: unlimited (bash timeout governs)`)
  log(`CLAUDE.md: ${claudeMd ? `loaded (${claudeMd.length} chars)` : 'not found'}`)
  log(`git context: ${gitLog ? 'loaded' : 'none'}`)

  // Build system prompt based on tool format
  const system = toolFormat === 'native'
    ? buildSystemPromptNative()
    : buildSystemPromptJsonText(jsonTextSchema)

  // Build initial user message with all context
  let userContent = ''
  if (claudeMd) {
    userContent += `PROJECT CONTEXT (CLAUDE.md):\n${claudeMd}\n\n---\n\n`
  }
  if (gitLog) {
    userContent += `RECENT COMMITS:\n${gitLog}\n\n`
  }
  if (gitDiff) {
    userContent += `RECENT CHANGES:\n${gitDiff}\n\n---\n\n`
  }
  userContent += `SPEC FILE: ${specPath}\n\n${spec}\n\n`
  if (process.env.RALPH_AGENT_EXTRA_CONTEXT) {
    userContent += `---\nADDITIONAL CONTEXT (from previous failures):\n${process.env.RALPH_AGENT_EXTRA_CONTEXT}\n\n`
  }
  if (toolFormat === 'json_text') {
    userContent += `Remember: reply with a single JSON tool action.`
  }

  const messages = [
    { role: 'system', content: system },
    { role: 'user', content: userContent },
  ]

  let step = 0
  while (true) {
    step++
    log(`--- step ${step} ---`)

    let response
    try {
      response = await llmChat({
        provider, config, messages, timeoutSeconds, useCase,
        toolFormat,
        tools: nativeTools
      })
    } catch (e) {
      log(`model error: ${String(e)}`)
      process.exit(2)
    }

    // Parse the action based on tool format
    let action = null

    if (toolFormat === 'native' && response.toolCall) {
      // Native tool calling - parse from structured response
      action = parseNativeToolCall(response.toolCall)
      if (!action) {
        messages.push({ role: 'assistant', content: response.content || '' })
        messages.push({ role: 'user', content: 'Tool call parsing failed. Please try again.' })
        continue
      }
    } else {
      // JSON-in-text format - parse from content
      const modelText = response.content || ''
      try {
        action = parseJsonTextResponse(modelText)
      } catch (e) {
        messages.push({ role: 'assistant', content: modelText })
        messages.push({
          role: 'user',
          content: `Your response was not valid JSON. Reply again with EXACTLY ONE JSON object tool action. Error: ${String(e).slice(0, 200)}`,
        })
        continue
      }
    }

    const act = action?.action
    if (typeof act !== 'string' || act.length === 0) {
      if (process.env.RALPH_AGENT_DEBUG) {
        console.log('[agent] invalid response (missing action)')
      }
      messages.push({ role: 'assistant', content: response.content || '' })
      messages.push({
        role: 'user',
        content: 'INVALID RESPONSE: missing required key "action". Please call one of the available tools.',
      })
      continue
    }

    // Function to add tool result to messages
    const respond = (payload) => {
      const resultStr = JSON.stringify(payload).slice(0, 15000)

      if (toolFormat === 'native' && action._toolCallId) {
        // Native format: use tool message type
        messages.push({
          role: 'assistant',
          content: null,
          tool_calls: [{
            id: action._toolCallId,
            type: 'function',
            function: {
              name: action.action,
              arguments: JSON.stringify({ ...action, _toolCallId: undefined, action: undefined })
            }
          }]
        })
        messages.push({
          role: 'tool',
          tool_call_id: action._toolCallId,
          content: resultStr
        })
      } else {
        // JSON-text format: use user message
        messages.push({ role: 'assistant', content: JSON.stringify(action) })
        messages.push({ role: 'user', content: resultStr })
      }
    }

    // Execute the tool action
    await executeToolAction(action, sessionId, respond)
  }
  // Loop exits only via: done → exit(0), LLM error → exit(2), or bash timeout kills process
}

main().catch((e) => {
  console.error(String(e))
  process.exit(1)
})
