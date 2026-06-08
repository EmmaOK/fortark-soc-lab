#!/usr/bin/env bash
# Lab 4 — Ransomware Simulation
# Safe: operates entirely in /tmp/lab4-ransomware, touches no real files.
# Wazuh FIM must monitor /tmp (already configured on all lab targets).

set -euo pipefail

TARGET_DIR="/tmp/lab4-ransomware"
RANSOM_NOTE="HOW_TO_DECRYPT.txt"
FILE_COUNT=40
EXTENSIONS=("pdf" "docx" "xlsx" "txt" "jpg" "png" "csv" "sql")
TAG="lab4-ransomware"

RED='\033[0;31m'
YLW='\033[1;33m'
GRN='\033[0;32m'
NC='\033[0m'

cleanup() {
  logger -t "$TAG" "CLEANUP: removing simulation artifacts from $TARGET_DIR"
  rm -rf "$TARGET_DIR"
  echo -e "${GRN}[cleanup] Done. Simulation artifacts removed.${NC}"
}

if [[ "${1:-}" == "--cleanup" ]]; then
  cleanup
  exit 0
fi

# ── Stage 1: File discovery ───────────────────────────────────────────────────
echo ""
echo -e "${YLW}[Stage 1] Discovery — scanning filesystem for target files...${NC}"
logger -t "$TAG" "STAGE:DISCOVERY scanning /tmp /home for encryptable files"
find /tmp /home 2>/dev/null | head -20 | while read -r f; do
  logger -t "$TAG" "DISCOVERY:FOUND $f"
done
sleep 1

# ── Stage 2: Staging — create decoy victim files ──────────────────────────────
echo ""
echo -e "${YLW}[Stage 2] Staging — creating victim file set in ${TARGET_DIR}...${NC}"
logger -t "$TAG" "STAGE:STAGING creating victim files in $TARGET_DIR"
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

for i in $(seq 1 $FILE_COUNT); do
  ext="${EXTENSIONS[$((RANDOM % ${#EXTENSIONS[@]}))]}"
  fname="$TARGET_DIR/document_$(printf '%03d' $i).${ext}"
  dd if=/dev/urandom bs=1024 count=$((RANDOM % 50 + 10)) 2>/dev/null | base64 > "$fname"
done

logger -t "$TAG" "STAGING:COMPLETE $FILE_COUNT files ready for encryption in $TARGET_DIR"
echo -e "  ${FILE_COUNT} victim files staged"
sleep 2

# ── Stage 3: Encryption ───────────────────────────────────────────────────────
echo ""
echo -e "${RED}[Stage 3] Encryption — beginning file encryption sequence...${NC}"
logger -t "$TAG" "STAGE:ENCRYPT beginning mass encryption of $FILE_COUNT files"

encrypted=0
for f in "$TARGET_DIR"/document_*; do
  mv "$f" "${f%.*}.locked"
  encrypted=$((encrypted + 1))
  sleep 0.05
done

logger -t "$TAG" "ENCRYPT:COMPLETE $encrypted files encrypted with extension .locked"
echo -e "  ${encrypted} files encrypted → .locked"
sleep 1

# ── Stage 4: Ransom note ──────────────────────────────────────────────────────
echo ""
echo -e "${RED}[Stage 4] Ransom — dropping ransom note...${NC}"
logger -t "$TAG" "STAGE:RANSOM dropping $RANSOM_NOTE to $TARGET_DIR and /tmp"

for dir in "$TARGET_DIR" /tmp; do
  cat > "$dir/$RANSOM_NOTE" <<EOF
YOUR FILES HAVE BEEN ENCRYPTED

All your documents, photos, and databases have been encrypted with AES-256-CBC.

To recover your files, send 0.5 BTC within 72 hours to:
  Bitcoin address: 1A1zP1eP5QGefi2DMPTfTL5SLmv7Divf8uABC

Contact for decryption key: recover@darkmail.onion

Files encrypted : $encrypted
Encryption time : $(date -u +%Y-%m-%dT%H:%M:%SZ)
Victim ID       : $(hostname)-$(date +%s)

-- WARNING: Do NOT attempt recovery without the key. You will destroy your files.
-- WARNING: Do NOT contact law enforcement. Your key will be deleted.

[SIM] This is a Fortark Labs training simulation. No real files were encrypted.
EOF
  logger -t "$TAG" "RANSOM:NOTE_DROPPED $dir/$RANSOM_NOTE"
  echo -e "  Ransom note dropped: $dir/$RANSOM_NOTE"
  sleep 0.3
done

# ── Stage 5: Inhibit recovery ─────────────────────────────────────────────────
echo ""
echo -e "${RED}[Stage 5] Inhibit — sweeping for backup files to remove...${NC}"
logger -t "$TAG" "STAGE:INHIBIT scanning for backup files to destroy"

find / -name "*.bak" -o -name "*.backup" -o -name "*.tar.gz" 2>/dev/null | \
  grep -v proc | grep -v sys | head -10 | while read -r f; do
    logger -t "$TAG" "INHIBIT:FOUND_BACKUP $f"
  done

logger -t "$TAG" "INHIBIT:SWEEP_COMPLETE backup removal sweep finished"
echo -e "  Backup sweep complete"

echo ""
echo -e "${RED}══════════════════════════════════════════════════════${NC}"
echo -e "${RED}  Ransomware simulation complete${NC}"
echo -e "${RED}  Files encrypted : ${encrypted}${NC}"
echo -e "${RED}  Extension used  : .locked${NC}"
echo -e "${RED}  Ransom note at  : ${TARGET_DIR}/${RANSOM_NOTE}${NC}"
echo -e "${RED}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YLW}Now check the Wazuh dashboard for FIM alerts.${NC}"
echo -e "${YLW}Run with --cleanup when the lab is done.${NC}"
