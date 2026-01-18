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

export async function plan(options = {}) {
  const cwd = process.cwd();
  const providerOverride = options.provider || null;

  const prdPath = options.prd
    ? resolve(cwd, options.prd)
    : findFirstExisting([
        resolve(cwd, 'docs/prd.md'),
        resolve(cwd, 'docs/PRD.md'),
      ]);

  if (!prdPath || !(await fs.pathExists(prdPath))) {
    throw new Error('PRD not found. Expected docs/prd.md (or docs/PRD.md). Run discover first or pass --prd <path>.');
  }

  const commandFile = findFirstExisting([
    resolve(cwd, '.ralph/.claude/commands/ralph:plan.md'),
    resolve(cwd, '.claude/commands/ralph:plan.md'),
    join(__dirname, '..', 'core', '.claude', 'commands', 'ralph:plan.md'),
  ]);

  if (!commandFile) {
    throw new Error('Could not locate ralph:plan.md (expected .ralph/.claude/commands or .claude/commands)');
  }

  const cmdText = await fs.readFile(commandFile, 'utf8');
  const prdText = await fs.readFile(prdPath, 'utf8');

  const spec = `# CLI: ralph-inferno plan\n\n` +
    `You are running in NON-INTERACTIVE CLI mode. Do NOT ask the user questions.\n` +
    `Use the PRD content below as the single source of truth.\n\n` +
    `PRD PATH: ${prdPath}\n\n` +
    `---\n\n${prdText}\n\n---\n\n` +
    `Follow the /ralph:plan instructions below (create docs/IMPLEMENTATION_PLAN.md and specs/*.md).\n` +
    `Keep each spec minimal (<= 20 lines). Only include testing setup if the PRD explicitly requests it.\n\n` +
    `---\n\n` +
    `${cmdText}\n\n` +
    `---\n\n` +
    `When complete: write <promise>DONE</promise>\n`;

  const tmpSpec = join(os.tmpdir(), `ralph-plan-${Date.now()}.md`);
  await fs.writeFile(tmpSpec, spec, 'utf8');

  const agentScript = findFirstExisting([
    resolve(cwd, '.ralph/scripts/agent-run.mjs'),
    join(__dirname, '..', 'core', 'scripts', 'agent-run.mjs'),
  ]);

  if (!agentScript) {
    throw new Error('Could not locate agent-run.mjs (expected .ralph/scripts/agent-run.mjs)');
  }

  const env = { ...process.env };
  if (providerOverride) env.RALPH_LLM_PROVIDER_PLAN = providerOverride;

  await new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [agentScript, tmpSpec, '--use-case', 'plan'], {
      stdio: 'inherit',
      cwd,
      env,
    });
    child.on('exit', (code) => {
      if (code === 0) return resolvePromise();
      reject(new Error(`plan failed (exit ${code})`));
    });
  });
}
