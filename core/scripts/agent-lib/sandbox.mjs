// agent-lib/sandbox.mjs - Command gating and path restrictions for local testing
import path from 'node:path'

/**
 * Command safety policies for different sandbox modes
 */
const POLICIES = {
  /**
   * Strict mode: Only explicitly allowed commands pass
   */
  strict: {
    allowlist: [
      'npm run', 'npm test', 'npm install', 'npm ci', 'npm exec', 'npm pkg',
      'node ', 'npx ', 'tsx ',
      'git status', 'git diff', 'git add', 'git log', 'git show', 'git branch',
      'ls', 'cat', 'head', 'tail', 'grep', 'find', 'wc',
      'mkdir', 'touch', 'cp', 'mv',
      'pwd', 'echo', 'which', 'env'
    ],
    blocklist: [
      'rm -rf', 'rm -r /', 'rm -rf /',
      'sudo', 'su ',
      'curl', 'wget', 'nc ', 'netcat',
      '> /dev', 'dd ', 'mkfs',
      'chmod 777', 'chmod -R 777',
      'eval ', '$(', '`'
    ]
  },

  /**
   * Permissive mode: Allow most commands, only block critical destructive operations
   */
  permissive: {
    allowlist: null, // Allow all
    blocklist: [
      'rm -rf /',
      'sudo rm -rf',
      'mkfs',
      'dd if=/dev/zero',
      '> /dev/sda',
      ':(){:|:&};:'  // Fork bomb
    ]
  },

  /**
   * Monitor mode: Log all commands, minimal blocking (for debugging)
   */
  monitor: {
    allowlist: null,
    blocklist: [
      'rm -rf /',
      'sudo rm -rf /',
      'mkfs',
      ':(){:|:&};:'
    ],
    logAll: true
  }
}

/**
 * Create a sandbox instance for command and path gating
 *
 * @param {Object} config - Sandbox configuration
 * @param {string} config.mode - Sandbox mode: 'strict', 'permissive', or 'monitor'
 * @param {string} config.projectRoot - Root directory for path restrictions
 * @returns {Object} Sandbox instance with validation methods
 */
export function createSandbox(config = {}) {
  const mode = config.mode || 'permissive'
  const policy = POLICIES[mode] || POLICIES.permissive
  const projectRoot = path.resolve(config.projectRoot || process.cwd())

  return {
    mode,
    projectRoot,

    /**
     * Check if a command is allowed under current policy
     * @param {string} cmd - Command to check
     * @returns {{ allowed: boolean, reason?: string, shouldLog?: boolean }}
     */
    isCommandAllowed(cmd) {
      const trimmedCmd = cmd.trim()

      // Check blocklist first (always applies)
      if (policy.blocklist) {
        for (const blocked of policy.blocklist) {
          if (trimmedCmd.includes(blocked)) {
            return {
              allowed: false,
              reason: `Blocked pattern: "${blocked}"`,
              shouldLog: true
            }
          }
        }
      }

      // Check allowlist (strict mode only)
      if (policy.allowlist) {
        const isAllowed = policy.allowlist.some(prefix => {
          // Check if command starts with allowed prefix
          if (trimmedCmd.startsWith(prefix)) return true
          // Also check after common shell prefixes like "cd dir && "
          const pipeIdx = trimmedCmd.lastIndexOf('&& ')
          if (pipeIdx > 0) {
            const afterPipe = trimmedCmd.slice(pipeIdx + 3).trim()
            if (afterPipe.startsWith(prefix)) return true
          }
          return false
        })

        if (!isAllowed) {
          return {
            allowed: false,
            reason: `Not in allowlist (mode: ${mode})`,
            shouldLog: true
          }
        }
      }

      return {
        allowed: true,
        shouldLog: policy.logAll || false
      }
    },

    /**
     * Check if a file path is within the project root
     * @param {string} filePath - Path to check
     * @returns {{ allowed: boolean, resolved: string, reason?: string }}
     */
    isPathAllowed(filePath) {
      const resolved = path.resolve(projectRoot, filePath)

      // Must be within project root
      if (!resolved.startsWith(projectRoot + path.sep) && resolved !== projectRoot) {
        return {
          allowed: false,
          resolved,
          reason: `Path escapes project root: ${resolved}`
        }
      }

      // Block sensitive paths
      const relativePath = path.relative(projectRoot, resolved)
      const sensitivePatterns = [
        /^\.git\//,
        /^\.env/,
        /^node_modules\/.bin\//,
        /credentials/i,
        /secrets?/i
      ]

      for (const pattern of sensitivePatterns) {
        if (pattern.test(relativePath)) {
          return {
            allowed: false,
            resolved,
            reason: `Sensitive path pattern: ${relativePath}`
          }
        }
      }

      return { allowed: true, resolved }
    },

    /**
     * Wrap command for sandbox execution (placeholder for future enhancements)
     * Could add: timeout wrappers, resource limits, chroot, etc.
     * @param {string} cmd - Command to wrap
     * @returns {string} Wrapped command
     */
    wrapCommand(cmd) {
      // Future: could add timeout, nice, ulimit, etc.
      return cmd
    },

    /**
     * Get a summary of the sandbox configuration
     * @returns {Object} Configuration summary
     */
    getSummary() {
      return {
        mode,
        projectRoot,
        hasAllowlist: !!policy.allowlist,
        blocklistSize: policy.blocklist?.length || 0,
        logsAll: policy.logAll || false
      }
    }
  }
}

/**
 * Available sandbox modes for documentation/CLI help
 */
export const SANDBOX_MODES = ['strict', 'permissive', 'monitor']
