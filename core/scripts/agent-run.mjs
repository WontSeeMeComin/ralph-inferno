#!/usr/bin/env node
// agent-run.mjs - Lightweight local/OpenRouter coding agent for running a Ralph spec
// Supports both native OpenAI tool calling and block_text formats.
// No external deps (Node 18+).

import fs from 'node:fs/promises'
import path from 'node:path'
import os from 'node:os'
import crypto from 'node:crypto'

import { log, die, run, envOr, COMPLETION_MARKER } from './agent-lib/utils.mjs'

// Verbose mode - show full output without truncation
const VERBOSE = !!process.env.RALPH_VERBOSE

/**
 * Truncate string for logging (respects VERBOSE mode)
 * @param {string} str - String to truncate
 * @param {number} maxLen - Max length (ignored if VERBOSE)
 */
function truncLog(str, maxLen = 200) {
  if (VERBOSE || !str || str.length <= maxLen) return str
  return str.slice(0, maxLen) + `... (${str.length} chars)`
}
import { readConfig, modelFor, selectProvider } from './agent-lib/config.mjs'
import { loadToolSchema, loadModelCapabilities, getModelCapabilities } from './agent-lib/schemas.mjs'
import { llmChat } from './agent-lib/llm.mjs'
import { parseNativeToolCall, parseTextResponse, extractThoughtBlock } from './agent-lib/parsers.mjs'
import { buildSystemPromptNative, buildSystemPromptBlockText } from './agent-lib/prompts.mjs'
import { createTranscript } from './agent-lib/transcript.mjs'
import { createSandbox } from './agent-lib/sandbox.mjs'
import { createMcpManager, executeMcpTool } from './agent-lib/mcp-client.mjs'
import { buildMcpToolDocs, buildMcpToolsNative, getCuratedTool, isCuratedMcpTool } from './agent-lib/mcp-tools.mjs'
import { isAppTool, getAppTool, buildAppToolDocs, buildAppToolsNative } from './agent-lib/app-tools.mjs'
import { startApp, stopApp, takeScreenshot, getPageSnapshot, verifyWithVision, executePassThrough, getAppState } from './agent-lib/app-control.mjs'

// ============================================================================
// Tool Execution
// ============================================================================

async function executeToolAction(action, sessionId, respond, transcript = null) {
  const act = action.action

  if (act === 'read_file') {
    const p = action.path
    const start = Number(action.start_line || 1)
    const end = Number(action.end_line || start + 200)
    try {
      const raw = await fs.readFile(p, 'utf8')
      const lines = raw.split('\n')
      const slice = lines.slice(start - 1, end).map((l, i) => `${start + i}: ${l}`)
      const result = { ok: true, action: 'read_file', path: p, start_line: start, end_line: end, content: slice.join('\n') }
      respond(result)
      return result
    } catch (e) {
      const result = { ok: false, action: 'read_file', error: String(e) }
      respond(result)
      return result
    }
  }

  if (act === 'list_dir') {
    const p = action.path
    try {
      const entries = await fs.readdir(p, { withFileTypes: true })
      const result = {
        ok: true,
        action: 'list_dir',
        path: p,
        entries: entries
          .slice(0, 200)
          .map((e) => ({ name: e.name, type: e.isDirectory() ? 'dir' : 'file' })),
      }
      respond(result)
      return result
    } catch (e) {
      const result = { ok: false, action: 'list_dir', error: String(e) }
      respond(result)
      return result
    }
  }

  if (act === 'search') {
    const pattern = action.pattern
    const p = action.path || '.'
    const res = run(`grep -R -n -- "${pattern.replaceAll('"', '\\"')}" "${p.replaceAll('"', '\\"')}" | head -50 || true`)
    const result = { ok: true, action: 'search', path: p, pattern, stdout: res.stdout, stderr: res.stderr }
    respond(result)
    return result
  }

  if (act === 'run') {
    const cmd = action.cmd
    log(`run: ${truncLog(cmd, 200)}`)
    const res = run(cmd)
    log(`  -> exit=${res.exitCode}`)
    if (VERBOSE && res.stdout) log(`  stdout: ${res.stdout.slice(0, 500)}`)
    if (VERBOSE && res.stderr) log(`  stderr: ${res.stderr.slice(0, 500)}`)
    const result = { ok: res.exitCode === 0, action: 'run', cmd, exitCode: res.exitCode, stdout: res.stdout, stderr: res.stderr }
    respond(result)
    return result
  }

  if (act === 'write_file') {
    const p = action.path
    const content = String(action.content ?? '')
    log(`write: ${p} (${Buffer.byteLength(content)} bytes)`)
    await fs.mkdir(path.dirname(p), { recursive: true }).catch(() => {})
    await fs.writeFile(p, content, 'utf8')
    const result = { ok: true, action: 'write_file', path: p, bytes: Buffer.byteLength(content) }
    respond(result)
    return result
  }

  if (act === 'apply_patch') {
    const patchText = String(action.patch ?? '')
    const tmp = path.join(os.tmpdir(), `ralph-patch-${sessionId}.patch`)
    await fs.writeFile(tmp, patchText, 'utf8')
    const res = run(`git apply --whitespace=nowarn "${tmp}"`, { timeoutMs: 60_000 })
    const result = { ok: res.exitCode === 0, action: 'apply_patch', exitCode: res.exitCode, stdout: res.stdout, stderr: res.stderr }
    respond(result)
    return result
  }

  if (act === 'done') {
    log(`=== DONE: ${action.summary || '(no summary)'} ===`)
    await transcript?.complete(action.summary || '(no summary)')
    console.log(COMPLETION_MARKER)
    process.exit(0)
  }

  // Unknown action
  log(`unknown action: ${act}`)
  const result = { ok: false, error: `Unknown action: ${act}` }
  respond(result)
  return result
}

// ============================================================================
// App Tool Execution (Browser Verification)
// ============================================================================

async function executeAppToolAction(action, mcp, config) {
  const act = action.action
  const toolDef = getAppTool(act)

  if (!toolDef) {
    return { ok: false, action: act, error: `Unknown app tool: ${act}` }
  }

  // Managed tools - handled by app-control with state management
  if (toolDef.type === 'managed') {
    switch (act) {
      case 'app_start':
        return await startApp(mcp, {
          port: action.port,
          command: action.command
        })

      case 'app_stop':
        return await stopApp()

      case 'app_verify_ui':
        if (!action.criteria) {
          return { ok: false, action: act, error: 'Missing required parameter: criteria' }
        }
        return await verifyWithVision(mcp, config, action.criteria)

      default:
        return { ok: false, action: act, error: `Unknown managed tool: ${act}` }
    }
  }

  // Pass-through tools - delegate to chrome-devtools MCP
  if (toolDef.type === 'passThrough') {
    // Remove internal fields before passing to MCP
    const params = { ...action }
    delete params.action
    delete params._thought
    delete params._thoughtFormat
    delete params._toolCallId

    switch (act) {
      case 'app_screenshot':
        return await takeScreenshot(mcp, {
          fullPage: params.fullPage,
          filePath: params.filePath
        })

      case 'app_snapshot':
        return await getPageSnapshot(mcp)

      case 'app_navigate':
        return await executePassThrough(mcp, 'navigate_page', {
          url: params.url,
          type: params.type || 'url'
        })

      case 'app_click':
        return await executePassThrough(mcp, 'click', {
          uid: params.uid,
          dblClick: params.dblClick
        })

      case 'app_fill':
        return await executePassThrough(mcp, 'fill', {
          uid: params.uid,
          value: params.value
        })

      case 'app_hover':
        return await executePassThrough(mcp, 'hover', {
          uid: params.uid
        })

      case 'app_press_key':
        return await executePassThrough(mcp, 'press_key', {
          key: params.key
        })

      case 'app_wait_for':
        return await executePassThrough(mcp, 'wait_for', {
          text: params.text,
          timeout: params.timeout
        })

      default:
        return { ok: false, action: act, error: `Unknown pass-through tool: ${act}` }
    }
  }

  return { ok: false, action: act, error: `Invalid tool type for: ${act}` }
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
  const { toolFormat: rawToolFormat, thinkingTags } = getModelCapabilities(model, config, provider, capabilities)

  // Normalize json_text -> block_text (backwards compatibility)
  const toolFormat = rawToolFormat === 'json_text' ? 'block_text' : rawToolFormat

  // Load appropriate tool schema
  const nativeTools = toolFormat === 'native' ? await loadToolSchema('native') : null
  const blockTextSchema = toolFormat === 'block_text' ? await loadToolSchema('block_text') : null

  const timeoutSeconds = Number(envOr(config, 'RALPH_LLM_TIMEOUT_SECONDS', (c) => c.llm?.timeout_seconds, '120'))

  const sessionId = crypto.randomUUID?.() ?? crypto.randomBytes(16).toString('hex')

  // Initialize sandbox for command gating
  const sandbox = createSandbox({
    mode: process.env.RALPH_SANDBOX_MODE || 'permissive',
    projectRoot: process.cwd()
  })

  // Initialize MCP servers for external tool access (documentation, web search, browser)
  const mcpEnabled = process.env.RALPH_MCP !== '0'
  const browserEnabled = process.env.RALPH_BROWSER !== '0'
  const mcpServers = ['context7', 'perplexity']
  if (browserEnabled) {
    mcpServers.push('chromeDevtools')
  }
  const mcp = mcpEnabled ? await createMcpManager(mcpServers, config) : null

  // Initialize transcript for session logging (enabled in local mode)
  const transcript = process.env.RALPH_TRANSCRIPT
    ? createTranscript(sessionId)
    : null

  const verbose = !!process.env.RALPH_VERBOSE
  const dryRun = !!process.env.RALPH_DRY_RUN

  log(`=== AGENT START ===`)
  log(`spec: ${specPath}`)
  log(`provider: ${provider} | model: ${model}`)
  log(`toolFormat: ${toolFormat} | thinkingTags: ${JSON.stringify(thinkingTags[0])}`)
  log(`timeout: ${timeoutSeconds}s | steps: unlimited (bash timeout governs)`)
  log(`sandbox: ${sandbox.mode} | transcript: ${transcript ? 'enabled' : 'disabled'}`)
  log(`mcp: ${mcp ? Object.keys(mcp.clients).join(', ') || 'no servers' : 'disabled'}`)
  log(`browser: ${(browserEnabled && mcp?.clients?.chromeDevtools) ? 'enabled' : 'disabled'}`)
  log(`CLAUDE.md: ${claudeMd ? `loaded (${claudeMd.length} chars)` : 'not found'}`)
  log(`git context: ${gitLog ? 'loaded' : 'none'}`)

  // Log session start to transcript
  if (transcript) {
    await transcript.start({
      spec: specPath,
      provider,
      model,
      toolFormat,
      sandboxMode: sandbox.mode
    })
  }

  // Build MCP tool documentation if MCP is enabled
  const mcpToolDocs = mcp ? buildMcpToolDocs() : ''

  // Build app tool documentation if browser is enabled
  const appToolDocs = (browserEnabled && mcp?.clients?.chromeDevtools) ? buildAppToolDocs() : ''

  // Build system prompt based on tool format (with MCP docs and app docs if available)
  const combinedExtraDocs = mcpToolDocs + appToolDocs
  const system = toolFormat === 'native'
    ? buildSystemPromptNative(combinedExtraDocs)
    : buildSystemPromptBlockText(blockTextSchema, combinedExtraDocs)

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
  if (toolFormat === 'block_text') {
    userContent += `Remember: First output your [THOUGHT], then use a tool with [tool_name]...[/tool_name] format.`
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
      // Merge MCP tools, app tools with native tools if using native format
      const mcpNativeTools = mcp ? buildMcpToolsNative() : []
      const appNativeTools = (browserEnabled && mcp?.clients?.chromeDevtools) ? buildAppToolsNative() : []
      const allExtraTools = [...mcpNativeTools, ...appNativeTools]
      const allNativeTools = nativeTools ? [...nativeTools, ...allExtraTools] : allExtraTools.length > 0 ? allExtraTools : null

      response = await llmChat({
        provider, config, messages, timeoutSeconds, useCase,
        toolFormat,
        tools: allNativeTools
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

      // Extract thought from content if present (native format may still include thoughts)
      if (response.content) {
        const { thought, format: thoughtFormat } = extractThoughtBlock(response.content, thinkingTags)
        if (thought && action) {
          action._thought = thought
          action._thoughtFormat = thoughtFormat
          log(`[THOUGHT] ${truncLog(thought, 300)}`)
          if (verbose) {
            console.log(`\n${thoughtFormat || '[THOUGHT]'}\n${thought}\n${thoughtFormat ? thoughtFormat.replace('<', '</') : '[/THOUGHT]'}\n`)
          }
          await transcript?.thought(step, thought, thoughtFormat)
        }
      }

      if (!action) {
        messages.push({ role: 'assistant', content: response.content || '' })
        messages.push({ role: 'user', content: 'Tool call parsing failed. Please try again with a valid tool call.' })
        continue
      }
    } else {
      // Block-text format - parse from content
      const modelText = response.content || ''
      try {
        action = parseTextResponse(modelText, true, thinkingTags) // preferBlockText=true, pass thinkingTags

        // Log thought if present
        if (action._thought) {
          log(`[THOUGHT] ${truncLog(action._thought, 300)}`)
          if (verbose) {
            const fmt = action._thoughtFormat || '[THOUGHT]'
            console.log(`\n${fmt}\n${action._thought}\n${fmt.replace('<', '</').replace('[', '[/')}\n`)
          }
          await transcript?.thought(step, action._thought, action._thoughtFormat)
        }
      } catch (e) {
        messages.push({ role: 'assistant', content: modelText })
        messages.push({
          role: 'user',
          content: `Your response was not in the expected format. Please use:

[THOUGHT]
Your reasoning here
[/THOUGHT]

<tool_code>
[tool_name]
param: value
[/tool_name]
</tool_code>

Error: ${String(e).slice(0, 200)}`,
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
        content: 'INVALID RESPONSE: missing required action. Please call one of the available tools using the correct format.',
      })
      continue
    }

    // Sandbox gating for run commands
    if (action.action === 'run') {
      const check = sandbox.isCommandAllowed(action.cmd)
      if (!check.allowed) {
        log(`BLOCKED: ${VERBOSE ? action.cmd : truncLog(action.cmd, 200)} - ${check.reason}`)
        await transcript?.blocked(step, action.cmd, check.reason)

        // Add to messages so model knows it was blocked
        messages.push({ role: 'assistant', content: `<tool_code>\n[run]\ncmd: ${action.cmd}\n[/run]\n</tool_code>` })
        messages.push({ role: 'user', content: JSON.stringify({ ok: false, error: `Command blocked by sandbox: ${check.reason}` }) })
        continue
      }
      if (check.shouldLog) {
        log(`[sandbox] ${VERBOSE ? action.cmd : truncLog(action.cmd, 200)}`)
      }
    }

    // Dry-run mode: log but don't execute
    if (dryRun && ['run', 'write_file', 'apply_patch'].includes(action.action)) {
      log(`DRY-RUN: ${action.action} - ${truncLog(JSON.stringify(action), 300)}`)
      await transcript?.toolCall(step, action.action, action)
      await transcript?.toolResult(step, action.action, { ok: true, dryRun: true }, 0)

      messages.push({ role: 'assistant', content: `<tool_code>\n[${action.action}]\n...\n[/${action.action}]\n</tool_code>` })
      messages.push({ role: 'user', content: JSON.stringify({ ok: true, dryRun: true, message: 'Dry run - command not executed' }) })
      continue
    }

    // Check if this is a curated MCP tool (mcp_docs, mcp_search_web, etc.)
    if (mcp && isCuratedMcpTool(action.action)) {
      const toolDef = getCuratedTool(action.action)
      const { messages: mcpMessages } = await executeMcpTool(mcp, action, toolDef, toolFormat, transcript, step)
      messages.push(...mcpMessages)
      continue
    }

    // Check if this is an app_* tool (browser verification)
    if (isAppTool(action.action)) {
      const startTime = Date.now()
      await transcript?.toolCall(step, action.action, action)

      let result
      try {
        result = await executeAppToolAction(action, mcp, config)
      } catch (e) {
        result = { ok: false, action: action.action, error: String(e) }
      }

      const resultStr = JSON.stringify(result).slice(0, 15000)
      await transcript?.toolResult(step, action.action, result, Date.now() - startTime)

      if (toolFormat === 'native' && action._toolCallId) {
        const assistantContent = action._thought ? `[THOUGHT]\n${action._thought}\n[/THOUGHT]` : null
        messages.push({
          role: 'assistant',
          content: assistantContent,
          tool_calls: [{ id: action._toolCallId, type: 'function', function: { name: action.action, arguments: JSON.stringify(action) } }]
        })
        messages.push({ role: 'tool', tool_call_id: action._toolCallId, content: resultStr })
      } else {
        let assistantContent = action._thought ? `[THOUGHT]\n${action._thought}\n[/THOUGHT]\n\n` : ''
        assistantContent += `<tool_code>\n[${action.action}]\n`
        for (const [k, v] of Object.entries(action)) {
          if (k === 'action' || k === '_thought' || k === '_thoughtFormat' || k === '_toolCallId') continue
          assistantContent += typeof v === 'object' ? `${k}: ${JSON.stringify(v)}\n` : `${k}: ${v}\n`
        }
        assistantContent += `[/${action.action}]\n</tool_code>`
        messages.push({ role: 'assistant', content: assistantContent })
        messages.push({ role: 'user', content: resultStr })
      }
      continue
    }

    // Log tool call details
    log(`tool: ${action.action}`)
    if (VERBOSE) {
      const params = { ...action }
      delete params.action
      delete params._thought
      delete params._thoughtFormat
      delete params._toolCallId
      if (Object.keys(params).length > 0) {
        log(`  params: ${JSON.stringify(params, null, 2).split('\n').join('\n  ')}`)
      }
    }

    // Function to add tool result to messages
    const respond = (payload) => {
      // Log result in verbose mode
      if (VERBOSE) {
        log(`  result: ${JSON.stringify(payload, null, 2).split('\n').join('\n  ')}`)
      }
      const resultStr = JSON.stringify(payload).slice(0, 15000)

      if (toolFormat === 'native' && action._toolCallId) {
        // Native format: use tool message type
        // Include thought in assistant content if present
        const assistantContent = action._thought ? `[THOUGHT]\n${action._thought}\n[/THOUGHT]` : null
        messages.push({
          role: 'assistant',
          content: assistantContent,
          tool_calls: [{
            id: action._toolCallId,
            type: 'function',
            function: {
              name: action.action,
              arguments: JSON.stringify({ ...action, _toolCallId: undefined, action: undefined, _thought: undefined, _thoughtFormat: undefined })
            }
          }]
        })
        messages.push({
          role: 'tool',
          tool_call_id: action._toolCallId,
          content: resultStr
        })
      } else {
        // Block-text format: preserve thought in assistant message
        let assistantContent = ''
        if (action._thought) {
          assistantContent += `[THOUGHT]\n${action._thought}\n[/THOUGHT]\n\n`
        }
        // Reconstruct the tool call in block format for history
        assistantContent += `<tool_code>\n[${action.action}]\n`
        for (const [k, v] of Object.entries(action)) {
          if (k === 'action' || k === '_thought' || k === '_thoughtFormat') continue
          if (typeof v === 'string' && v.includes('\n')) {
            assistantContent += `${k}:\n${v}\n`
          } else {
            assistantContent += `${k}: ${v}\n`
          }
        }
        assistantContent += `[/${action.action}]\n</tool_code>`

        messages.push({ role: 'assistant', content: assistantContent })
        messages.push({ role: 'user', content: resultStr })
      }
    }

    // Log tool call to transcript before execution
    const startTime = Date.now()
    await transcript?.toolCall(step, action.action, action)

    // Execute the tool action (pass transcript for done action)
    const result = await executeToolAction(action, sessionId, respond, transcript)

    // Log result to transcript after execution
    await transcript?.toolResult(step, action.action, result || {}, Date.now() - startTime)
  }
  // Loop exits only via: done → exit(0), LLM error → exit(2), or bash timeout kills process
}

main().catch((e) => {
  console.error(String(e))
  process.exit(1)
})
