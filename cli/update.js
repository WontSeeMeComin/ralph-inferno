import chalk from 'chalk';
import fs from 'fs-extra';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { execSync } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const CORE_DIR = join(__dirname, '..', 'core');
const STACKS_DIR = join(__dirname, '..', 'stacks');
const TARGET_DIR = '.ralph';
const CONFIG_FILE = join(TARGET_DIR, 'config.json');

export async function update() {
  console.log(chalk.cyan(`
🔄 Ralph Inferno Update
`));

  // Check if installed
  if (!await fs.pathExists(CONFIG_FILE)) {
    console.log(chalk.red('❌ Ralph not installed in this directory.'));
    console.log(chalk.dim('Run: npx ralph-inferno install'));
    return;
  }

  // Read existing config
  const config = await fs.readJson(CONFIG_FILE);

  // Ensure new LLM config defaults exist (do not override user settings)
  if (!config.llm) {
    config.llm = {
      provider: 'claude',
      fallback_provider: 'claude',
      agent_mode: 'claude',
      timeout_seconds: 120,
      max_retries: 2,
      lmstudio: { base_url: 'http://localhost:1234', model: 'qwen/qwen3-next-80b', vision_model: 'zai-org/glm-4.6v-flash' },
      ollama: { host: 'http://localhost:11434', model: 'qwen3' },
      openrouter: { base_url: 'https://openrouter.ai/api/v1', model: 'openai/gpt-4o-mini' }
    };
  }

  // Backfill newer optional fields without overwriting user config
  if (!config.llm.lmstudio) config.llm.lmstudio = { base_url: 'http://localhost:1234', model: 'qwen/qwen3-next-80b' };
  if (!config.llm.lmstudio.vision_model) config.llm.lmstudio.vision_model = 'zai-org/glm-4.6v-flash';
  if (!config.llm.lmstudio.use_case_models) config.llm.lmstudio.use_case_models = {};

  if (!config.llm.ollama) config.llm.ollama = { host: 'http://localhost:11434', model: 'qwen3' };
  if (!config.llm.ollama.use_case_models) config.llm.ollama.use_case_models = {};

  if (!config.llm.openrouter) config.llm.openrouter = { base_url: 'https://openrouter.ai/api/v1', model: 'openai/gpt-4o-mini' };
  if (!config.llm.openrouter.use_case_models) config.llm.openrouter.use_case_models = {};

  if (!config.llm.use_case_providers) config.llm.use_case_providers = {};

  // Backfill plugins config (new in unopinionated refactor)
  if (!config.plugins) {
    config.plugins = {
      verify: 'auto',
      test: 'auto',
      screenshot: 'auto'
    };
  }

  console.log(chalk.dim('Current config:'));
  console.log(chalk.dim(`  Provider: ${config.provider || 'none'}`));
  console.log(chalk.dim(`  Language: ${config.language || 'en'}`));
  console.log(chalk.dim(`  VM: ${config.vm_name || 'not set'}`));
  console.log('');

  // Check for missing required config
  const warnings = [];
  if (!config.provider || config.provider === 'none') {
    warnings.push('provider - VM is required for safe execution');
  }
  if (!config.vm_name) {
    warnings.push('vm_name - No VM name configured');
  }
  if (!config.github?.username) {
    warnings.push('github.username - Needed for repo operations');
  }

  if (warnings.length > 0) {
    console.log(chalk.yellow('⚠️  Missing config:'));
    warnings.forEach(w => console.log(chalk.yellow(`   - ${w}`)));
    console.log(chalk.dim('   Fix with: ralph-inferno config --set key=value\n'));
  }

  // Update core directories
  console.log(chalk.cyan('Updating core files...'));

  const dirs = ['lib', 'scripts', 'templates', 'plugins', '.claude'];
  for (const dir of dirs) {
    const src = join(CORE_DIR, dir);
    const dest = join(TARGET_DIR, dir);

    if (await fs.pathExists(src)) {
      // Remove old and copy new
      await fs.remove(dest);
      await fs.copy(src, dest);

      const files = await countFiles(dest);
      console.log(chalk.green(`✅ ${dir}/ updated (${files} files)`));
    }
  }

  // Update stacks from root-level stacks/
  if (await fs.pathExists(STACKS_DIR)) {
    const stacksDest = join(TARGET_DIR, 'templates', 'stacks');
    await fs.remove(stacksDest);
    await fs.copy(STACKS_DIR, stacksDest);
    const files = await countFiles(stacksDest);
    console.log(chalk.green(`✅ stacks/ updated (${files} files)`));
  }

  // Also copy .claude/commands to project root (where Claude Code reads from)
  const claudeSrc = join(CORE_DIR, '.claude', 'commands');
  const claudeDest = join('.claude', 'commands');
  if (await fs.pathExists(claudeSrc)) {
    await fs.ensureDir('.claude');
    await fs.copy(claudeSrc, claudeDest, { overwrite: true });
    console.log(chalk.green('✅ .claude/commands/ synced to project root'));
  }

  // Ensure MCP SDK is installed (required for browser verification)
  await ensureMcpSdk();

  // Config is preserved (we didn't touch it)
  console.log(chalk.green('✅ config.json preserved'));

  // Update version in config
  const pkg = await fs.readJson(join(__dirname, '..', 'package.json'));
  config.version = pkg.version;
  await fs.writeJson(CONFIG_FILE, config, { spaces: 2 });

  console.log(chalk.green(`
✅ Update complete! (v${pkg.version})
`));
}

async function countFiles(dir) {
  let count = 0;
  const items = await fs.readdir(dir, { withFileTypes: true });

  for (const item of items) {
    if (item.isDirectory()) {
      count += await countFiles(join(dir, item.name));
    } else {
      count++;
    }
  }

  return count;
}

/**
 * Ensure MCP SDK is installed in the target project
 * Required for browser verification and MCP tool access
 */
async function ensureMcpSdk() {
  const pkgPath = 'package.json';
  const sdkPackage = '@modelcontextprotocol/sdk';

  // Check if package.json exists
  if (!await fs.pathExists(pkgPath)) {
    console.log(chalk.dim('  No package.json found, skipping MCP SDK install'));
    return;
  }

  try {
    const pkg = await fs.readJson(pkgPath);
    const deps = pkg.dependencies || {};
    const devDeps = pkg.devDependencies || {};

    // Check if already installed
    if (deps[sdkPackage] || devDeps[sdkPackage]) {
      // Check if node_modules has it
      const sdkPath = join('node_modules', '@modelcontextprotocol', 'sdk');
      if (await fs.pathExists(sdkPath)) {
        console.log(chalk.dim('  MCP SDK already installed'));
        return;
      }
      // In package.json but not installed - run npm install
      console.log(chalk.cyan('  Installing dependencies (MCP SDK in package.json but not installed)...'));
      execSync('npm install', { stdio: 'inherit' });
      console.log(chalk.green('✅ Dependencies installed'));
      return;
    }

    // Add to devDependencies and install
    console.log(chalk.cyan('  Adding MCP SDK for browser verification...'));
    execSync(`npm install --save-dev ${sdkPackage}`, { stdio: 'inherit' });
    console.log(chalk.green('✅ MCP SDK installed'));
  } catch (e) {
    console.log(chalk.yellow(`⚠️  Could not install MCP SDK: ${e.message}`));
    console.log(chalk.dim(`   Run manually: npm install --save-dev ${sdkPackage}`));
  }
}
