#!/usr/bin/env bash
# Fortark SOC Lab — first-time setup (macOS / Linux)
# Usage: bash setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
fail() { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

echo ""
echo "  ███████╗ ██████╗ ██████╗    ██╗      █████╗ ██████╗"
echo "  ██╔════╝██╔═══██╗██╔════╝   ██║     ██╔══██╗██╔══██╗"
echo "  █████╗  ██║   ██║██████╗    ██║     ███████║██████╔╝"
echo "  ██╔══╝  ██║   ██║██╔══██╗   ██║     ██╔══██║██╔══██╗"
echo "  ██║     ╚██████╔╝██║  ██║   ███████╗██║  ██║██████╔╝"
echo "  ╚═╝      ╚═════╝ ╚═╝  ╚═╝   ╚══════╝╚═╝  ╚═╝╚═════╝"
echo ""
echo "  SOC Lab — Student Setup Script"
echo ""

# ── Prerequisites check ────────────────────────────────────────────────────

info "Checking prerequisites..."

command -v docker  >/dev/null 2>&1 || fail "Docker not found. Install Docker Desktop from https://www.docker.com/products/docker-desktop/"
command -v python3 >/dev/null 2>&1 || fail "python3 not found."
command -v openssl >/dev/null 2>&1 || fail "openssl not found."

DOCKER_RUNNING=false
docker info >/dev/null 2>&1 && DOCKER_RUNNING=true
$DOCKER_RUNNING || fail "Docker daemon not running. Start Docker Desktop and retry."
ok "Docker running"

COMPOSE_CMD=""
docker compose version >/dev/null 2>&1 && COMPOSE_CMD="docker compose"
[[ -n "$COMPOSE_CMD" ]] || fail "Docker Compose v2 not found. Update Docker Desktop."
ok "Docker Compose v2 found"

TOTAL_RAM_GB=0
if [[ "$(uname)" == "Darwin" ]]; then
    TOTAL_RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
    PLATFORM="macos"
else
    TOTAL_RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
    PLATFORM="linux"
fi

if (( TOTAL_RAM_GB < 14 )); then
    warn "This machine has ${TOTAL_RAM_GB} GB RAM. Minimum recommended is 16 GB."
    warn "You may experience OOM crashes. Proceed anyway? (y/N)"
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
else
    ok "RAM: ${TOTAL_RAM_GB} GB"
fi
ok "Platform: $PLATFORM"

# ── Linux: vm.max_map_count ────────────────────────────────────────────────

if [[ "$PLATFORM" == "linux" ]]; then
    info "Setting vm.max_map_count (OpenSearch requirement)..."
    sudo sysctl -w vm.max_map_count=262144
    grep -q "vm.max_map_count" /etc/sysctl.conf 2>/dev/null || \
        echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf >/dev/null
    ok "vm.max_map_count=262144"
fi

# ── .env setup ─────────────────────────────────────────────────────────────

if [[ ! -f .env ]]; then
    info "Creating .env from template..."
    cp .env.example .env

    gen32() { openssl rand -hex 32; }
    gen_pw()  { openssl rand -base64 18 | tr -dc 'A-Za-z0-9!@#$%' | head -c 16; echo; }

    # OpenSearch password must meet complexity requirements
    OS_PASS="SocLab!$(openssl rand -hex 6 | tr '[:lower:]' '[:upper:]')1"
    WAZUH_PASS="Wazuh!$(openssl rand -hex 6)"
    TH_SECRET=$(gen32)
    CX_SECRET=$(gen32)
    SH_KEY=$(gen32)

    sed -i.bak \
        -e "s|OPENSEARCH_ADMIN_PASSWORD=GENERATED|OPENSEARCH_ADMIN_PASSWORD=${OS_PASS}|" \
        -e "s|WAZUH_API_PASSWORD=GENERATED|WAZUH_API_PASSWORD=${WAZUH_PASS}|" \
        -e "s|THEHIVE_SECRET=GENERATED|THEHIVE_SECRET=${TH_SECRET}|" \
        -e "s|CORTEX_SECRET=GENERATED|CORTEX_SECRET=${CX_SECRET}|" \
        -e "s|SHUFFLE_ENCRYPTION_KEY=GENERATED|SHUFFLE_ENCRYPTION_KEY=${SH_KEY}|" \
        .env
    rm -f .env.bak

    # Set CORTEX_JOBS_PATH to an absolute path on this machine
    JOBS_PATH="${SCRIPT_DIR}/platform/cortex/jobs"
    sed -i.bak "s|CORTEX_JOBS_PATH=.*|CORTEX_JOBS_PATH=${JOBS_PATH}|" .env
    rm -f .env.bak

    ok ".env created with generated secrets"
else
    ok ".env already exists — skipping secret generation"
fi

source .env

# ── Cortex jobs directory ──────────────────────────────────────────────────

info "Creating Cortex jobs directory..."
mkdir -p "${CORTEX_JOBS_PATH}"
chmod 777 "${CORTEX_JOBS_PATH}"
ok "Cortex jobs: ${CORTEX_JOBS_PATH}"

# ── OpenSearch self-signed certs ───────────────────────────────────────────

CERT_DIR="./platform/opensearch/certs"
if [[ ! -f "${CERT_DIR}/node.pem" ]]; then
    info "Generating OpenSearch TLS certificates..."
    mkdir -p "$CERT_DIR"
    # Root CA
    openssl genrsa -out "${CERT_DIR}/root-ca-key.pem" 2048 2>/dev/null
    openssl req -new -x509 -sha256 -key "${CERT_DIR}/root-ca-key.pem" \
        -subj "/CN=SOC-Root-CA/O=FortarkSOCLab" \
        -out "${CERT_DIR}/root-ca.pem" -days 3650 2>/dev/null
    # Node cert
    openssl genrsa -out "${CERT_DIR}/node-key.pem" 2048 2>/dev/null
    openssl req -new -key "${CERT_DIR}/node-key.pem" \
        -subj "/CN=opensearch/O=FortarkSOCLab" \
        -out "${CERT_DIR}/node.csr" 2>/dev/null
    openssl x509 -req -in "${CERT_DIR}/node.csr" \
        -CA "${CERT_DIR}/root-ca.pem" -CAkey "${CERT_DIR}/root-ca-key.pem" \
        -CAcreateserial -sha256 -out "${CERT_DIR}/node.pem" -days 3650 2>/dev/null
    rm -f "${CERT_DIR}/node.csr"
    ok "TLS certificates generated"
else
    ok "TLS certificates already exist"
fi

# ── Wazuh Dashboard certs ─────────────────────────────────────────────────

DASH_CERT_DIR="./platform/wazuh-dashboard/certs"
if [[ ! -f "${DASH_CERT_DIR}/dashboard.pem" ]]; then
    info "Generating Wazuh Dashboard TLS certificates..."
    mkdir -p "$DASH_CERT_DIR"
    openssl genrsa -out "${DASH_CERT_DIR}/dashboard-key.pem" 2048 2>/dev/null
    openssl req -new -key "${DASH_CERT_DIR}/dashboard-key.pem" \
        -subj "/CN=wazuh-dashboard/O=FortarkSOCLab" \
        -out "${DASH_CERT_DIR}/dashboard.csr" 2>/dev/null
    openssl x509 -req -in "${DASH_CERT_DIR}/dashboard.csr" \
        -CA "${CERT_DIR}/root-ca.pem" -CAkey "${CERT_DIR}/root-ca-key.pem" \
        -CAcreateserial -sha256 -out "${DASH_CERT_DIR}/dashboard.pem" -days 3650 2>/dev/null
    cp "${CERT_DIR}/root-ca.pem" "${DASH_CERT_DIR}/root-ca.pem"
    rm -f "${DASH_CERT_DIR}/dashboard.csr"
    ok "Dashboard certs generated"
else
    ok "Dashboard certs already exist"
fi

# ── Pull images ────────────────────────────────────────────────────────────

info "Pulling Docker images (this may take 5–15 minutes on first run)..."
COMPOSE_FILES="-f docker-compose.yml"
[[ "$PLATFORM" == "macos" ]] && COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.mac.yml"
$COMPOSE_CMD $COMPOSE_FILES pull
ok "Images pulled"

# ── Start stack ────────────────────────────────────────────────────────────

info "Starting SOC lab stack..."
$COMPOSE_CMD $COMPOSE_FILES up -d
ok "Stack started"

echo ""
echo "  ─────────────────────────────────────────────────────────"
echo "  Stack is starting. Services take 3–5 minutes to be ready."
echo ""
echo "  Access:"
echo "    Wazuh Dashboard    → http://localhost:5601   (admin / ${OPENSEARCH_ADMIN_PASSWORD})"
echo "    TheHive            → http://localhost:9000   (admin@thehive.local / secret)"
echo "    Cortex             → http://localhost:9001"
echo "    Shuffle SOAR       → http://localhost:3001   (${SHUFFLE_DEFAULT_USERNAME} / ${SHUFFLE_DEFAULT_PASSWORD})"
echo "    Kali Desktop       → http://localhost:7681   (kasm_user / ${KALI_VNC_PASSWORD})"
echo "    SOC Tools          → http://localhost:8000"
echo ""
echo "  Next steps:"
echo "    1. Wait ~5 min, then open the URLs above"
echo "    2. Run: bash platform/scripts/post-start.sh"
echo "       (creates TheHive org, API keys, enrolls Wazuh agent)"
echo "    3. Add your API keys to .env (AbuseIPDB, VirusTotal, Shodan)"
echo "       then run: bash platform/scripts/configure-cortex-analyzers.sh"
echo "  ─────────────────────────────────────────────────────────"
echo ""
