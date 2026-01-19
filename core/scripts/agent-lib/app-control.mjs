// agent-lib/app-control.mjs - App state management facade
// Orchestrates server, browser, and vision modules. Maintains shared state.

import { log } from './utils.mjs'
import { startServer, stopServer } from './app-server.mjs'
import {
  openBrowser,
  closeBrowser,
  takeScreenshot as browserTakeScreenshot,
  getPageSnapshot as browserGetPageSnapshot,
  executePassThrough as browserExecutePassThrough
} from './app-browser.mjs'
import { verifyWithVision } from './app-vision.mjs'

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
 * Reset state to defaults
 */
function resetState() {
  appState = {
    serverProcess: null,
    serverPid: null,
    serverPort: 5173,
    serverCommand: 'npm run dev',
    browserPageId: null,
    mcpClient: null,
    startTime: null
  }
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
    log(`app-control: App already running on port ${appState.serverPort}`)
    return {
      ok: true,
      action: 'app_start',
      port: appState.serverPort,
      pageId: appState.browserPageId,
      message: 'App already running'
    }
  }

  // Start dev server
  const serverResult = await startServer(command, port, (code) => {
    // On exit callback - reset server state
    appState.serverProcess = null
    appState.serverPid = null
  })

  if (serverResult.error) {
    return {
      ok: false,
      action: 'app_start',
      error: serverResult.error
    }
  }

  // Update state (handles both new server and existing server cases)
  if (!serverResult.existingServer) {
    appState.serverProcess = serverResult.process
    appState.serverPid = serverResult.pid
  }
  appState.serverPort = port
  appState.serverCommand = command
  appState.startTime = Date.now()

  // Open browser via chrome-devtools MCP
  if (mcp?.clients?.chromeDevtools) {
    const browserResult = await openBrowser(mcp, `http://localhost:${port}`)

    if (browserResult.error) {
      // Server is running but browser failed - still partially successful
      return {
        ok: true,
        action: 'app_start',
        port,
        pageId: null,
        warning: browserResult.error
      }
    }

    appState.browserPageId = browserResult.pageId
    appState.mcpClient = mcp

    return {
      ok: true,
      action: 'app_start',
      port,
      pageId: browserResult.pageId,
      message: `Dev server running on port ${port}, browser opened`
    }
  } else {
    log(`app-control: chromeDevtools MCP not connected, skipping browser`)
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
  const prevPort = appState.serverPort

  // Close browser page
  if (appState.browserPageId !== null && appState.mcpClient) {
    results.browserClosed = await closeBrowser(appState.mcpClient, appState.browserPageId)
  }

  // Kill dev server
  if (appState.serverProcess) {
    results.serverStopped = stopServer(appState.serverProcess, appState.serverPid)
  }

  // Reset state
  resetState()

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
  if (appState.browserPageId === null) {
    return {
      ok: false,
      action: 'app_screenshot',
      error: 'No browser page open. Call app_start first.'
    }
  }

  const result = await browserTakeScreenshot(mcp, options)

  if (result.error) {
    return {
      ok: false,
      action: 'app_screenshot',
      error: result.error
    }
  }

  return {
    ok: true,
    action: 'app_screenshot',
    imageBase64: result.imageBase64,
    path: result.path,
    fullPage: options.fullPage ?? true
  }
}

/**
 * Get accessibility tree snapshot of current page
 * @param {object} mcp - MCP manager instance
 * @returns {Promise<object>} - Result with page snapshot
 */
export async function getPageSnapshot(mcp) {
  if (appState.browserPageId === null) {
    return {
      ok: false,
      action: 'app_snapshot',
      error: 'No browser page open. Call app_start first.'
    }
  }

  const result = await browserGetPageSnapshot(mcp)

  if (result.error) {
    return {
      ok: false,
      action: 'app_snapshot',
      error: result.error
    }
  }

  return {
    ok: true,
    action: 'app_snapshot',
    snapshot: result.snapshot
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
  if (appState.browserPageId === null) {
    return {
      ok: false,
      error: 'No browser page open. Call app_start first.'
    }
  }

  return browserExecutePassThrough(mcp, toolName, params)
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

// Re-export verifyWithVision from app-vision
export { verifyWithVision }
