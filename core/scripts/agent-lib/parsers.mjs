// agent-lib/parsers.mjs - Response parsing functions
import { log } from './utils.mjs'

/**
 * Extract thought block from response text using configurable tag formats.
 * Tries each [openTag, closeTag] pair in order, returning the first match.
 *
 * @param {string} text - The response text to parse
 * @param {Array<[string, string]>|null} thinkingTags - Array of [open, close] tag pairs, or null for default
 * @returns {{ thought: string|null, remainder: string, format: string|null }}
 */
export function extractThoughtBlock(text, thinkingTags = null) {
  // Default fallback tags
  const tagPairs = thinkingTags || [['[THOUGHT]', '[/THOUGHT]']]

  for (const [openTag, closeTag] of tagPairs) {
    // Escape special regex characters in tags
    const escaped = [openTag, closeTag].map(t =>
      t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    )
    const regex = new RegExp(`${escaped[0]}([\\s\\S]*?)${escaped[1]}`, 'i')
    const match = text.match(regex)
    if (match) {
      return {
        thought: match[1].trim(),
        remainder: text.replace(match[0], '').trim(),
        format: openTag  // Track which format was used
      }
    }
  }
  return { thought: null, remainder: text, format: null }
}

/**
 * Parse block-text format response: [TOOL_NAME]...[/TOOL_NAME]
 * This format avoids JSON escaping issues with code content.
 *
 * @param {string} text - The response text to parse
 * @param {Array<[string, string]>|null} thinkingTags - Optional thinking tag pairs
 */
export function parseBlockTextResponse(text, thinkingTags = null) {
  // Extract thought first
  const { thought, remainder, format: thoughtFormat } = extractThoughtBlock(text, thinkingTags)

  // Strip <tool_code> wrapper if present
  let cleanText = remainder
  const toolCodeMatch = remainder.match(/<tool_code>([\s\S]*?)<\/tool_code>/i)
  if (toolCodeMatch) {
    cleanText = toolCodeMatch[1].trim()
  }

  // Find tool block: [TOOL_NAME]...[/TOOL_NAME]
  const toolMatch = cleanText.match(/\[(\w+)\]([\s\S]*?)\[\/\1\]/i)
  if (!toolMatch) {
    throw new Error('No valid tool block found. Expected format: [tool_name]...[/tool_name]')
  }

  const action = toolMatch[1].toLowerCase()
  const body = toolMatch[2].trim()

  // Parse key: value pairs from body
  const result = { action, _thought: thought, _thoughtFormat: thoughtFormat }
  const lines = body.split('\n')
  let currentKey = null
  let contentLines = []
  let inMultilineContent = false

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]

    if (inMultilineContent) {
      // Accumulate all remaining lines as content
      contentLines.push(line)
    } else if (line.match(/^(\w+):\s*$/)) {
      // Key with content on following lines (e.g., "content:" or "patch:")
      // This indicates multiline content starts on next line
      currentKey = line.match(/^(\w+):/)[1]
      inMultilineContent = true
    } else if (line.match(/^(\w+):\s*(.+)$/)) {
      // Key: value on same line
      const keyMatch = line.match(/^(\w+):\s*(.+)$/)
      result[keyMatch[1]] = keyMatch[2]
    }
  }

  // Store accumulated multiline content
  if (currentKey && contentLines.length > 0) {
    result[currentKey] = contentLines.join('\n')
  }

  return result
}

/**
 * Strip markdown fences and extract JSON object from text.
 */
export function stripToJsonObject(text) {
  // Remove common code fences and grab the first {...} block.
  const t = String(text || '').replace(/```[a-zA-Z]*\n?/g, '').replace(/```/g, '').trim()
  const start = t.indexOf('{')
  const end = t.lastIndexOf('}')
  if (start === -1 || end === -1 || end <= start) throw new Error('No JSON object found')
  return t.slice(start, end + 1)
}

/**
 * Parse native OpenAI-style tool call from API response.
 */
export function parseNativeToolCall(toolCall) {
  if (!toolCall) return null
  try {
    const args = JSON.parse(toolCall.arguments || '{}')
    return {
      action: toolCall.name,
      ...args,
      _toolCallId: toolCall.id
    }
  } catch (e) {
    log(`Failed to parse tool call arguments: ${e.message}`)
    return null
  }
}

/**
 * Parse JSON-in-text response (legacy format, kept as fallback).
 * Also extracts thought block if present.
 *
 * @param {string} text - The response text to parse
 * @param {Array<[string, string]>|null} thinkingTags - Optional thinking tag pairs
 */
export function parseJsonTextResponse(text, thinkingTags = null) {
  // Extract thought first
  const { thought, remainder, format: thoughtFormat } = extractThoughtBlock(text, thinkingTags)

  const jsonStr = stripToJsonObject(remainder)
  const result = JSON.parse(jsonStr)

  // Attach thought if found
  if (thought) {
    result._thought = thought
    result._thoughtFormat = thoughtFormat
  }

  return result
}

/**
 * Unified parser that tries block_text first, falls back to JSON.
 * This enables smooth migration from json_text to block_text.
 *
 * @param {string} text - The response text to parse
 * @param {boolean} preferBlockText - Whether to try block_text format first
 * @param {Array<[string, string]>|null} thinkingTags - Optional thinking tag pairs
 */
export function parseTextResponse(text, preferBlockText = true, thinkingTags = null) {
  if (preferBlockText) {
    // Try block_text format first
    try {
      return parseBlockTextResponse(text, thinkingTags)
    } catch (blockErr) {
      // Fall back to JSON format
      try {
        const result = parseJsonTextResponse(text, thinkingTags)
        log(`Parsed as JSON (block_text fallback): ${result.action}`)
        return result
      } catch (jsonErr) {
        // Neither worked, throw the block_text error as it's the preferred format
        throw blockErr
      }
    }
  } else {
    // Try JSON format first (for backwards compatibility)
    try {
      return parseJsonTextResponse(text, thinkingTags)
    } catch (jsonErr) {
      // Fall back to block_text
      try {
        return parseBlockTextResponse(text, thinkingTags)
      } catch (blockErr) {
        throw jsonErr
      }
    }
  }
}
