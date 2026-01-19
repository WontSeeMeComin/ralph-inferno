// agent-lib/app-vision.mjs - Vision model verification
// Uses vision-capable LLMs to verify UI matches acceptance criteria

import { log } from './utils.mjs'
import { llmVision } from './llm.mjs'
import { takeScreenshot, getPageSnapshot } from './app-browser.mjs'

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
  if (screenshot.error) {
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

    log(`app-vision: Verification ${passed ? 'PASSED' : 'FAILED'}`)

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
    log(`app-vision: Vision failed (${e.message}), falling back to snapshot`)

    const snapshot = await getPageSnapshot(mcp)
    if (!snapshot.error) {
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
