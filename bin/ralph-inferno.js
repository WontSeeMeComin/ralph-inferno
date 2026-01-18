#!/usr/bin/env node

import { program } from 'commander';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

program
  .name('ralph-inferno')
  .description('AI-driven autonomous development workflow')
  .version('1.0.0');

program
  .command('install')
  .description('Install Ralph Inferno in current project')
  .action(async () => {
    const { install } = await import('../cli/install.js');
    await install();
  });

program
  .command('update')
  .description('Update core files, preserve config')
  .action(async () => {
    const { update } = await import('../cli/update.js');
    await update();
  });

program
  .command('discover')
  .description('Generate docs/prd.md + CLAUDE.md using configured LLM provider (no Claude UI required)')
  .argument('[projectName]', 'Optional project name')
  .option('--idea <text>', 'Short description / what are we building?')
  .option('--input <file>', 'Optional meeting notes / transcript file')
  .option('--provider <provider>', 'Override provider for discovery (lmstudio|ollama|openrouter|auto)')
  .action(async (projectName, opts) => {
    const { discover } = await import('../cli/discover.js');
    await discover(projectName, opts);
  });

program
  .command('plan')
  .description('Generate docs/IMPLEMENTATION_PLAN.md and specs/*.md from docs/prd.md using configured LLM provider')
  .option('--prd <file>', 'Path to PRD (default: docs/prd.md)')
  .option('--provider <provider>', 'Override provider for planning (lmstudio|ollama|openrouter|auto)')
  .action(async (opts) => {
    const { plan } = await import('../cli/plan.js');
    await plan(opts);
  });

program
  .command('run-local')
  .description('Run a spec file locally with sandbox and transcript support')
  .argument('<spec>', 'Path to the spec file to execute')
  .option('--sandbox <mode>', 'Sandbox mode: strict|permissive|monitor (default: monitor)', 'monitor')
  .option('--verbose', 'Show all thoughts and tool calls')
  .option('--dry-run', 'Parse but don\'t execute commands')
  .action(async (spec, opts) => {
    const { runLocal } = await import('../cli/run-local.js');
    await runLocal(spec, opts);
  });

program.parse();
