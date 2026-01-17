#!/bin/bash
# vm-init.sh - Runs automatically when VM starts
# Installs everything needed for ralph

set -e

echo "=== Ralph VM Setup ==="

# Update system
sudo apt-get update

# Install basic tools
sudo apt-get install -y curl git ripgrep jq tmux

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install Claude Code CLI (optional)
if [ "${RALPH_INSTALL_CLAUDE:-0}" = "1" ]; then
	sudo npm install -g @anthropic-ai/claude-code
else
	echo "[vm-init] Skipping Claude Code install (set RALPH_INSTALL_CLAUDE=1 to enable)"
fi

# Install the GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt-get update
sudo apt-get install -y gh

# Create workspace
mkdir -p ~/workspace
mkdir -p ~/scripts
mkdir -p ~/specs

echo ""
echo "=== Installation complete! ==="
echo ""
echo "Next steps (one-time configuration):"
echo "1. (Optional) Login to Claude: claude"
echo "2. Login to GitHub: gh auth login"
echo ""
echo "Then the VM is ready for ralph!"
