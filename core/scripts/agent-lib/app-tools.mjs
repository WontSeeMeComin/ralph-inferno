// agent-lib/app-tools.mjs - Curated app_* tools for browser verification
// These tools are the ONLY interface agents see for browser interaction.
// No direct chrome-devtools exposure - everything goes through app-control.mjs

/**
 * App tool definitions
 *
 * Tool types:
 * - managed: Handled by app-control.mjs with state management (start, stop, verify)
 * - passThrough: Delegated to chrome-devtools MCP (click, fill, navigate, etc.)
 */
export const APP_TOOLS = [
  // ============================================
  // MANAGED TOOLS - Handled by app-control.mjs
  // ============================================
  {
    name: 'app_start',
    type: 'managed',
    description: 'Start dev server and open browser at localhost. MUST call this first.',
    when_to_use: [
      'Your spec has UI verification criteria in "Done when"',
      'You need to visually verify your changes rendered correctly',
      'Build passes but you need to confirm the app actually works'
    ],
    parameters: {
      port: { type: 'number', description: 'Port (default: 5173)', required: false },
      command: { type: 'string', description: 'Start command (default: "npm run dev")', required: false }
    },
    example: { port: 5173 }
  },
  {
    name: 'app_stop',
    type: 'managed',
    description: 'Stop dev server and close browser. Call when done with verification.',
    when_to_use: [
      'You finished verifying the UI',
      'You need to stop the server before making more code changes',
      'Verification passed and you\'re ready to call done'
    ],
    parameters: {},
    example: {}
  },
  {
    name: 'app_verify_ui',
    type: 'managed',
    description: 'Screenshot + vision model analysis. Returns PASS/FAIL with details.',
    when_to_use: [
      'You need to verify visual appearance matches spec criteria',
      'You want to confirm text, buttons, or layout is correct',
      'You need to check if the page rendered without errors'
    ],
    parameters: {
      criteria: { type: 'string', description: 'What to verify (from spec "Done when")', required: true }
    },
    example: { criteria: 'Navigation shows 6 links, welcome message displays correctly' }
  },

  // ============================================
  // PASS-THROUGH TOOLS - Delegate to chrome-devtools MCP
  // ============================================
  {
    name: 'app_screenshot',
    type: 'passThrough',
    mcpTool: 'take_screenshot',
    description: 'Take screenshot (for debugging or manual review)',
    when_to_use: [
      'You want to see what the page looks like without vision analysis',
      'You need to save a screenshot to a file',
      'Vision model failed and you need to debug'
    ],
    parameters: {
      fullPage: { type: 'boolean', description: 'Capture full page (default: true)', required: false },
      filePath: { type: 'string', description: 'Save path (optional)', required: false }
    },
    example: { fullPage: true }
  },
  {
    name: 'app_snapshot',
    type: 'passThrough',
    mcpTool: 'take_snapshot',
    description: 'Get accessibility tree snapshot with element UIDs for interaction',
    when_to_use: [
      'You need to find element UIDs for clicking or filling',
      'You want to inspect the page structure programmatically',
      'You need to verify specific elements exist'
    ],
    parameters: {},
    example: {}
  },
  {
    name: 'app_navigate',
    type: 'passThrough',
    mcpTool: 'navigate_page',
    description: 'Navigate to a URL or back/forward/reload',
    when_to_use: [
      'You need to go to a different page/route',
      'You need to reload after code changes',
      'You need to test browser history navigation'
    ],
    parameters: {
      url: { type: 'string', description: 'URL to navigate to', required: false },
      type: { type: 'string', description: 'url|back|forward|reload (default: url)', required: false }
    },
    example: { url: 'http://localhost:5173/about' }
  },
  {
    name: 'app_click',
    type: 'passThrough',
    mcpTool: 'click',
    description: 'Click an element by UID (get UIDs from app_snapshot)',
    when_to_use: [
      'You need to click a button or link',
      'You need to interact with the UI to test functionality',
      'You need to trigger an action'
    ],
    parameters: {
      uid: { type: 'string', description: 'Element UID from app_snapshot', required: true },
      dblClick: { type: 'boolean', description: 'Double-click (default: false)', required: false }
    },
    example: { uid: 'submit-button' }
  },
  {
    name: 'app_fill',
    type: 'passThrough',
    mcpTool: 'fill',
    description: 'Type text into an input field or select option',
    when_to_use: [
      'You need to fill in a form field',
      'You need to search or filter by typing',
      'You need to select a dropdown option'
    ],
    parameters: {
      uid: { type: 'string', description: 'Input element UID', required: true },
      value: { type: 'string', description: 'Text to enter', required: true }
    },
    example: { uid: 'email-input', value: 'test@example.com' }
  },
  {
    name: 'app_hover',
    type: 'passThrough',
    mcpTool: 'hover',
    description: 'Hover over an element (for dropdowns, tooltips)',
    when_to_use: [
      'You need to reveal a dropdown menu',
      'You need to trigger a tooltip',
      'You need to test hover states'
    ],
    parameters: {
      uid: { type: 'string', description: 'Element UID', required: true }
    },
    example: { uid: 'menu-button' }
  },
  {
    name: 'app_press_key',
    type: 'passThrough',
    mcpTool: 'press_key',
    description: 'Press keyboard key or combo (Enter, Tab, Ctrl+A)',
    when_to_use: [
      'You need to submit a form with Enter',
      'You need to navigate with Tab',
      'You need to trigger keyboard shortcuts'
    ],
    parameters: {
      key: { type: 'string', description: 'Key or combo (e.g., "Enter", "Control+A")', required: true }
    },
    example: { key: 'Enter' }
  },
  {
    name: 'app_wait_for',
    type: 'passThrough',
    mcpTool: 'wait_for',
    description: 'Wait for text to appear on page',
    when_to_use: [
      'You need to wait for async content to load',
      'You need to wait for a state change after an action',
      'Page content loads dynamically'
    ],
    parameters: {
      text: { type: 'string', description: 'Text to wait for', required: true },
      timeout: { type: 'number', description: 'Timeout in ms (default: 5000)', required: false }
    },
    example: { text: 'Welcome to the app', timeout: 10000 }
  }
]

/**
 * Check if a tool name is an app_* tool
 */
export function isAppTool(name) {
  return name.startsWith('app_') && APP_TOOLS.some(t => t.name === name)
}

/**
 * Get tool definition by name
 */
export function getAppTool(name) {
  return APP_TOOLS.find(t => t.name === name) || null
}

/**
 * Get all app tool names
 */
export function getAppToolNames() {
  return APP_TOOLS.map(t => t.name)
}

/**
 * Generate block-text documentation for app tools
 * Injected into system prompt when browser verification is enabled
 */
export function buildAppToolDocs() {
  let docs = '\n## APP VERIFICATION TOOLS\n\n'
  docs += 'When your spec has UI verification criteria in "Done when", use these tools:\n\n'

  docs += '### Lifecycle\n'
  for (const tool of APP_TOOLS.filter(t => t.type === 'managed')) {
    docs += `- **${tool.name}** - ${tool.description}\n`
  }

  docs += '\n### Interaction (if needed)\n'
  for (const tool of APP_TOOLS.filter(t => t.type === 'passThrough')) {
    docs += `- **${tool.name}** - ${tool.description}\n`
  }

  docs += `
### Workflow

1. Build passes → \`app_start\`
2. Verify: \`app_verify_ui criteria="<Done when criteria>"\`
3. If PASS → \`app_stop\` → \`done\`
4. If FAIL → \`app_stop\` → fix code → rebuild → retry

### Example

\`\`\`
[app_start]
port: 5173
[/app_start]

[app_verify_ui]
criteria: Navigation shows 6 links, Home page displays welcome message
[/app_verify_ui]
// Response: PASS - Navigation has 6 links visible, welcome message shows "Welcome to Aussie Site"

[app_stop]
[/app_stop]

[done]
summary: Implemented navigation with 6 links and welcome message, verified with browser
[/done]
\`\`\`
`

  return docs
}

/**
 * Convert app tools to OpenAI native function format
 * Used when model supports native tool calling
 */
export function buildAppToolsNative() {
  return APP_TOOLS.map(tool => ({
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
