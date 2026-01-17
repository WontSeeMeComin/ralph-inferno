#!/bin/bash
# security.sh - DevSecOps checks for the ralph VM
#
# Runs before first run to secure VM
# Exit 0 = OK, Exit 1 = Warning/Error

set -e

echo "🔒 DevSecOps Security Check"
echo "==========================="
echo ""

WARNINGS=0
ERRORS=0

# 1. SSH configuration
echo "1️⃣ SSH security..."
if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
    echo " ✅ Passwordauth turned off"
else
    echo " ⚠️ Password auth may be on - should be turned off"
    WARNINGS=$((WARNINGS + 1))
fi

if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
    echo " ✅ Root login disabled"
else
    echo " ⚠️ Root login may be allowed"
    WARNINGS=$((WARNINGS + 1))
fi

# 2. Firewall
echo "2️⃣ Firewall..."
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        echo " ✅ UFW active"
        # Check that only necessary ports are open
        if ufw status | grep -q "22/tcp"; then
            echo " ✅ SSH (22) open"
        fi
    else
        echo " ⚠️ UFW installed but not active"
        WARNINGS=$((WARNINGS + 1))
    fi
elif command -v firewall-cmd &> /dev/null; then
    if firewall-cmd --state 2>/dev/null | grep -q "running"; then
        echo " ✅ Firewalld active"
    else
        echo " ⚠️ Firewalld not active"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo " ⚠️ No firewall found (ufw/firewalld)"
    WARNINGS=$((WARNINGS + 1))
fi

# 3. Users & permissions
echo "3️⃣ User..."
if id ralph &>/dev/null; then
    echo " ✅ ralph user exists"

    # Check that ralph has limited sudo
    if sudo -l -U ralph 2>/dev/null | grep -q "ALL"; then
        echo " ⚠️ ralph has full sudo - should be limited"
        WARNINGS=$((WARNINGS + 1))
    else
        echo " ✅ ralph has limited sudo"
    fi
else
    echo " ❌ ralph user missing"
    ERRORS=$((ERRORS + 1))
fi

# 4. Updates
echo "4️⃣ System updates..."
if command -v apt &> /dev/null; then
    UPDATES=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")
    if [ "$UPDATES" -gt 10 ]; then
        echo " ⚠️ $UPDATES package can be updated"
        WARNINGS=$((WARNINGS + 1))
    else
        echo " ✅ System relatively updated"
    fi
elif command -v dnf &> /dev/null; then
    UPDATES=$(dnf check-update --quiet 2>/dev/null | wc -l || echo "0")
    if [ "$UPDATES" -gt 10 ]; then
        echo " ⚠️ $UPDATES package can be updated"
        WARNINGS=$((WARNINGS + 1))
    else
        echo " ✅ System relatively updated"
    fi
fi

# 5. Secrets
echo "5️⃣ Secrets..."
if [ -f "$HOME/.env" ]; then
    echo "⚠️ .env in home folder - move to project"
    WARNINGS=$((WARNINGS + 1))
else
    echo " ✅ No .env in home"
fi

# Check that no API keys are in bash_history
if grep -qiE "(api_key|secret|token|password)=" "$HOME/.bash_history" 2>/dev/null; then
    echo " ⚠️ Possible secrets in bash_history"
    WARNINGS=$((WARNINGS + 1))
else
    echo " ✅ No obvious secrets in history"
fi

# 6. Docker (if installed)
echo "6️⃣ Docker..."
if command -v docker &> /dev/null; then
    if docker info &>/dev/null; then
        echo " ✅ Docker is running"

        # Check that ralph is in the docker group
        if groups ralph 2>/dev/null | grep -q docker; then
            echo " ✅ ralph in docker group"
        else
            echo " ⚠️ ralph not in docker group"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo " ⚠️ Docker installed but not running"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo " ℹ️ Docker not installed"
fi

# 7. Network exposure
echo "7️⃣ Network exposure..."
LISTENING=$(ss -tlnp 2>/dev/null | grep LISTEN | wc -l)
echo "ℹ️ $LISTENING services listening"

# Warn if something is listening on 0.0.0.0 (all interfaces)
EXPOSED=$(ss -tlnp 2>/dev/null | grep "0.0.0.0:" | grep -v ":22" | wc -l)
if [ "$EXPOSED" -gt 0 ]; then
    echo " ⚠️ $EXPOSED services exposed on all interfaces"
    ss -tlnp 2>/dev/null | grep "0.0.0.0:" | grep -v ":22"
    WARNINGS=$((WARNINGS + 1))
else
    echo " ✅ Only SSH exposed externally"
fi

# 8. Disk & Resources
echo "8️⃣ Resources..."
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USAGE" -gt 80 ]; then
    echo " ⚠️ Disk ${DISK_USAGE}% full"
    WARNINGS=$((WARNINGS + 1))
else
    echo " ✅ Disk OK (${DISK_USAGE}%)"
fi

MEM_FREE=$(free -m | awk 'NR==2 {print $7}')
if [ "$MEM_FREE" -lt 500 ]; then
    echo " ⚠️ Low free memory (${MEM_FREE}MB)"
    WARNINGS=$((WARNINGS + 1))
else
    echo " ✅ Memory OK (${MEM_FREE}MB free)"
fi

# Result
echo ""
echo "================================"
if [ $ERRORS -gt 0 ]; then
    echo "❌ SECURITY CHECK FAILED ($ERRORS errors, $WARNINGS warnings)"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo "⚠️ SECURITY CHECK: $WARNINGS warnings"
    echo " Run 'ralph secure' to fix"
    exit 0
else
    echo "✅ SECURITY CHECK OK"
    exit 0
fi
