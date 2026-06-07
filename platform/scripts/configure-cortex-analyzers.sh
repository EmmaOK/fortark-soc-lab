#!/usr/bin/env bash
# configure-cortex-analyzers.sh — Enables and configures Cortex analysers
# Requires: CORTEX_THEHIVE_API_KEY set in .env, Cortex running on localhost:9001

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

[[ -f .env ]] || { echo "ERROR: .env not found."; exit 1; }
source .env

ok()   { echo "[✓] $*"; }
info() { echo "[*] $*"; }
warn() { echo "[!] $*"; }

[[ -n "${CORTEX_THEHIVE_API_KEY:-}" ]] || { echo "ERROR: CORTEX_THEHIVE_API_KEY not set in .env"; exit 1; }

CX_URL="http://localhost:9001"
AUTH="Authorization: Bearer ${CORTEX_THEHIVE_API_KEY}"

info "Listing available analysers..."
ANALYSERS=$(curl -s -H "$AUTH" "${CX_URL}/api/analyzer" 2>/dev/null || echo "[]")
echo "$ANALYSERS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for a in data[:20]:
        print(f\"  {a.get('id','?')} — {a.get('name','?')}\")
except:
    print('  (could not list analysers — check API key and Cortex health)')
"

configure_analyzer() {
    local ID="$1"
    local CONFIG="$2"
    local RESP
    RESP=$(curl -s -X POST -H "$AUTH" -H "Content-Type: application/json" \
        "${CX_URL}/api/analyzer/${ID}/enable" \
        -d "$CONFIG" 2>/dev/null || echo "")
    if echo "$RESP" | grep -q '"_id"'; then
        ok "Enabled: $ID"
    else
        warn "Could not enable $ID (may not be installed yet)"
    fi
}

echo ""
info "Configuring analysers with API keys from .env..."

if [[ -n "${ABUSEIPDB_API_KEY:-}" ]]; then
    configure_analyzer "AbuseIPDB_2_0" "{\"key\":\"${ABUSEIPDB_API_KEY}\",\"days\":\"30\"}"
else
    warn "ABUSEIPDB_API_KEY not set — skipping AbuseIPDB"
fi

if [[ -n "${VIRUSTOTAL_API_KEY:-}" ]]; then
    configure_analyzer "VirusTotal_GetReport_3_1" "{\"key\":\"${VIRUSTOTAL_API_KEY}\"}"
else
    warn "VIRUSTOTAL_API_KEY not set — skipping VirusTotal"
fi

if [[ -n "${SHODAN_API_KEY:-}" ]]; then
    configure_analyzer "Shodan_Host_1_0" "{\"key\":\"${SHODAN_API_KEY}\"}"
else
    warn "SHODAN_API_KEY not set — skipping Shodan"
fi

echo ""
ok "Done. Refresh Cortex → Analyzers to verify."
echo "  To add API keys: edit .env → re-run this script"
