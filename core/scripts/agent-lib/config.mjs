// agent-lib/config.mjs - Configuration loading and provider setup
import fs from 'node:fs/promises'
import path from 'node:path'
import { envOr, log } from './utils.mjs'

export async function readConfig() {
  const configPath = process.env.RALPH_CONFIG || path.join('.ralph', 'config.json')
  try {
    const raw = await fs.readFile(configPath, 'utf8')
    return { path: configPath, json: JSON.parse(raw) }
  } catch {
    return { path: configPath, json: {} }
  }
}

function normalizeOpenAIBaseUrl(base) {
  const b = String(base || '').replace(/\/$/, '')
  return b.endsWith('/v1') ? b : `${b}/v1`
}

function useCaseSuffix(useCase) {
  return String(useCase || '')
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '_')
}

function useCaseEnv(baseKey, useCase) {
  const s = useCaseSuffix(useCase)
  return s ? `${baseKey}_${s}` : baseKey
}

export function modelFor({ provider, config, useCase }) {
  if (provider === 'ollama') {
    return (
      process.env[useCaseEnv('RALPH_OLLAMA_MODEL', useCase)] ||
      config.llm?.ollama?.use_case_models?.[useCase] ||
      process.env.RALPH_OLLAMA_MODEL ||
      config.llm?.ollama?.model ||
      'qwen3'
    )
  }

  if (provider === 'lmstudio') {
    return (
      process.env[useCaseEnv('RALPH_LMSTUDIO_MODEL', useCase)] ||
      config.llm?.lmstudio?.use_case_models?.[useCase] ||
      process.env.RALPH_LMSTUDIO_MODEL ||
      config.llm?.lmstudio?.model ||
      'qwen/qwen3-next-80b'
    )
  }

  if (provider === 'openrouter') {
    return (
      process.env[useCaseEnv('RALPH_OPENROUTER_MODEL', useCase)] ||
      config.llm?.openrouter?.use_case_models?.[useCase] ||
      process.env.RALPH_OPENROUTER_MODEL ||
      config.llm?.openrouter?.model ||
      'openai/gpt-4o-mini'
    )
  }

  return null
}

export async function selectProvider(config) {
  const requested = (process.env.RALPH_LLM_PROVIDER || config.llm?.provider || 'claude').toLowerCase()

  async function healthOpenAI(base, headers = {}) {
    try {
      const url = `${normalizeOpenAIBaseUrl(base)}/models`
      const r = await fetch(url, { headers, signal: AbortSignal.timeout(3000) })
      return r.ok
    } catch {
      return false
    }
  }

  async function healthOllama(host) {
    try {
      const r = await fetch(`${host.replace(/\/$/, '')}/api/tags`, { signal: AbortSignal.timeout(3000) })
      return r.ok
    } catch {
      return false
    }
  }

  const auto = async () => {
    const lmBase = envOr(config, 'RALPH_LMSTUDIO_BASE_URL', (c) => c.llm?.lmstudio?.base_url, 'http://localhost:1234')
    if (await healthOpenAI(lmBase)) return 'lmstudio'

    const ollamaHost = envOr(config, 'RALPH_OLLAMA_HOST', (c) => c.llm?.ollama?.host, 'http://localhost:11434')
    if (await healthOllama(ollamaHost)) return 'ollama'

    const orBase = envOr(config, 'RALPH_OPENROUTER_BASE_URL', (c) => c.llm?.openrouter?.base_url, 'https://openrouter.ai/api/v1')
    const key = process.env.RALPH_OPENROUTER_API_KEY || process.env.OPENROUTER_API_KEY || config.llm?.openrouter?.api_key
    if (key) {
      if (await healthOpenAI(orBase, { Authorization: `Bearer ${key}` })) return 'openrouter'
    }

    return null
  }

  if (requested === 'auto') return (await auto())
  if (['lmstudio', 'ollama', 'openrouter'].includes(requested)) return requested
  return null
}

export { normalizeOpenAIBaseUrl }
