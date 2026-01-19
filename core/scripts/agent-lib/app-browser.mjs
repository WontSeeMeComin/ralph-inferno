// agent-lib/app-browser.mjs - Browser operations via chrome-devtools MCP
// Handles browser page lifecycle and interactions

import { log } from './utils.mjs'

/**
 * Open a new browser page
 * @param {object} mcp - MCP manager instance
 * @param {string} url - URL to open
 * @returns {Promise<{pageId: number}|{error: string}>}
 */
export async function openBrowser(mcp, url) {
  if (!mcp?.clients?.chromeDevtools) {
    return { error: 'chromeDevtools MCP not connected' }
  }

  try {
    log(`app-browser: Opening browser at ${url}`)
    const result = await mcp.callServerTool('chromeDevtools', 'new_page', { url })
    const pageId = extractPageId(result)
    log(`app-browser: Browser opened, pageId=${pageId}`)
    return { pageId }
  } catch (e) {
    log(`app-browser: Failed to open browser: ${e.message}`)
    return { error: `Failed to open browser: ${e.message}` }
  }
}

/**
 * Close a browser page
 * @param {object} mcp - MCP manager instance
 * @param {number} pageId - Page ID to close
 * @returns {Promise<boolean>}
 */
export async function closeBrowser(mcp, pageId) {
  if (!mcp?.clients?.chromeDevtools || pageId === null) {
    return false
  }

  try {
    await mcp.callServerTool('chromeDevtools', 'close_page', { pageId })
    log(`app-browser: Browser page closed`)
    return true
  } catch (e) {
    log(`app-browser: Failed to close browser: ${e.message}`)
    return false
  }
}

/**
 * Take a screenshot of the current page
 * @param {object} mcp - MCP manager instance
 * @param {object} options - Screenshot options
 * @returns {Promise<{imageBase64: string}|{error: string}>}
 */
export async function takeScreenshot(mcp, options = {}) {
  if (!mcp?.clients?.chromeDevtools) {
    return { error: 'chromeDevtools MCP not connected' }
  }

  try {
    const result = await mcp.callServerTool('chromeDevtools', 'take_screenshot', {
      fullPage: options.fullPage ?? true,
      filePath: options.filePath
    })
    const imageBase64 = extractImageBase64(result)
    return { imageBase64, path: options.filePath || null }
  } catch (e) {
    return { error: `Screenshot failed: ${e.message}` }
  }
}

/**
 * Get accessibility tree snapshot of current page
 * @param {object} mcp - MCP manager instance
 * @returns {Promise<{snapshot: any}|{error: string}>}
 */
export async function getPageSnapshot(mcp) {
  if (!mcp?.clients?.chromeDevtools) {
    return { error: 'chromeDevtools MCP not connected' }
  }

  try {
    const result = await mcp.callServerTool('chromeDevtools', 'take_snapshot', {})
    return { snapshot: result.content || result }
  } catch (e) {
    return { error: `Snapshot failed: ${e.message}` }
  }
}

/**
 * Execute a pass-through chrome-devtools tool
 * @param {object} mcp - MCP manager instance
 * @param {string} toolName - chrome-devtools tool name
 * @param {object} params - Tool parameters
 * @returns {Promise<object>} - Tool result
 */
export async function executePassThrough(mcp, toolName, params) {
  if (!mcp?.clients?.chromeDevtools) {
    return { ok: false, error: 'chromeDevtools MCP not connected' }
  }

  try {
    const result = await mcp.callServerTool('chromeDevtools', toolName, params)
    return { ok: true, ...result }
  } catch (e) {
    return { ok: false, error: `${toolName} failed: ${e.message}` }
  }
}

// ============================================================================
// Helper functions - Extract data from MCP responses
// ============================================================================

/**
 * Extract pageId from MCP new_page result
 */
export function extractPageId(result) {
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
export function extractImageBase64(result) {
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
      return result.content
    }
  }
  return null
}
