#!/usr/bin/env bash
# Lab 1 — SSH Brute Force Simulation
# Simulates a brute force attack by making rapid failed SSH login attempts
# followed by one successful login (using valid credentials).
#
# Safe: uses SSH to a target you control (default: Mac Mini at 192.168.6.213).
# Wazuh on the target machine picks up the auth failures from sshd logs.
#
# Requirements: ssh available on PATH, target machine has SSH enabled.

set -euo pipefail

TARGET_HOST="${TARGET_HOST:-192.168.6.213}"
TARGET_USER="${TARGET_USER:-emmanuelokonkwo}"
ATTACK_USER="${ATTACK_USER:-admin}"       # username attacker tries
ATTEMPT_COUNT="${ATTEMPT_COUNT:-20}"      # number of failed attempts
DELAY="${DELAY:-0.3}"                     # seconds between attempts

GRN='\033[0;32m'
YLW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YLW}[lab1] SSH brute force simulation${NC}"
echo -e "  Target      : ${TARGET_USER}@${TARGET_HOST}"
echo -e "  Attack user : ${ATTACK_USER}"
echo -e "  Attempts    : ${ATTEMPT_COUNT} failed + 1 successful"
echo ""

# Stage 1: Failed attempts with wrong passwords
echo -e "${RED}[lab1] Stage 1: Sending ${ATTEMPT_COUNT} failed auth attempts...${NC}"
failed=0
for i in $(seq 1 $ATTEMPT_COUNT); do
  ssh -o StrictHostKeyChecking=no \
      -o ConnectTimeout=3 \
      -o PasswordAuthentication=yes \
      -o BatchMode=no \
      -o PubkeyAuthentication=no \
      "${ATTACK_USER}@${TARGET_HOST}" exit 2>/dev/null || true
  failed=$((failed + 1))
  printf "  attempt %02d/%d\r" "$failed" "$ATTEMPT_COUNT"
  sleep "$DELAY"
done
echo ""
echo -e "${RED}[lab1] ${ATTEMPT_COUNT} failed attempts sent${NC}"
sleep 1

# Stage 2: Successful login (using real credentials)
echo -e "${YLW}[lab1] Stage 2: Simulating successful login...${NC}"
ssh -o StrictHostKeyChecking=no \
    -o ConnectTimeout=5 \
    "${TARGET_USER}@${TARGET_HOST}" \
    "echo '[lab1-sim] Successful login at \$(date -u)' >> /tmp/lab1-login.log && whoami && uptime" 2>&1 || {
  echo -e "${YLW}  (SSH key auth not set up — successful login stage skipped)${NC}"
}

echo ""
echo -e "${RED}[lab1] Simulation complete:${NC}"
echo -e "  Failed attempts  : ${ATTEMPT_COUNT} (rule 5712 in Wazuh)"
echo -e "  Successful login : 1 (rule 5715 in Wazuh)"
echo ""
echo -e "${YLW}Go to sec.fortark.com and find the brute force alerts.${NC}"
echo -e "${YLW}Tip: filter by rule.id:5712 in Threat Hunting → Events${NC}"
