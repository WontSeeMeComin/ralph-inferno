// cli/run-local.js - Local sandbox execution for Ralph specs
import chalk from 'chalk';
import path from 'path';
import fs from 'fs';
import { spawn } from 'child_process';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Run a spec file locally with sandbox and transcript support
 *
 * @param {string} specPath - Path to the spec file
 * @param {Object} options - Execution options
 * @param {string} options.sandbox - Sandbox mode: strict|permissive|monitor
 * @param {boolean} options.verbose - Show all thoughts and tool calls
 * @param {boolean} options.dryRun - Parse but don't execute commands
 */
export async function runLocal(specPath, options = {}) {
  const fire = chalk.hex('#FF6B35');
  const dim = chalk.dim;
  const cyan = chalk.cyan;
  const green = chalk.green;
  const red = chalk.red;
  const yellow = chalk.yellow;

  console.log(fire(`
  Local Test Mode
`));

  // Validate spec path
  if (!specPath) {
    console.log(red('Usage: ralph run-local <spec-file> [options]'));
    console.log('');
    console.log(dim('Options:'));
    console.log(dim('  --sandbox <mode>   strict|permissive|monitor (default: monitor)'));
    console.log(dim('  --verbose          Show all thoughts and tool calls'));
    console.log(dim('  --dry-run          Parse but don\'t execute commands'));
    console.log('');
    console.log(dim('Examples:'));
    console.log(dim('  ralph run-local .ralph/specs/001-setup.md'));
    console.log(dim('  ralph run-local .ralph/specs/001-setup.md --sandbox strict --verbose'));
    return;
  }

  // Check if spec file exists
  const resolvedSpec = path.resolve(process.cwd(), specPath);
  if (!fs.existsSync(resolvedSpec)) {
    console.log(red(`Spec file not found: ${specPath}`));
    return;
  }

  // Set up environment
  const sandboxMode = options.sandbox || 'monitor';
  const env = {
    ...process.env,
    RALPH_SANDBOX_MODE: sandboxMode,
    RALPH_VERBOSE: options.verbose ? '1' : '',
    RALPH_DRY_RUN: options.dryRun ? '1' : '',
    RALPH_TRANSCRIPT: '1'  // Always enable transcripts in local mode
  };

  // Display configuration
  console.log(cyan('Configuration:'));
  console.log(dim(`  Spec:       ${specPath}`));
  console.log(dim(`  Sandbox:    ${sandboxMode}`));
  console.log(dim(`  Verbose:    ${options.verbose ? 'yes' : 'no'}`));
  console.log(dim(`  Dry run:    ${options.dryRun ? 'yes' : 'no'}`));
  console.log(dim(`  Transcripts: .ralph/transcripts/`));
  console.log('');

  if (sandboxMode === 'strict') {
    console.log(yellow('Strict sandbox: Only allowlisted commands will execute'));
  } else if (sandboxMode === 'monitor') {
    console.log(dim('Monitor sandbox: All commands logged, minimal blocking'));
  }
  console.log('');

  // Path to agent-run.mjs
  const agentPath = path.join(__dirname, '..', 'core', 'scripts', 'agent-run.mjs');

  if (!fs.existsSync(agentPath)) {
    console.log(red(`Agent script not found: ${agentPath}`));
    console.log(dim('Run "ralph update" to ensure core files are in place.'));
    return;
  }

  console.log(dim('Starting agent...'));
  console.log(dim('─'.repeat(60)));
  console.log('');

  // Spawn the agent process
  const child = spawn('node', [agentPath, resolvedSpec], {
    env,
    stdio: 'inherit',  // Stream output in real-time
    cwd: process.cwd()
  });

  // Handle process exit
  child.on('exit', (code) => {
    console.log('');
    console.log(dim('─'.repeat(60)));

    if (code === 0) {
      console.log(green('Spec completed successfully'));
    } else if (code === 2) {
      console.log(red(`LLM error (exit code: ${code})`));
    } else {
      console.log(red(`Spec failed (exit code: ${code})`));
    }

    console.log(dim('Check .ralph/transcripts/ for full session log'));
  });

  child.on('error', (err) => {
    console.log(red(`Failed to start agent: ${err.message}`));
  });
}
