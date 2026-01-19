// agent-lib/mcp-client.mjs - MCP server connection & tool execution
// Connects to MCP servers (Context7, Perplexity) for documentation lookup and web search.
// Supports 3-tier API key lookup: env → .ralph/config.json → ~/.claude.json

import fs from 'node:fs/promises'
import path from 'node:path'
import os from 'node:os'
import { log } from './utils.mjs'

/**
 * Load API key with 3-tier precedence:
 * 1. Environment variable (VM deployment)
 * 2. .ralph/config.json → mcp.api_keys.{name} (project config)
 * 3. ~/.claude.json → mcpServers.{serverName}.env.{envVar} (local dev)
 */
async function loadApiKey(envVar, configKey, claudeServerName, ralphConfig) {
  // Tier 1: Environment variable
  if (process.env[envVar]) {
    log(`MCP: ${envVar} from environment`)
    return process.env[envVar]
  }

  // Tier 2: .ralph/config.json
  const configValue = ralphConfig?.mcp?.api_keys?.[configKey]
  if (configValue) {
    log(`MCP: ${envVar} from .ralph/config.json`)
    return configValue
  }

  // Tier 3: ~/.claude.json
  try {
    const claudePath = path.join(os.homedir(), '.claude.json')
    const raw = await fs.readFile(claudePath, 'utf8')
    const claudeConfig = JSON.parse(raw)
    const serverEnv = claudeConfig?.mcpServers?.[claudeServerName]?.env
    if (serverEnv?.[envVar]) {
      log(`MCP: ${envVar} from ~/.claude.json`)
      return serverEnv[envVar]
    }
  } catch {
    // ~/.claude.json not found or parse error - that's fine
  }

  return null
}

/**
 * MCP Server configurations
 */
const MCP_SERVERS = {
  context7: {
    command: 'npx',
    args: ['-y', '@upstash/context7-mcp@latest'],
    claudeServerName: 'Context7', // Name in ~/.claude.json
    description: 'Documentation lookup for libraries and frameworks'
  },
  perplexity: {
    command: 'npx',
    args: ['-y', 'server-perplexity-ask'],
    claudeServerName: 'perplexity-ask', // Name in ~/.claude.json
    envVar: 'PERPLEXITY_API_KEY',
    configKey: 'perplexity',
    description: 'Web search via Perplexity AI'
  },
  chromeDevtools: {
    command: 'npx',
    args: ['-y', '@anthropic/chrome-devtools-mcp@latest'],
    claudeServerName: 'chrome-devtools', // Name in ~/.claude.json
    description: 'Browser automation via Chrome DevTools'
  }
}

/**
 * Dynamically import MCP SDK
 * Returns null if SDK is not installed (graceful degradation)
 */
async function loadMcpSdk() {
  try {
    const { Client } = await import('@modelcontextprotocol/sdk/client/index.js')
    const { StdioClientTransport } = await import('@modelcontextprotocol/sdk/client/stdio.js')
    return { Client, StdioClientTransport }
  } catch (e) {
    log(`MCP: SDK not installed (npm install @modelcontextprotocol/sdk)`)
    return null
  }
}

/**
 * Create an MCP manager that handles multiple server connections
 * @param {string[]} enabledServers - List of server names to connect to
 * @param {object} ralphConfig - Ralph config from .ralph/config.json
 * @returns {Promise<McpManager|null>} - MCP manager or null if unavailable
 */
export async function createMcpManager(enabledServers = ['context7', 'perplexity'], ralphConfig = {}) {
  const sdk = await loadMcpSdk()
  if (!sdk) return null

  const { Client, StdioClientTransport } = sdk
  const clients = {}
  const toolRegistry = {} // Maps tool name -> { server, schema }

  for (const name of enabledServers) {
    const serverConfig = MCP_SERVERS[name]
    if (!serverConfig) {
      log(`MCP: Unknown server "${name}", skipping`)
      continue
    }

    // Load API key if required
    let apiKey = null
    if (serverConfig.envVar) {
      apiKey = await loadApiKey(
        serverConfig.envVar,
        serverConfig.configKey,
        serverConfig.claudeServerName,
        ralphConfig
      )
      if (!apiKey) {
        log(`MCP: ${name} skipped (${serverConfig.envVar} not found)`)
        continue
      }
    }

    try {
      const client = new Client(
        { name: 'ralph-agent', version: '1.0.0' },
        { capabilities: {} }
      )

      // Build env with API key if present
      const env = { ...process.env }
      if (apiKey && serverConfig.envVar) {
        env[serverConfig.envVar] = apiKey
      }

      const transport = new StdioClientTransport({
        command: serverConfig.command,
        args: serverConfig.args,
        env
      })

      await client.connect(transport)
      clients[name] = client

      // Register tools from this server
      const { tools } = await client.listTools()
      for (const tool of tools) {
        toolRegistry[tool.name] = { server: name, schema: tool }
      }

      log(`MCP: ${name} connected (${tools.length} tools)`)
    } catch (e) {
      log(`MCP: ${name} failed - ${e.message}`)
    }
  }

  if (Object.keys(clients).length === 0) {
    log(`MCP: No servers connected`)
    return null
  }

  return {
    clients,
    toolRegistry,

    /**
     * Call a tool on a specific server
     * @param {string} serverName - Server name (e.g., 'context7')
     * @param {string} toolName - Tool name on that server
     * @param {object} args - Arguments for the tool
     */
    async callServerTool(serverName, toolName, args) {
      const client = clients[serverName]
      if (!client) {
        throw new Error(`MCP server not connected: ${serverName}`)
      }

      const result = await client.callTool({ name: toolName, arguments: args })

      // Extract text content from MCP response format
      if (Array.isArray(result.content)) {
        const textParts = result.content
          .filter(c => c.type === 'text')
          .map(c => c.text)
        return { content: textParts.join('\n'), raw: result }
      }

      return { content: result.content, raw: result }
    },

    /**
     * Gracefully close all MCP connections
     */
    async close() {
      for (const [name, client] of Object.entries(clients)) {
        try {
          await client.close()
          log(`MCP: ${name} disconnected`)
        } catch {
          // Ignore close errors
        }
      }
    }
  }
}

/**
 * Execute a curated MCP tool call and format the result for the agent
 * @param {object} mcp - MCP manager instance
 * @param {object} action - Tool action with action name and params
 * @param {object} toolDef - Curated tool definition from mcp-tools.mjs
 * @param {string} toolFormat - 'native' or 'block_text'
 * @param {object} transcript - Optional transcript logger
 * @param {number} step - Current step number
 * @returns {Promise<{messages: Array, payload: object}>}
 */
export async function executeMcpTool(mcp, action, toolDef, toolFormat, transcript, step) {
  log(`MCP: ${action.action} -> ${toolDef.mcpServer}/${toolDef.mcpTool}`)
  await transcript?.toolCall(step, action.action, action)
  const startTime = Date.now()

  // Extract params (remove internal fields)
  const mcpArgs = { ...action }
  delete mcpArgs.action
  delete mcpArgs._thought
  delete mcpArgs._thoughtFormat
  delete mcpArgs._toolCallId

  const messages = []

  try {
    const result = await mcp.callServerTool(toolDef.mcpServer, toolDef.mcpTool, mcpArgs)
    const payload = { ok: true, action: action.action, content: result.content }
    const resultStr = JSON.stringify(payload).slice(0, 15000)

    if (toolFormat === 'native' && action._toolCallId) {
      const assistantContent = action._thought ? `[THOUGHT]\n${action._thought}\n[/THOUGHT]` : null
      messages.push({
        role: 'assistant',
        content: assistantContent,
        tool_calls: [{
          id: action._toolCallId,
          type: 'function',
          function: { name: action.action, arguments: JSON.stringify(mcpArgs) }
        }]
      })
      messages.push({ role: 'tool', tool_call_id: action._toolCallId, content: resultStr })
    } else {
      let assistantContent = action._thought ? `[THOUGHT]\n${action._thought}\n[/THOUGHT]\n\n` : ''
      assistantContent += `<tool_code>\n[${action.action}]\n`
      for (const [k, v] of Object.entries(mcpArgs)) {
        assistantContent += typeof v === 'object' ? `${k}: ${JSON.stringify(v)}\n` : `${k}: ${v}\n`
      }
      assistantContent += `[/${action.action}]\n</tool_code>`
      messages.push({ role: 'assistant', content: assistantContent })
      messages.push({ role: 'user', content: resultStr })
    }

    await transcript?.toolResult(step, action.action, payload, Date.now() - startTime)
    return { messages, payload }
  } catch (e) {
    const payload = { ok: false, action: action.action, error: String(e) }
    const resultStr = JSON.stringify(payload)

    if (toolFormat === 'native' && action._toolCallId) {
      messages.push({
        role: 'assistant',
        content: null,
        tool_calls: [{ id: action._toolCallId, type: 'function', function: { name: action.action, arguments: '{}' } }]
      })
      messages.push({ role: 'tool', tool_call_id: action._toolCallId, content: resultStr })
    } else {
      messages.push({ role: 'assistant', content: `<tool_code>\n[${action.action}]\n[/${action.action}]\n</tool_code>` })
      messages.push({ role: 'user', content: resultStr })
    }

    await transcript?.toolResult(step, action.action, payload, Date.now() - startTime)
    log(`MCP error: ${e}`)
    return { messages, payload }
  }
}
