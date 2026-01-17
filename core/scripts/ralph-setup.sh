#!/bin/bash
# ralph-setup.sh - Interactive setup for Ralph
#
# Configures cloud provider and VM settings

set -e

CONFIG_FILE="$HOME/.ralph-vm"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
cat << "LOGO"
  ██████╗  █████╗ ██╗     ██████╗ ██╗  ██╗
  ██╔══██╗██╔══██╗██║     ██╔══██╗██║  ██║
  ██████╔╝███████║██║     ██████╔╝███████║
  ██╔══██╗██╔══██║██║     ██╔═══╝ ██╔══██║
  ██║  ██║██║  ██║███████╗██║     ██║  ██║
  ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝
LOGO
echo -e "${NC}"
echo "ralph Setup"
echo "==========="
echo ""

# Check if already configured
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Existing configuration found:${NC}"
    cat "$CONFIG_FILE"
    echo ""
    read -p "Do you want to overwrite? [y/N] " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        echo "Interrupting."
        exit 0
    fi
    echo ""
fi

# Select cloud provider
echo "Select cloud provider:"
echo " 1) Hetzner"
echo " 2) GCP (Google Cloud)"
echo " 3) Local (no VM)"
echo ""
read -p "Choice [1]: " provider_choice
provider_choice="${provider_choice:-1}"

case "$provider_choice" in
    1)
        CLOUD="hetzner"
        echo ""
        echo -e "${CYAN}=== Hetzner Setup ===${NC}"

        # VM IP
        read -p "VM IP address: " vm_ip
        if [ -z "$vm_ip" ]; then
            echo -e "${RED}IP address required${NC}"
            exit 1
        fi

        # SSH User
        read -p "SSH user [root]: " ssh_user
        ssh_user="${ssh_user:-root}"

        # SSH Key
        default_key="$HOME/.ssh/id_rsa"
        if [ ! -f "$default_key" ]; then
            default_key="$HOME/.ssh/id_ed25519"
        fi
        read -p "SSH key [$default_key]: " ssh_key
        ssh_key="${ssh_key:-$default_key}"

        # VM Name
        read -p "VM name [ralph-sandbox]: " vm_name
        vm_name="${vm_name:-ralph-sandbox}"

        # Write config
        cat > "$CONFIG_FILE" << CONF
# Ralph VM Config - Hetzner
RALPH_CLOUD=hetzner

HETZNER_VM_NAME=$vm_name
HETZNER_VM_IP=$vm_ip
HETZNER_VM_USER=$ssh_user
HETZNER_SSH_KEY=$ssh_key
CONF
        ;;

    2)
        CLOUD="gcp"
        echo ""
        echo -e "${CYAN}=== GCP Setup ===${NC}"

        # Project ID
        read -p "GCP Project ID: " project_id
        if [ -z "$project_id" ]; then
            echo -e "${RED}Project ID required${NC}"
            exit 1
        fi

        # Zone
        read -p "Zone [europe-north1-a]: " zone
        zone="${zone:-europe-north1-a}"

        # VM Name
        read -p "VM name [ralph-sandbox]: " vm_name
        vm_name="${vm_name:-ralph-sandbox}"

        # User
        read -p "SSH user [$(whoami)]: " ssh_user
        ssh_user="${ssh_user:-$(whoami)}"

        # Write config
        cat > "$CONFIG_FILE" << CONF
# Ralph VM Config - GCP
RALPH_CLOUD=gcp

GCP_VM_PROJECT=$project_id
GCP_VM_ZONE=$zone
GCP_VM_NAME=$vm_name
GCP_VM_USER=$ssh_user
CONF
        ;;

    3)
        CLOUD="local"
        echo ""
        echo -e "${YELLOW}Local mode - no VM${NC}"

        cat > "$CONFIG_FILE" << CONF
# Ralph VM Config - Local
RALPH_CLOUD=local
CONF
        ;;

    *)
        echo -e "${RED}Invalid val${NC}"
        exit 1
        ;;
esac

# Claude Code mode
echo ""
echo -e "${CYAN}=== Claude Code Settings ===${NC}"
echo ""
echo "How do you run Claude Code locally?"
echo " 1) MAX subscription (flat rate)"
echo " 2) API key (pay-per-token)"
echo ""
read -p "Choice [1]: " local_mode
local_mode="${local_mode:-1}"

if [ "$local_mode" = "1" ]; then
    echo "CLAUDE_LOCAL_MODE=max" >> "$CONFIG_FILE"
else
    echo "CLAUDE_LOCAL_MODE=api" >> "$CONFIG_FILE"
fi

# VM Claude mode (if not local)
if [ "$CLOUD" != "local" ]; then
    echo ""
    echo "How do you run Claude Code on VM?"
    echo " 1) MAX subscription (flat rate)"
    echo " 2) API key (pay-per-token)"
    echo ""
    read -p "Selection [1]: " vm_mode
    vm_mode="${vm_mode:-1}"

    if [ "$vm_mode" = "1" ]; then
        echo "CLAUDE_VM_MODE=max" >> "$CONFIG_FILE"
        echo ""
        echo -e "${YELLOW}Tips for MAX on VM:${NC}"
        echo " - Timeout may need to be increased (supervisor checks)"
        echo " - Limit parallel worktrees to 2-3"
	    	echo " - (Optional) Login with: ssh VM && claude login"
    else
        echo "CLAUDE_VM_MODE=api" >> "$CONFIG_FILE"
        echo ""
        echo -e "${YELLOW}Tips for API on VM:${NC}"
        echo " - Put ANTHROPIC_API_KEY in VM's environment"
        echo " - Faster response, but costs per token"
    fi
fi

# ntfy topic
echo ""
read -p "ntfy.sh topic for notifications (optional): " ntfy_topic
echo "NTFY_TOPIC=$ntfy_topic" >> "$CONFIG_FILE"

echo ""
echo -e "${GREEN}✅ Configuration saved to $CONFIG_FILE${NC}"
echo ""
cat "$CONFIG_FILE"
echo ""

# Test connection
if [ "$CLOUD" != "local" ]; then
    echo -e "${YELLOW}Testar connection...${NC}"

    if [ "$CLOUD" = "hetzner" ]; then
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$ssh_key" "$ssh_user@$vm_ip" "echo 'OK'" 2>/dev/null; then
            echo -e "${GREEN}✅ SSH connection OK${NC}"

            # Check if Claude Code exists
            if ssh -o StrictHostKeyChecking=no -i "$ssh_key" "$ssh_user@$vm_ip" "which claude" 2>/dev/null; then
                echo -e "${GREEN}✅ Claude Code installed on VM${NC}"
            else
                echo -e "${YELLOW}⚠ Claude Code not found on VM${NC}"
                echo " Install with: npm install -g @anthropic-ai/claude-code"
            fi
        else
            echo -e "${RED}❌ Could not connect to VM${NC}"
            echo " Check IP, user and SSH key"
        fi
    elif [ "$CLOUD" = "gcp" ]; then
        if gcloud compute ssh "$ssh_user@$vm_name" --zone="$zone" --project="$project_id" --command="echo OK" 2>/dev/null; then
            echo -e "${GREEN}✅ GCP connection OK${NC}"
        else
            echo -e "${RED}❌ Could not connect to VM${NC}"
            echo " Check gcloud auth and project settings"
        fi
    fi
fi

echo ""
echo -e "${GREEN}Ralph setup ready!${NC}"
echo ""
echo "Next steps:"
	echo " ralph-inferno discover my-app # Create PRD"
	echo " ralph-inferno plan # Create implementation plan"
echo " ralph handoff # Run on VM"
