// cli/run-local.js - Local sandbox execution for Ralph specs
import chalk from 'chalk';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import { spawn } from 'child_process';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SPECS_DIR = 'specs';
const CHECKSUM_DIR = '.spec-checksums';

/**
 * Get MD5 checksum of a file
 */
function getChecksum(filePath) {
  const content = fs.readFileSync(filePath);
  return crypto.createHash('md5').update(content).digest('hex');
}

/**
 * Check if spec is already done (checksum matches)
 */
function isSpecDone(specPath) {
  const basename = path.basename(specPath);
  const checksumFile = path.join(CHECKSUM_DIR, `${basename}.md5`);

  if (!fs.existsSync(checksumFile)) return false;

  const oldChecksum = fs.readFileSync(checksumFile, 'utf-8').trim();
  const newChecksum = getChecksum(specPath);

  return oldChecksum === newChecksum;
}

/**
 * Mark spec as done (save checksum)
 */
function markSpecDone(specPath) {
  const basename = path.basename(specPath);
  fs.mkdirSync(CHECKSUM_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(CHECKSUM_DIR, `${basename}.md5`),
    getChecksum(specPath)
  );
}

/**
 * Get list of incomplete specs
 */
function getIncompleteSpecs() {
  if (!fs.existsSync(SPECS_DIR)) return [];

  const specs = fs.readdirSync(SPECS_DIR)
    .filter(f => f.endsWith('.md'))
    .map(f => path.join(SPECS_DIR, f))
    .sort();

  return specs.filter(spec => !isSpecDone(spec));
}

/**
 * Get all specs
 */
function getAllSpecs() {
  if (!fs.existsSync(SPECS_DIR)) return [];

  return fs.readdirSync(SPECS_DIR)
    .filter(f => f.endsWith('.md'))
    .map(f => path.join(SPECS_DIR, f))
    .sort();
}

/**
 * Run a single spec with sandbox protection
 * Returns a promise that resolves with exit code
 */
function runSpec(specPath, env, options) {
  return new Promise((resolve) => {
    const dim = chalk.dim;
    const green = chalk.green;
    const red = chalk.red;
    const yellow = chalk.yellow;
    const cyan = chalk.cyan;

    const specName = path.basename(specPath, '.md');
    console.log(cyan(`\n=== ${specName} ===`));

    if (isSpecDone(specPath)) {
      console.log(dim('⏭  Already done (checksum match)'));
      resolve(0);
      return;
    }

    // Path to agent-run.mjs - check installed location first, then CLI location
    let agentPath = path.join(process.cwd(), '.ralph', 'scripts', 'agent-run.mjs');
    if (!fs.existsSync(agentPath)) {
      agentPath = path.join(__dirname, '..', 'core', 'scripts', 'agent-run.mjs');
    }

    if (!fs.existsSync(agentPath)) {
      console.log(red(`Agent script not found`));
      console.log(dim('Run "ralph-inferno update" to ensure core files are in place.'));
      resolve(1);
      return;
    }

    console.log(dim('Starting agent...'));

    const child = spawn('node', [agentPath, specPath, '--use-case', 'execute'], {
      env,
      stdio: 'inherit',
      cwd: process.cwd()
    });

    child.on('exit', (code) => {
      if (code === 0) {
        console.log(green(`✅ ${specName} completed`));
        if (!options.dryRun) {
          markSpecDone(specPath);
        }
      } else {
        console.log(red(`❌ ${specName} failed (exit code: ${code})`));
      }
      resolve(code);
    });

    child.on('error', (err) => {
      console.log(red(`Failed to start agent: ${err.message}`));
      resolve(1);
    });
  });
}

/**
 * Run a spec file locally with sandbox and transcript support
 *
 * @param {string} specPath - Path to the spec file (optional - if omitted, runs all specs)
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
  🔥 Local Test Mode
`));

  // Set up environment with sandbox protection
  const sandboxMode = options.sandbox || 'monitor';
  // Honor env vars OR CLI flags
  const isVerbose = options.verbose || process.env.RALPH_VERBOSE === '1';
  const isDryRun = options.dryRun || process.env.RALPH_DRY_RUN === '1';

  const env = {
    ...process.env,
    RALPH_SANDBOX_MODE: sandboxMode,
    RALPH_VERBOSE: isVerbose ? '1' : '',
    RALPH_DRY_RUN: isDryRun ? '1' : '',
    RALPH_TRANSCRIPT: '1'
  };

  // Display configuration
  console.log(cyan('Configuration:'));
  console.log(dim(`  Sandbox:     ${sandboxMode}`));
  console.log(dim(`  Verbose:     ${isVerbose ? 'yes' : 'no'}`));
  console.log(dim(`  Dry run:     ${isDryRun ? 'yes' : 'no'}`));
  console.log(dim(`  Transcripts: .ralph/transcripts/`));

  if (sandboxMode === 'strict') {
    console.log(yellow('\n⚠️  Strict sandbox: Only allowlisted commands will execute'));
  } else if (sandboxMode === 'monitor') {
    console.log(dim('\nMonitor sandbox: All commands logged, dangerous commands blocked'));
  }

  // Single spec mode
  if (specPath) {
    const resolvedSpec = path.resolve(process.cwd(), specPath);
    if (!fs.existsSync(resolvedSpec)) {
      console.log(red(`\nSpec file not found: ${specPath}`));
      return;
    }

    console.log(dim(`\nRunning single spec: ${specPath}`));
    console.log(dim('─'.repeat(60)));

    const code = await runSpec(resolvedSpec, env, options);

    console.log(dim('─'.repeat(60)));
    console.log(dim('Check .ralph/transcripts/ for full session log'));
    return;
  }

  // Full loop mode - no spec provided
  const allSpecs = getAllSpecs();
  const incompleteSpecs = getIncompleteSpecs();

  if (allSpecs.length === 0) {
    console.log(red('\nNo specs found in specs/'));
    console.log(dim('Run /ralph:plan to generate specs first.'));
    return;
  }

  console.log(dim(`\nSpecs: ${allSpecs.length - incompleteSpecs.length}/${allSpecs.length} done`));

  if (incompleteSpecs.length === 0) {
    console.log(green('\n✅ All specs already completed!'));
    console.log(dim('Delete .spec-checksums/*.md5 to re-run specs.'));
    return;
  }

  console.log(dim(`Running ${incompleteSpecs.length} remaining specs...`));
  console.log(dim('─'.repeat(60)));

  let completed = 0;
  let failed = 0;

  for (const spec of incompleteSpecs) {
    const code = await runSpec(spec, env, options);

    if (code === 0) {
      completed++;
    } else {
      failed++;
      // Stop on first failure in loop mode
      console.log(yellow(`\nStopping loop due to failure. ${completed} completed, ${failed} failed.`));
      break;
    }
  }

  console.log(dim('─'.repeat(60)));
  console.log(cyan(`\nResults: ${completed} completed, ${failed} failed`));
  console.log(dim(`Total: ${allSpecs.length - incompleteSpecs.length + completed}/${allSpecs.length} specs done`));
  console.log(dim('Check .ralph/transcripts/ for session logs'));
}
