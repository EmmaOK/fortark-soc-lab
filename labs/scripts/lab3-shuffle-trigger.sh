#!/usr/bin/env bash
# Lab 3 — Shuffle Playbook Test Trigger
# Fires a test webhook payload to your Shuffle workflow to verify
# the automation pipeline is working end-to-end.
#
# Usage:
#   SHUFFLE_WEBHOOK_URL=https://your-shuffle/api/v1/hooks/xxx ./lab3-shuffle-trigger.sh
#
# The payload mimics a real Wazuh alert so your playbook processes it identically
# to a live alert. Run after building the playbook in the Lab 3 guide.

set -euo pipefail

WEBHOOK_URL="${SHUFFLE_WEBHOOK_URL:-}"
ATTACKER_IP="${ATTACKER_IP:-198.51.100.42}"   # TEST-NET-3, RFC 5737 — safe fake IP
AGENT_NAME="${AGENT_NAME:-macbook-pro}"

YLW='\033[1;33m'
RED='\033[0;31m'
GRN='\033[0;32m'
NC='\033[0m'

if [[ -z "$WEBHOOK_URL" ]]; then
  echo -e "${RED}Error: set SHUFFLE_WEBHOOK_URL before running${NC}"
  echo "  export SHUFFLE_WEBHOOK_URL=https://<your-shuffle>/api/v1/hooks/<hook-id>"
  exit 1
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

PAYLOAD=$(cat <<EOF
{
  "id": "lab3-test-$(date +%s)",
  "timestamp": "${TIMESTAMP}",
  "rule": {
    "id": "5712",
    "level": 10,
    "description": "SSHD brute force trying to get access to the system. Non-existent user.",
    "groups": ["authentication_failed", "ssh", "brute_force"]
  },
  "agent": {
    "id": "003",
    "name": "${AGENT_NAME}"
  },
  "data": {
    "srcip": "${ATTACKER_IP}",
    "dstuser": "admin"
  },
  "full_log": "sshd[1234]: Failed password for invalid user admin from ${ATTACKER_IP} port 54321 ssh2"
}
EOF
)

echo -e "${YLW}[lab3] Firing test alert to Shuffle webhook${NC}"
echo -e "  Webhook : ${WEBHOOK_URL}"
echo -e "  Payload : rule 5712, attacker IP ${ATTACKER_IP}, agent ${AGENT_NAME}"
echo ""

response=$(curl -s -w "\n%{http_code}" -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | head -1)

if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
  echo -e "${GRN}[lab3] Webhook accepted (HTTP ${http_code})${NC}"
  echo -e "  Check Shuffle → your workflow should have a new execution"
  echo -e "  Check TheHive → a new case should appear within ~30 seconds"
else
  echo -e "${RED}[lab3] Webhook failed (HTTP ${http_code})${NC}"
  echo -e "  Response: ${body}"
  echo -e "  Check your SHUFFLE_WEBHOOK_URL and that the workflow is enabled"
fi
