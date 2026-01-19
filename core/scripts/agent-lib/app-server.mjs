// agent-lib/app-server.mjs - Dev server lifecycle management
// Handles starting/stopping the development server process

import { spawn } from 'node:child_process'
import net from 'node:net'
import { log } from './utils.mjs'

/**
 * Wait for a port to become available
 * @param {number} port - Port to check
 * @param {number} timeoutMs - Timeout in milliseconds
 * @returns {Promise<boolean>} - True if port becomes available
 */
export async function waitForPort(port, timeoutMs = 10000) {
  const start = Date.now()
  const checkInterval = 250

  while (Date.now() - start < timeoutMs) {
    try {
      await new Promise((resolve, reject) => {
        const socket = new net.Socket()
        socket.setTimeout(1000)
        socket.once('connect', () => {
          socket.destroy()
          resolve(true)
        })
        socket.once('timeout', () => {
          socket.destroy()
          reject(new Error('timeout'))
        })
        socket.once('error', reject)
        socket.connect(port, 'localhost')
      })
      return true
    } catch {
      await new Promise(r => setTimeout(r, checkInterval))
    }
  }
  return false
}

/**
 * Check if a port is in use
 * @param {number} port - Port to check
 * @returns {Promise<boolean>} - True if port is in use
 */
export async function isPortInUse(port) {
  return new Promise((resolve) => {
    const socket = new net.Socket()
    socket.setTimeout(1000)
    socket.once('connect', () => {
      socket.destroy()
      resolve(true)
    })
    socket.once('timeout', () => {
      socket.destroy()
      resolve(false)
    })
    socket.once('error', () => {
      socket.destroy()
      resolve(false)
    })
    socket.connect(port, 'localhost')
  })
}

/**
 * Start a dev server process
 * @param {string} command - Command to run (e.g., 'npm run dev')
 * @param {number} port - Port number
 * @param {function} onExit - Callback when server exits
 * @returns {Promise<{process: ChildProcess, pid: number}|{error: string}>}
 */
export async function startServer(command, port, onExit) {
  // Check if port is already in use
  if (await isPortInUse(port)) {
    log(`app-server: Port ${port} already in use, will use existing server`)
    return { process: null, pid: null, existingServer: true }
  }

  log(`app-server: Starting dev server with "${command}" on port ${port}`)

  // Parse command for spawn
  const parts = command.split(' ')
  const cmd = parts[0]
  const args = parts.slice(1)

  try {
    const server = spawn(cmd, args, {
      detached: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env, PORT: String(port) }
    })

    // Log server output for debugging
    const verbose = !!process.env.RALPH_VERBOSE
    server.stdout?.on('data', (data) => {
      const str = data.toString().trim()
      if (str) log(`[dev-server] ${verbose ? str : str.slice(0, 200)}`)
    })
    server.stderr?.on('data', (data) => {
      const str = data.toString().trim()
      if (str) log(`[dev-server:err] ${verbose ? str : str.slice(0, 200)}`)
    })

    server.on('error', (err) => {
      log(`app-server: Server process error: ${err.message}`)
    })

    server.on('exit', (code) => {
      log(`app-server: Server exited with code ${code}`)
      if (onExit) onExit(code)
    })

    // Wait for server to be ready
    log(`app-server: Waiting for port ${port} to become available...`)
    const ready = await waitForPort(port, 15000)
    if (!ready) {
      // Kill the process if it didn't start properly
      try {
        if (server.pid) process.kill(-server.pid, 'SIGTERM')
        server.kill('SIGTERM')
      } catch { /* ignore */ }
      return { error: `Server did not start within 15s. Check that "${command}" is valid.` }
    }

    log(`app-server: Dev server ready on port ${port}`)
    return { process: server, pid: server.pid }
  } catch (e) {
    return { error: `Failed to start server: ${e.message}` }
  }
}

/**
 * Stop a dev server process
 * @param {ChildProcess} serverProcess - The server process
 * @param {number} pid - Process ID
 * @returns {boolean} - True if stopped successfully
 */
export function stopServer(serverProcess, pid) {
  if (!serverProcess) return false

  try {
    // Kill the process group (detached process)
    if (pid) {
      process.kill(-pid, 'SIGTERM')
    }
    serverProcess.kill('SIGTERM')
    log(`app-server: Dev server stopped (pid ${pid})`)
    return true
  } catch (e) {
    log(`app-server: Failed to stop server: ${e.message}`)
    // Try SIGKILL as fallback
    try {
      if (pid) {
        process.kill(-pid, 'SIGKILL')
      }
      return true
    } catch {
      // Process might already be dead
      return false
    }
  }
}
