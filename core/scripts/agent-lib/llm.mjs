// agent-lib/llm.mjs - LLM client implementation
import { log, envOr } from './utils.mjs'
import { modelFor, normalizeOpenAIBaseUrl } from './config.mjs'

export async function llmChat({ provider, config, messages, timeoutSeconds, useCase, toolFormat, tools }) {
  const model = modelFor({ provider, config, useCase })
  log(`llm: provider=${provider} model=${model} format=${toolFormat} msgs=${messages.length}`)
  const startTime = Date.now()

  try {
    const result = await _llmChatImpl({ provider, config, messages, timeoutSeconds, useCase, toolFormat, tools })
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1)
    const resultType = result.toolCall ? 'tool_call' : 'text'
    log(`llm: response in ${elapsed}s (${resultType})`)
    return result
  } catch (e) {
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1)
    log(`llm: FAILED after ${elapsed}s - ${e.message}`)
    throw e
  }
}

async function _llmChatImpl({ provider, config, messages, timeoutSeconds, useCase, toolFormat, tools }) {
  if (provider === 'ollama') {
    // Ollama doesn't support native tool calling well, always use block_text format
    const host = envOr(config, 'RALPH_OLLAMA_HOST', (c) => c.llm?.ollama?.host, 'http://localhost:11434')
    const model = modelFor({ provider, config, useCase })
    const resp = await fetch(`${host.replace(/\/$/, '')}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, stream: false, messages }),
      signal: AbortSignal.timeout(timeoutSeconds * 1000),
    })
    const text = await resp.text()
    if (!resp.ok) throw new Error(`Ollama error ${resp.status}: ${text.slice(0, 500)}`)
    const json = JSON.parse(text)
    return { content: json?.message?.content ?? '', toolCall: null }
  }

  if (provider === 'lmstudio' || provider === 'openrouter') {
    const base = provider === 'lmstudio'
      ? envOr(config, 'RALPH_LMSTUDIO_BASE_URL', (c) => c.llm?.lmstudio?.base_url, 'http://localhost:1234')
      : envOr(config, 'RALPH_OPENROUTER_BASE_URL', (c) => c.llm?.openrouter?.base_url, 'https://openrouter.ai/api/v1')

    const model = modelFor({ provider, config, useCase })
    const url = `${normalizeOpenAIBaseUrl(base)}/chat/completions`

    const headers = { 'Content-Type': 'application/json' }
    if (provider === 'openrouter') {
      const key = process.env.RALPH_OPENROUTER_API_KEY || process.env.OPENROUTER_API_KEY || config.llm?.openrouter?.api_key
      if (!key) throw new Error('OpenRouter requires OPENROUTER_API_KEY (or RALPH_OPENROUTER_API_KEY)')
      headers.Authorization = `Bearer ${key}`
      if (process.env.OPENROUTER_HTTP_REFERER) headers['HTTP-Referer'] = process.env.OPENROUTER_HTTP_REFERER
      if (process.env.OPENROUTER_X_TITLE) headers['X-Title'] = process.env.OPENROUTER_X_TITLE
    }

    // Build request body - include tools for native format
    const body = { model, messages, temperature: 0.2 }
    if (toolFormat === 'native' && tools && tools.length > 0) {
      body.tools = tools
      body.tool_choice = 'auto'
    }

    const resp = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutSeconds * 1000),
    })
    const text = await resp.text()
    if (!resp.ok) throw new Error(`OpenAI-compatible error ${resp.status}: ${text.slice(0, 500)}`)
    const json = JSON.parse(text)

    const choice = json?.choices?.[0]?.message
    if (!choice) {
      return { content: '', toolCall: null }
    }

    // Check for native tool calls
    if (choice.tool_calls && choice.tool_calls.length > 0) {
      const tc = choice.tool_calls[0]
      return {
        content: choice.content || '',
        toolCall: {
          id: tc.id,
          name: tc.function?.name,
          arguments: tc.function?.arguments || '{}'
        }
      }
    }

    return { content: choice.content ?? '', toolCall: null }
  }

  throw new Error(`Unsupported provider: ${provider}`)
}

/**
 * Send a vision request (image + prompt) to a vision-capable model
 * @param {object} config - Ralph config
 * @param {string} prompt - Text prompt for the vision model
 * @param {string} imageBase64 - Base64 encoded image data
 * @param {object} options - Optional settings (maxTokens, temperature)
 * @returns {Promise<string>} - Model's response text
 */
export async function llmVision(config, prompt, imageBase64, options = {}) {
  const provider = (
    process.env.RALPH_VISION_PROVIDER ||
    config.llm?.use_case_providers?.vision ||
    process.env.RALPH_LLM_PROVIDER ||
    config.llm?.provider ||
    'lmstudio'
  ).toLowerCase()

  // Get vision model for the provider
  const visionModel = (
    process.env.RALPH_VISION_MODEL ||
    config.llm?.[provider]?.vision_model ||
    config.llm?.[provider]?.model ||
    getDefaultVisionModel(provider)
  )

  if (!visionModel) {
    throw new Error(`No vision model configured for provider ${provider}. Set llm.${provider}.vision_model in config.`)
  }

  log(`llmVision: provider=${provider} model=${visionModel}`)

  // Build multimodal message (OpenAI-compatible format)
  const messages = [
    {
      role: 'user',
      content: [
        { type: 'text', text: prompt },
        {
          type: 'image_url',
          image_url: { url: `data:image/png;base64,${imageBase64}` }
        }
      ]
    }
  ]

  const maxTokens = options.maxTokens || 1024
  const temperature = options.temperature ?? 0.3

  if (provider === 'lmstudio') {
    const base = envOr(config, 'RALPH_LMSTUDIO_BASE_URL', (c) => c.llm?.lmstudio?.base_url, 'http://localhost:1234')
    const url = `${normalizeOpenAIBaseUrl(base)}/chat/completions`

    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: visionModel,
        messages,
        max_tokens: maxTokens,
        temperature
      }),
      signal: AbortSignal.timeout(60000)
    })

    const text = await resp.text()
    if (!resp.ok) throw new Error(`LM Studio vision error ${resp.status}: ${text.slice(0, 500)}`)

    const json = JSON.parse(text)
    return json?.choices?.[0]?.message?.content ?? ''
  }

  if (provider === 'openrouter') {
    const base = envOr(config, 'RALPH_OPENROUTER_BASE_URL', (c) => c.llm?.openrouter?.base_url, 'https://openrouter.ai/api/v1')
    const key = process.env.RALPH_OPENROUTER_API_KEY || process.env.OPENROUTER_API_KEY || config.llm?.openrouter?.api_key

    if (!key) throw new Error('OpenRouter requires OPENROUTER_API_KEY for vision')

    const url = `${normalizeOpenAIBaseUrl(base)}/chat/completions`
    const headers = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${key}`
    }

    const resp = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        model: visionModel,
        messages,
        max_tokens: maxTokens,
        temperature
      }),
      signal: AbortSignal.timeout(60000)
    })

    const text = await resp.text()
    if (!resp.ok) throw new Error(`OpenRouter vision error ${resp.status}: ${text.slice(0, 500)}`)

    const json = JSON.parse(text)
    return json?.choices?.[0]?.message?.content ?? ''
  }

  if (provider === 'ollama') {
    // Ollama uses a different format for vision
    const host = envOr(config, 'RALPH_OLLAMA_HOST', (c) => c.llm?.ollama?.host, 'http://localhost:11434')

    const resp = await fetch(`${host.replace(/\/$/, '')}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: visionModel,
        stream: false,
        messages: [
          {
            role: 'user',
            content: prompt,
            images: [imageBase64]
          }
        ]
      }),
      signal: AbortSignal.timeout(60000)
    })

    const text = await resp.text()
    if (!resp.ok) throw new Error(`Ollama vision error ${resp.status}: ${text.slice(0, 500)}`)

    const json = JSON.parse(text)
    return json?.message?.content ?? ''
  }

  throw new Error(`Vision not supported for provider: ${provider}`)
}

/**
 * Get default vision model for a provider
 */
function getDefaultVisionModel(provider) {
  const defaults = {
    lmstudio: 'llava-v1.6-mistral-7b',
    openrouter: 'openai/gpt-4o-mini',
    ollama: 'llava'
  }
  return defaults[provider] || null
}
