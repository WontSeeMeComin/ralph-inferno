import fs from 'fs-extra';
import { fileURLToPath } from 'url';
import { dirname, join, resolve } from 'path';
import os from 'os';
import { spawn } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

function findFirstExisting(paths) {
  for (const p of paths) {
    if (fs.existsSync(p)) return p;
  }
  return null;
}

export async function discover(projectName, options = {}) {
  const cwd = process.cwd();
  const idea = options.idea || '';
  const inputPath = options.input ? resolve(cwd, options.input) : null;
  const providerOverride = options.provider || null;

  const commandFile = findFirstExisting([
    resolve(cwd, '.ralph/.claude/commands/ralph:discover.md'),
    resolve(cwd, '.claude/commands/ralph:discover.md'),
    join(__dirname, '..', 'core', '.claude', 'commands', 'ralph:discover.md'),
  ]);

  if (!commandFile) {
    throw new Error('Could not locate ralph:discover.md (expected .ralph/.claude/commands or .claude/commands)');
  }

  const cmdText = await fs.readFile(commandFile, 'utf8');
  const inputText = inputPath && (await fs.pathExists(inputPath)) ? await fs.readFile(inputPath, 'utf8') : '';

  const spec = `# CLI: ralph-inferno discover\n\n` +
    `You are running in NON-INTERACTIVE CLI mode. Do NOT ask the user questions.\n` +
    `If required information is missing, make reasonable assumptions and record them in docs/prd.md.\n\n` +
    (projectName ? `Project name hint: ${projectName}\n\n` : '') +
    (idea ? `Idea/description:\n${idea}\n\n` : '') +
    (inputText ? `Meeting notes / input file content:\n${inputText}\n\n` : '') +
    `Follow the /ralph:discover instructions below, but adapt them for CLI (no numbered back-and-forth).\n` +
    `Mandatory outputs: docs/prd.md and CLAUDE.md.\n\n` +
    `---\n\n` +
    `${cmdText}\n\n` +
    `---\n\n` +
    `When complete: write <promise>DONE</promise>\n`;

  const tmpSpec = join(os.tmpdir(), `ralph-discover-${Date.now()}.md`);
  await fs.writeFile(tmpSpec, spec, 'utf8');

  const agentScript = findFirstExisting([
    resolve(cwd, '.ralph/scripts/agent-run.mjs'),
    join(__dirname, '..', 'core', 'scripts', 'agent-run.mjs'),
  ]);

  if (!agentScript) {
    throw new Error('Could not locate agent-run.mjs (expected .ralph/scripts/agent-run.mjs)');
  }

  const env = { ...process.env };
  if (providerOverride) env.RALPH_LLM_PROVIDER_DISCOVER = providerOverride;

  await new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [agentScript, tmpSpec, '--use-case', 'discover'], {
      stdio: 'inherit',
      cwd,
      env,
    });
    child.on('exit', (code) => {
      if (code === 0) return resolvePromise();
      reject(new Error(`discover failed (exit ${code})`));
    });
  });
}
