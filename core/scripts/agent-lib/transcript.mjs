// agent-lib/transcript.mjs - JSONL session transcript logging for debugging/replay
import fs from 'node:fs/promises'
import path from 'node:path'

// Check verbose mode - no truncation when set
const VERBOSE = !!process.env.RALPH_VERBOSE

/**
 * Create a transcript logger for a session.
 * Writes JSONL entries for tool calls, results, thoughts, and errors.
 *
 * @param {string} sessionId - Unique session identifier
 * @param {string} outputDir - Directory for transcript files (default: .ralph/transcripts)
 * @returns {Object} Transcript logger with log methods
 */
export function createTranscript(sessionId, outputDir = '.ralph/transcripts') {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-')
  const filename = path.join(outputDir, `${timestamp}-${sessionId.slice(0, 8)}.jsonl`)

  let initialized = false

  return {
    /**
     * Initialize transcript directory (called lazily on first log)
     */
    async init() {
      if (!initialized) {
        await fs.mkdir(outputDir, { recursive: true })
        initialized = true
      }
    },

    /**
     * Log a raw event entry
     * @param {Object} event - Event data to log
     */
    async log(event) {
      await this.init()
      const entry = {
        ts: new Date().toISOString(),
        sessionId,
        ...event
      }
      await fs.appendFile(filename, JSON.stringify(entry) + '\n')
    },

    /**
     * Log a tool call before execution
     * @param {number} step - Current step number
     * @param {string} action - Tool action name
     * @param {Object} input - Tool input parameters
     */
    async toolCall(step, action, input) {
      // Clone and sanitize input (remove internal fields, truncate large content)
      const sanitized = { ...input }
      delete sanitized._thought
      delete sanitized._thoughtFormat
      delete sanitized._toolCallId

      // Truncate large content fields for readability (skip if VERBOSE)
      if (!VERBOSE) {
        for (const key of ['content', 'patch', 'stdout', 'stderr']) {
          if (sanitized[key] && sanitized[key].length > 500) {
            sanitized[key] = sanitized[key].slice(0, 500) + `... (${sanitized[key].length} chars)`
          }
        }
      }

      await this.log({ type: 'tool_call', step, action, input: sanitized })
    },

    /**
     * Log a tool result after execution
     * @param {number} step - Current step number
     * @param {string} action - Tool action name
     * @param {Object} result - Tool execution result
     * @param {number} elapsedMs - Execution time in milliseconds
     */
    async toolResult(step, action, result, elapsedMs) {
      // Summarize result for logging
      const summary = {
        ok: result.ok,
        exitCode: result.exitCode
      }

      // Include error if present
      if (result.error) {
        const errStr = String(result.error)
        summary.error = VERBOSE ? errStr : errStr.slice(0, 200)
      }

      // Include stdout/stderr length for run commands
      if (result.stdout !== undefined) {
        summary.stdoutLen = result.stdout?.length || 0
      }
      if (result.stderr !== undefined) {
        summary.stderrLen = result.stderr?.length || 0
      }

      await this.log({ type: 'tool_result', step, action, result: summary, elapsedMs })
    },

    /**
     * Log a thought block from the model
     * @param {number} step - Current step number
     * @param {string} thought - Thought content
     * @param {string|null} format - Tag format used (e.g., "<think>" or "[THOUGHT]")
     */
    async thought(step, thought, format) {
      // Truncate very long thoughts (skip if VERBOSE)
      const truncated = (!VERBOSE && thought.length > 1000)
        ? thought.slice(0, 1000) + `... (${thought.length} chars)`
        : thought

      await this.log({ type: 'thought', step, thought: truncated, format })
    },

    /**
     * Log an error during execution
     * @param {number} step - Current step number
     * @param {string} action - Action that caused the error
     * @param {Error|string} error - Error object or message
     */
    async error(step, action, error) {
      await this.log({ type: 'error', step, action, error: String(error) })
    },

    /**
     * Log sandbox block event
     * @param {number} step - Current step number
     * @param {string} cmd - Blocked command
     * @param {string} reason - Reason for blocking
     */
    async blocked(step, cmd, reason) {
      await this.log({ type: 'blocked', step, cmd, reason })
    },

    /**
     * Log session start
     * @param {Object} meta - Session metadata (provider, model, spec, etc.)
     */
    async start(meta) {
      await this.log({ type: 'session_start', ...meta })
    },

    /**
     * Log session completion
     * @param {string} summary - Completion summary from done action
     */
    async complete(summary) {
      await this.log({ type: 'complete', summary })
    },

    /**
     * Get the path to this transcript file
     * @returns {string} Full path to the transcript file
     */
    getPath() {
      return filename
    }
  }
}
