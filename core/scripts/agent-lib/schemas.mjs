// agent-lib/schemas.mjs - Tool schema and model capabilities loading
import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { log } from './utils.mjs'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const SCHEMAS_DIR = path.join(__dirname, '..', 'tool-schemas')

export async function loadToolSchema(format) {
  let filename
  if (format === 'native') {
    filename = 'openai-native.json'
  } else if (format === 'block_text') {
    filename = 'block-text-schema.json'
  } else {
    // Legacy json_text fallback
    filename = 'json-text-schema.json'
  }

  const schemaPath = path.join(SCHEMAS_DIR, filename)
  try {
    const raw = await fs.readFile(schemaPath, 'utf8')
    return JSON.parse(raw)
  } catch (e) {
    log(`Warning: Could not load tool schema ${filename}: ${e.message}`)
    return null
  }
}

export async function loadModelCapabilities() {
  const capPath = path.join(SCHEMAS_DIR, 'model-capabilities.json')
  try {
    const raw = await fs.readFile(capPath, 'utf8')
    return JSON.parse(raw)
  } catch (e) {
    log(`Warning: Could not load model-capabilities.json: ${e.message}`)
    return { models: {}, default: { toolFormat: 'block_text', thinkingTags: ['[THOUGHT]', '[/THOUGHT]'] } }
  }
}

export function getModelCapabilities(model, config, provider, capabilities) {
  // Check config override first
  const override = config.llm?.[provider]?.tool_format
  if (override) {
    return { toolFormat: override, thinkingTags: null }
  }

  // Auto-detect from model name
  const modelLower = (model || '').toLowerCase()
  for (const [key, caps] of Object.entries(capabilities.models || {})) {
    if (modelLower.includes(key)) {
      return { toolFormat: caps.toolFormat, thinkingTags: caps.thinkingTags }
    }
  }
  return capabilities.default || { toolFormat: 'block_text', thinkingTags: ['[THOUGHT]', '[/THOUGHT]'] }
}
