// agent-lib/app-control.mjs - Deterministic app state management for browser verification
// Manages dev server lifecycle and browser state. Agent calls high-level tools, this handles processes.

import { spawn } from 'node:child_process'
import net from 'node:net'
import { log } from './utils.mjs'
import { llmVision } from './llm.mjs'

/**
 * Internal state tracked by deterministic layer
 * Agent never sees or manipulates this directly
 */
let appState = {
  serverProcess: null,
  serverPid: null,
  serverPort: 5173,
  serverCommand: 'npm run dev',
  browserPageId: null,
  mcpClient: null,
  startTime: null
}

/**
 * Wait for a port to become available
 * @param {number} port - Port to check
 * @param {number} timeoutMs - Timeout in milliseconds
 * @returns {Promise<boolean>} - True if port becomes available
 */
async function waitForPort(port, timeoutMs = 10000) {
  const start = Date.now()
  const checkInterval = 250

  while (Date.now() - start < timeoutMs) {
    try {
      await new Promise((resolve, reject) => {
        const socket = new net.Socket()
        socket.setTimeout(1000)
        socket.once('connect', () => {
          socket.destroy()
          resolve(true)
        })
        socket.once('timeout', () => {
          socket.destroy()
          reject(new Error('timeout'))
        })
        socket.once('error', reject)
        socket.connect(port, 'localhost')
      })
      return true
    } catch {
      await new Promise(r => setTimeout(r, checkInterval))
    }
  }
  return false
}

/**
 * Check if a port is in use
 * @param {number} port - Port to check
 * @returns {Promise<boolean>} - True if port is in use
 */
async function isPortInUse(port) {
  return new Promise((resolve) => {
    const socket = new net.Socket()
    socket.setTimeout(1000)
    socket.once('connect', () => {
      socket.destroy()
      resolve(true)
    })
    socket.once('timeout', () => {
      socket.destroy()
      resolve(false)
    })
    socket.once('error', () => {
      socket.destroy()
      resolve(false)
    })
    socket.connect(port, 'localhost')
  })
}

/**
 * Start the dev server and open browser
 * @param {object} mcp - MCP manager instance (must have chromeDevtools connected)
 * @param {object} options - Start options
 * @returns {Promise<object>} - Result with ok, port, pageId
 */
export async function startApp(mcp, options = {}) {
  const port = options.port || 5173
  const command = options.command || 'npm run dev'

  // Check if app already started
  if (appState.serverProcess) {
    log(`app_control: App already running on port ${appState.serverPort}`)
    return {
      ok: true,
      action: 'app_start',
      port: appState.serverPort,
      pageId: appState.browserPageId,
      message: 'App already running'
    }
  }

  // Check if port is already in use (maybe dev server from previous session)
  if (await isPortInUse(port)) {
    log(`app_control: Port ${port} already in use, will use existing server`)
  } else {
    // Start dev server
    log(`app_control: Starting dev server with "${command}" on port ${port}`)

    // Parse command for spawn
    const parts = command.split(' ')
    const cmd = parts[0]
    const args = parts.slice(1)

    try {
      const server = spawn(cmd, args, {
        detached: true,
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, PORT: String(port) }
      })

      appState.serverProcess = server
      appState.serverPid = server.pid
      appState.serverPort = port
      appState.serverCommand = command
      appState.startTime = Date.now()

      // Log server output for debugging
      server.stdout?.on('data', (data) => {
        const str = data.toString().trim()
        if (str) log(`[dev-server] ${str.slice(0, 200)}`)
      })
      server.stderr?.on('data', (data) => {
        const str = data.toString().trim()
        if (str) log(`[dev-server:err] ${str.slice(0, 200)}`)
      })

      server.on('error', (err) => {
        log(`app_control: Server process error: ${err.message}`)
      })

      server.on('exit', (code) => {
        log(`app_control: Server exited with code ${code}`)
        appState.serverProcess = null
        appState.serverPid = null
      })

      // Wait for server to be ready
      log(`app_control: Waiting for port ${port} to become available...`)
      const ready = await waitForPort(port, 15000)
      if (!ready) {
        // Kill the process if it didn't start properly
        await stopApp()
        return {
          ok: false,
          action: 'app_start',
          error: `Server did not start within 15s. Check that "${command}" is valid.`
        }
      }

      log(`app_control: Dev server ready on port ${port}`)
    } catch (e) {
      return {
        ok: false,
        action: 'app_start',
        error: `Failed to start server: ${e.message}`
      }
    }
  }

  // Open browser via chrome-devtools MCP
  if (mcp?.clients?.chromeDevtools) {
    try {
      log(`app_control: Opening browser at http://localhost:${port}`)
      const result = await mcp.callServerTool('chromeDevtools', 'new_page', {
        url: `http://localhost:${port}`
      })

      // Extract pageId from result
      const pageId = extractPageId(result)
      appState.browserPageId = pageId
      appState.mcpClient = mcp

      log(`app_control: Browser opened, pageId=${pageId}`)

      return {
        ok: true,
        action: 'app_start',
        port,
        pageId,
        message: `Dev server running on port ${port}, browser opened`
      }
    } catch (e) {
      log(`app_control: Failed to open browser: ${e.message}`)
      // Server is running but browser failed - still partially successful
      return {
        ok: true,
        action: 'app_start',
        port,
        pageId: null,
        warning: `Server running but browser failed: ${e.message}`
      }
    }
  } else {
    log(`app_control: chromeDevtools MCP not connected, skipping browser`)
    return {
      ok: true,
      action: 'app_start',
      port,
      pageId: null,
      warning: 'chromeDevtools MCP not connected, browser not opened'
    }
  }
}

/**
 * Stop the dev server and close browser
 * @returns {Promise<object>} - Result with ok status
 */
export async function stopApp() {
  const results = { browserClosed: false, serverStopped: false }

  // Close browser page
  if (appState.browserPageId !== null && appState.mcpClient) {
    try {
      await appState.mcpClient.callServerTool('chromeDevtools', 'close_page', {
        pageId: appState.browserPageId
      })
      results.browserClosed = true
      log(`app_control: Browser page closed`)
    } catch (e) {
      log(`app_control: Failed to close browser: ${e.message}`)
    }
  }

  // Kill dev server
  if (appState.serverProcess) {
    try {
      // Kill the process group (detached process)
      if (appState.serverPid) {
        process.kill(-appState.serverPid, 'SIGTERM')
      }
      appState.serverProcess.kill('SIGTERM')
      results.serverStopped = true
      log(`app_control: Dev server stopped (pid ${appState.serverPid})`)
    } catch (e) {
      log(`app_control: Failed to stop server: ${e.message}`)
      // Try SIGKILL as fallback
      try {
        if (appState.serverPid) {
          process.kill(-appState.serverPid, 'SIGKILL')
        }
        results.serverStopped = true
      } catch {
        // Process might already be dead
      }
    }
  }

  // Reset state
  const prevPort = appState.serverPort
  appState = {
    serverProcess: null,
    serverPid: null,
    serverPort: 5173,
    serverCommand: 'npm run dev',
    browserPageId: null,
    mcpClient: null,
    startTime: null
  }

  return {
    ok: true,
    action: 'app_stop',
    ...results,
    message: `App stopped (was on port ${prevPort})`
  }
}

/**
 * Take a screenshot of the current page
 * @param {object} mcp - MCP manager instance
 * @param {object} options - Screenshot options
 * @returns {Promise<object>} - Result with base64 image data
 */
export async function takeScreenshot(mcp, options = {}) {
  if (!mcp?.clients?.chromeDevtools) {
    return {
      ok: false,
      action: 'app_screenshot',
      error: 'chromeDevtools MCP not connected'
    }
  }

  if (appState.browserPageId === null) {
    return {
      ok: false,
      action: 'app_screenshot',
      error: 'No browser page open. Call app_start first.'
    }
  }

  try {
    const result = await mcp.callServerTool('chromeDevtools', 'take_screenshot', {
      fullPage: options.fullPage ?? true,
      filePath: options.filePath
    })

    // Extract base64 image data from result
    const imageBase64 = extractImageBase64(result)

    return {
      ok: true,
      action: 'app_screenshot',
      imageBase64,
      path: options.filePath || null,
      fullPage: options.fullPage ?? true
    }
  } catch (e) {
    return {
      ok: false,
      action: 'app_screenshot',
      error: `Screenshot failed: ${e.message}`
    }
  }
}

/**
 * Get accessibility tree snapshot of current page
 * @param {object} mcp - MCP manager instance
 * @returns {Promise<object>} - Result with page snapshot
 */
export async function getPageSnapshot(mcp) {
  if (!mcp?.clients?.chromeDevtools) {
    return {
      ok: false,
      action: 'app_snapshot',
      error: 'chromeDevtools MCP not connected'
    }
  }

  if (appState.browserPageId === null) {
    return {
      ok: false,
      action: 'app_snapshot',
      error: 'No browser page open. Call app_start first.'
    }
  }

  try {
    const result = await mcp.callServerTool('chromeDevtools', 'take_snapshot', {})
    return {
      ok: true,
      action: 'app_snapshot',
      snapshot: result.content || result
    }
  } catch (e) {
    return {
      ok: false,
      action: 'app_snapshot',
      error: `Snapshot failed: ${e.message}`
    }
  }
}

/**
 * Verify UI with vision model
 * Takes screenshot and sends to vision model for analysis
 * @param {object} mcp - MCP manager instance
 * @param {object} config - Ralph config
 * @param {string} criteria - What to verify
 * @returns {Promise<object>} - Result with pass/fail and analysis
 */
export async function verifyWithVision(mcp, config, criteria) {
  // Take screenshot first
  const screenshot = await takeScreenshot(mcp, { fullPage: true })
  if (!screenshot.ok) {
    return {
      ok: false,
      action: 'app_verify_ui',
      error: screenshot.error
    }
  }

  if (!screenshot.imageBase64) {
    return {
      ok: false,
      action: 'app_verify_ui',
      error: 'Screenshot returned no image data'
    }
  }

  // Build vision prompt
  const visionPrompt = `Analyze this screenshot of a web application.

Verify the following criteria:
${criteria}

Respond with:
- PASS: if all criteria are met
- FAIL: if any criteria are not met, explain what's wrong

Be specific about what you see. If the page appears blank or shows an error, that's a FAIL.`

  try {
    // Send to vision model
    const analysis = await llmVision(config, visionPrompt, screenshot.imageBase64)

    const passed = analysis.toUpperCase().includes('PASS') && !analysis.toUpperCase().includes('FAIL')

    log(`app_control: Vision verification ${passed ? 'PASSED' : 'FAILED'}`)

    return {
      ok: true,
      action: 'app_verify_ui',
      criteria,
      analysis,
      passed,
      message: passed ? 'All criteria verified' : 'Verification failed - see analysis'
    }
  } catch (e) {
    // Vision failed - fall back to snapshot text verification
    log(`app_control: Vision failed (${e.message}), falling back to snapshot`)

    const snapshot = await getPageSnapshot(mcp)
    if (snapshot.ok) {
      return {
        ok: true,
        action: 'app_verify_ui',
        criteria,
        analysis: `Vision model unavailable. Snapshot content:\n${JSON.stringify(snapshot.snapshot).slice(0, 2000)}`,
        passed: false,
        warning: 'Vision model unavailable, manual verification needed',
        snapshot: snapshot.snapshot
      }
    }

    return {
      ok: false,
      action: 'app_verify_ui',
      error: `Vision failed: ${e.message}`
    }
  }
}

/**
 * Execute a pass-through chrome-devtools tool
 * Ensures app is started before delegating
 * @param {object} mcp - MCP manager instance
 * @param {string} toolName - chrome-devtools tool name
 * @param {object} params - Tool parameters
 * @returns {Promise<object>} - Tool result
 */
export async function executePassThrough(mcp, toolName, params) {
  if (!mcp?.clients?.chromeDevtools) {
    return {
      ok: false,
      error: 'chromeDevtools MCP not connected'
    }
  }

  if (appState.browserPageId === null) {
    return {
      ok: false,
      error: 'No browser page open. Call app_start first.'
    }
  }

  try {
    const result = await mcp.callServerTool('chromeDevtools', toolName, params)
    return {
      ok: true,
      ...result
    }
  } catch (e) {
    return {
      ok: false,
      error: `${toolName} failed: ${e.message}`
    }
  }
}

/**
 * Get current app state (for debugging/status)
 */
export function getAppState() {
  return {
    running: appState.serverProcess !== null,
    port: appState.serverPort,
    browserOpen: appState.browserPageId !== null,
    pageId: appState.browserPageId,
    uptime: appState.startTime ? Date.now() - appState.startTime : 0
  }
}

// ============================================================================
// Helper functions
// ============================================================================

/**
 * Extract pageId from MCP new_page result
 */
function extractPageId(result) {
  // Result format may vary - handle common cases
  if (typeof result === 'object') {
    if (result.pageId !== undefined) return result.pageId
    if (result.content?.pageId !== undefined) return result.content.pageId
    if (result.raw?.pageId !== undefined) return result.raw.pageId
    // Try parsing content as JSON
    if (typeof result.content === 'string') {
      try {
        const parsed = JSON.parse(result.content)
        if (parsed.pageId !== undefined) return parsed.pageId
      } catch { /* not JSON */ }
    }
  }
  // Default to 0 (first page)
  return 0
}

/**
 * Extract base64 image data from screenshot result
 */
function extractImageBase64(result) {
  if (typeof result === 'object') {
    // Direct base64 data
    if (result.data) return result.data
    if (result.imageBase64) return result.imageBase64

    // Nested in content
    if (result.content?.data) return result.content.data

    // Raw MCP response format
    if (result.raw?.content) {
      for (const item of result.raw.content) {
        if (item.type === 'image' && item.data) return item.data
      }
    }

    // Content might be the base64 string directly
    if (typeof result.content === 'string' && result.content.length > 1000) {
      // Likely base64 data
      return result.content
    }
  }
  return null
}
