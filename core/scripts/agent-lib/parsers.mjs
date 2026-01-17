// agent-lib/parsers.mjs - Response parsing functions
import { log } from './utils.mjs'

/**
 * Extract [THOUGHT]...[/THOUGHT] block from response text.
 * Returns the thought content and the remainder of the text.
 */
export function extractThoughtBlock(text) {
  const match = text.match(/\[THOUGHT\]([\s\S]*?)\[\/THOUGHT\]/i)
  if (match) {
    const thought = match[1].trim()
    const remainder = text.replace(match[0], '').trim()
    return { thought, remainder }
  }
  return { thought: null, remainder: text }
}

/**
 * Parse block-text format response: [TOOL_NAME]...[/TOOL_NAME]
 * This format avoids JSON escaping issues with code content.
 */
export function parseBlockTextResponse(text) {
  // Extract thought first
  const { thought, remainder } = extractThoughtBlock(text)

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
  const result = { action, _thought: thought }
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
 */
export function parseJsonTextResponse(text) {
  // Extract thought first
  const { thought, remainder } = extractThoughtBlock(text)

  const jsonStr = stripToJsonObject(remainder)
  const result = JSON.parse(jsonStr)

  // Attach thought if found
  if (thought) {
    result._thought = thought
  }

  return result
}

/**
 * Unified parser that tries block_text first, falls back to JSON.
 * This enables smooth migration from json_text to block_text.
 */
export function parseTextResponse(text, preferBlockText = true) {
  const { thought, remainder } = extractThoughtBlock(text)

  if (preferBlockText) {
    // Try block_text format first
    try {
      return parseBlockTextResponse(text)
    } catch (blockErr) {
      // Fall back to JSON format
      try {
        const result = parseJsonTextResponse(text)
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
      return parseJsonTextResponse(text)
    } catch (jsonErr) {
      // Fall back to block_text
      try {
        return parseBlockTextResponse(text)
      } catch (blockErr) {
        throw jsonErr
      }
    }
  }
}
