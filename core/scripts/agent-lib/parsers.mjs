// agent-lib/parsers.mjs - Response parsing functions
import { log } from './utils.mjs'

export function stripToJsonObject(text) {
  // Remove common code fences and grab the first {...} block.
  const t = String(text || '').replace(/```[a-zA-Z]*\n?/g, '').replace(/```/g, '').trim()
  const start = t.indexOf('{')
  const end = t.lastIndexOf('}')
  if (start === -1 || end === -1 || end <= start) throw new Error('No JSON object found')
  return t.slice(start, end + 1)
}

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

export function parseJsonTextResponse(text) {
  const jsonStr = stripToJsonObject(text)
  return JSON.parse(jsonStr)
}
