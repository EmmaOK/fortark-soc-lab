#!/usr/bin/env bash
# enroll-wazuh-agent.sh — Installs and enrolls the Wazuh agent on lab-target
# Run after Wazuh manager is healthy and lab-target container is up

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

[[ -f .env ]] || { echo "ERROR: .env not found."; exit 1; }
source .env

ok()   { echo "[✓] $*"; }
info() { echo "[*] $*"; }

info "Installing Wazuh agent on lab-target..."
docker exec lab-target bash -c "
    apt-get update -qq &&
    apt-get install -y -qq curl gnupg &&
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add - &&
    echo 'deb https://packages.wazuh.com/4.x/apt/ stable main' > /etc/apt/sources.list.d/wazuh.list &&
    apt-get update -qq &&
    WAZUH_MANAGER=soc-wazuh-manager WAZUH_AGENT_NAME=lab-target apt-get install -y -qq wazuh-agent &&
    /var/ossec/bin/wazuh-control start
" && ok "Wazuh agent installed and started on lab-target"

info "Waiting for agent to enroll..."
sleep 10

# Verify
AGENTS=$(curl -sk -u "${WAZUH_API_USERNAME}:${WAZUH_API_PASSWORD}" \
    https://localhost:55000/agents?pretty=true 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
agents = d.get('data', {}).get('affected_items', [])
for a in agents:
    print(f\"  {a['id']} — {a['name']} — {a['status']}\")
" 2>/dev/null || echo "  (could not query agents)")

ok "Enrolled agents:"
echo "$AGENTS"
