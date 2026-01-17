// agent-lib/utils.mjs - Shared utility functions
import { spawnSync } from 'node:child_process'

export const COMPLETION_MARKER = '<promise>DONE</promise>'

export function log(msg) {
  const ts = new Date().toISOString().slice(11, 19)
  console.log(`[${ts}] ${msg}`)
}

export function die(msg, code = 1) {
  const ts = new Date().toISOString().slice(11, 19)
  console.error(`[${ts}] ERROR: ${msg}`)
  process.exit(code)
}

export function run(cmd, { cwd = process.cwd(), timeoutMs = 0 } = {}) {
  const res = spawnSync('bash', ['-lc', cmd], {
    cwd,
    encoding: 'utf8',
    maxBuffer: 50 * 1024 * 1024,
    timeout: timeoutMs > 0 ? timeoutMs : undefined,
  })
  return {
    exitCode: res.status ?? 0,
    stdout: res.stdout ?? '',
    stderr: res.stderr ?? '',
    signal: res.signal ?? null,
  }
}

export function envOr(obj, envName, getter, fallback) {
  const v = process.env[envName]
  if (v !== undefined && v !== '') return v
  const jv = getter(obj)
  if (jv !== undefined && jv !== null && String(jv) !== '') return String(jv)
  return fallback
}
