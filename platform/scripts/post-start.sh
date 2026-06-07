#!/usr/bin/env bash
# post-start.sh — Run once after the stack is healthy (~5 min after setup.sh)
# Creates TheHive org/users, generates API keys, enrolls the Wazuh agent

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

[[ -f .env ]] || { echo "ERROR: .env not found. Run setup.sh first."; exit 1; }
source .env

ok()   { echo "[✓] $*"; }
info() { echo "[*] $*"; }
fail() { echo "[✗] $*" >&2; exit 1; }

# ── Wait for services ─────────────────────────────────────────────────────

info "Waiting for TheHive to be ready..."
for i in $(seq 1 30); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9000/api/v1/status 2>/dev/null || echo "000")
    if [[ "$CODE" =~ ^(200|401)$ ]]; then
        ok "TheHive is up (HTTP $CODE)"
        break
    fi
    echo "  ... waiting ($i/30)"
    sleep 10
done

info "Waiting for Wazuh manager to be ready..."
for i in $(seq 1 20); do
    CODE=$(curl -sk -u "${WAZUH_API_USERNAME}:${WAZUH_API_PASSWORD}" \
        -X GET https://localhost:55000/security/user/authenticate \
        -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
    if [[ "$CODE" == "200" ]]; then
        ok "Wazuh API is up"
        break
    fi
    echo "  ... waiting ($i/20)"
    sleep 10
done

# ── TheHive: create SOC organisation ─────────────────────────────────────

info "Creating TheHive SOC organisation..."
ORG_RESP=$(curl -s -X POST http://localhost:9000/api/v1/organisation \
    -H "Authorization: Bearer $(get_admin_key)" \
    -H "Content-Type: application/json" \
    -d '{"name":"SOC","description":"SOC Lab Organisation"}' 2>/dev/null || echo "")

echo "  Response: $ORG_RESP"

echo ""
echo "  ── Manual steps required ──────────────────────────────────────────"
echo "  TheHive first-login setup needs to be done in the browser:"
echo ""
echo "  1. Open http://localhost:9000"
echo "  2. Login: admin@thehive.local / secret"
echo "  3. Go to: Admin → Organisations → Create 'SOC'"
echo "  4. Create user: analyst@soc.local (role: analyst) in SOC org"
echo "  5. Go to: User profile → API Keys → Create → copy it"
echo "  6. Paste the API key into .env as THEHIVE_API_KEY="
echo ""
echo "  ── Cortex first-login setup ────────────────────────────────────────"
echo "  1. Open http://localhost:9001"
echo "  2. Create admin account on first visit"
echo "  3. Admin → Organisations → Create 'SOC'"
echo "  4. Create user: thehive@cortex.local (role: read, analyze) in SOC org"
echo "  5. User profile → API Keys → Create → copy it"
echo "  6. Paste into .env as CORTEX_THEHIVE_API_KEY="
echo "  7. Re-run: docker compose restart thehive"
echo ""
echo "  ── After API keys are set: ──────────────────────────────────────────"
echo "  bash platform/scripts/configure-cortex-analyzers.sh"
echo "  bash platform/scripts/enroll-wazuh-agent.sh"
echo ""
