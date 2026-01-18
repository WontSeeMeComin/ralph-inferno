// agent-lib/mcp-tools.mjs - Curated MCP tool definitions with clear docs
// Designed for "dumbest LLM on earth" - crystal clear tool docs with examples.

/**
 * Curated MCP tools with explicit documentation for local LLMs.
 * Each tool has: name, description, when_to_use, parameters, example
 *
 * We expose a SUBSET of MCP tools with simplified names:
 * - mcp_docs -> Context7 query-docs
 * - mcp_resolve_library -> Context7 resolve-library-id
 * - mcp_search_web -> Perplexity perplexity_ask
 */
export const CURATED_MCP_TOOLS = [
  {
    name: 'mcp_resolve_library',
    mcpServer: 'context7',
    mcpTool: 'resolve-library-id',
    description: 'Find the correct library ID for mcp_docs. Use this FIRST if you don\'t know the exact library ID.',
    when_to_use: [
      'You need to look up docs but don\'t know the library ID format',
      'You want to search for a library by name'
    ],
    parameters: {
      libraryName: {
        type: 'string',
        description: 'Name of the library (e.g., "nextjs", "prisma", "tailwind")',
        required: true
      },
      query: {
        type: 'string',
        description: 'What you\'re trying to do with this library',
        required: true
      }
    },
    example: {
      libraryName: 'prisma',
      query: 'database ORM for Node.js'
    }
  },
  {
    name: 'mcp_docs',
    mcpServer: 'context7',
    mcpTool: 'query-docs',
    description: 'Look up documentation for a library or framework. Returns code examples and API reference.',
    when_to_use: [
      'You don\'t know how to use a library (e.g., React, Express, Prisma)',
      'You need the correct API syntax for a function',
      'You\'re getting errors and need to check proper usage'
    ],
    parameters: {
      libraryId: {
        type: 'string',
        description: 'Library ID in format "/org/project" (e.g., "/vercel/next.js", "/prisma/prisma"). Use mcp_resolve_library first if unknown.',
        required: true
      },
      query: {
        type: 'string',
        description: 'What you want to know (e.g., "how to create API routes", "useEffect cleanup")',
        required: true
      }
    },
    example: {
      libraryId: '/vercel/next.js',
      query: 'how to create API route handlers'
    }
  },
  {
    name: 'mcp_search_web',
    mcpServer: 'perplexity',
    mcpTool: 'perplexity_ask',
    description: 'Search the web for answers. Returns summarized information from multiple sources.',
    when_to_use: [
      'mcp_docs didn\'t have the answer',
      'You need current/recent information (news, updates)',
      'You need to research a general programming concept',
      'You\'re stuck and need a different perspective'
    ],
    parameters: {
      messages: {
        type: 'array',
        description: 'Array with single message: [{"role": "user", "content": "your question"}]',
        required: true
      }
    },
    example: {
      messages: [{ role: 'user', content: 'How to fix "Cannot find module" error in Node.js ES modules?' }]
    }
  }
]

/**
 * Generate block-text documentation for MCP tools
 * Injected into system prompt for block_text format models
 */
export function buildMcpToolDocs() {
  let docs = '\n## EXTERNAL TOOLS (MCP)\n\n'
  docs += 'These tools connect to external services. Use them when built-in tools aren\'t enough.\n\n'

  for (const tool of CURATED_MCP_TOOLS) {
    docs += `### ${tool.name}\n`
    docs += `${tool.description}\n\n`
    docs += `**When to use:**\n`
    for (const hint of tool.when_to_use) {
      docs += `- ${hint}\n`
    }
    docs += `\n**Parameters:**\n`
    for (const [name, info] of Object.entries(tool.parameters)) {
      docs += `- ${name} (${info.type}${info.required ? ', required' : ''}): ${info.description}\n`
    }
    docs += `\n**Example:**\n\`\`\`\n[${tool.name}]\n`
    for (const [k, v] of Object.entries(tool.example)) {
      if (typeof v === 'object') {
        docs += `${k}: ${JSON.stringify(v)}\n`
      } else {
        docs += `${k}: ${v}\n`
      }
    }
    docs += `[/${tool.name}]\n\`\`\`\n\n`
  }

  return docs
}

/**
 * Convert curated tools to OpenAI native function format
 * Used when model supports native tool calling
 */
export function buildMcpToolsNative() {
  return CURATED_MCP_TOOLS.map(tool => ({
    type: 'function',
    function: {
      name: tool.name,
      description: `${tool.description}\n\nWhen to use:\n${tool.when_to_use.map(h => '- ' + h).join('\n')}`,
      parameters: {
        type: 'object',
        properties: Object.fromEntries(
          Object.entries(tool.parameters).map(([name, info]) => [
            name,
            { type: info.type, description: info.description }
          ])
        ),
        required: Object.entries(tool.parameters)
          .filter(([_, info]) => info.required)
          .map(([name]) => name)
      }
    }
  }))
}

/**
 * Get the tool definition for a curated MCP tool
 * @param {string} name - Curated tool name (e.g., 'mcp_docs')
 * @returns {object|null} - Tool definition or null
 */
export function getCuratedTool(name) {
  return CURATED_MCP_TOOLS.find(t => t.name === name) || null
}

/**
 * Check if a tool name is a curated MCP tool
 */
export function isCuratedMcpTool(name) {
  return name.startsWith('mcp_') && CURATED_MCP_TOOLS.some(t => t.name === name)
}

/**
 * Map curated tool parameters to actual MCP tool parameters
 * Most tools pass through directly, but some need transformation
 */
export function mapToolParams(curatedTool, params) {
  // For now, all tools pass through directly
  // Add transformations here if needed for specific tools
  return params
}
