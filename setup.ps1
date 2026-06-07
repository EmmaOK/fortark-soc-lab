# Fortark SOC Lab — first-time setup (Windows / WSL2)
# Run in PowerShell as Administrator:
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#   .\setup.ps1

param()
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

function ok   { Write-Host "[✓] $args" -ForegroundColor Green }
function info { Write-Host "[*] $args" -ForegroundColor Cyan }
function warn { Write-Host "[!] $args" -ForegroundColor Yellow }
function fail { Write-Host "[✗] $args" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "  Fortark SOC Lab — Windows Setup" -ForegroundColor Cyan
Write-Host ""

# ── Prerequisites ─────────────────────────────────────────────────────────

info "Checking prerequisites..."

try { $null = docker info 2>&1; ok "Docker running" }
catch { fail "Docker not running. Start Docker Desktop and retry." }

try { $null = docker compose version 2>&1; ok "Docker Compose v2 found" }
catch { fail "Docker Compose v2 not found. Update Docker Desktop." }

$ram = [math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB)
if ($ram -lt 14) {
    warn "RAM: ${ram} GB — minimum recommended is 16 GB"
    $ans = Read-Host "Continue anyway? (y/N)"
    if ($ans -ne "y") { exit 1 }
} else { ok "RAM: ${ram} GB" }

# ── WSL2 vm.max_map_count ─────────────────────────────────────────────────

info "Setting vm.max_map_count in WSL2 (OpenSearch requirement)..."
$wslConf = "$env:USERPROFILE\.wslconfig"
$mapEntry = "[wsl2]`nkernelCommandLine = sysctl.vm.max_map_count=262144"
if (-not (Test-Path $wslConf) -or -not (Select-String -Path $wslConf -Pattern "max_map_count" -Quiet)) {
    Add-Content -Path $wslConf -Value "`n$mapEntry"
    warn "Added vm.max_map_count to $wslConf — WSL2 will pick it up on next restart"
} else {
    ok "vm.max_map_count already configured in .wslconfig"
}

# ── .env setup ─────────────────────────────────────────────────────────────

if (-not (Test-Path ".env")) {
    info "Creating .env from template..."
    Copy-Item ".env.example" ".env"

    function GenHex([int]$bytes = 32) {
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $buf = New-Object byte[] $bytes
        $rng.GetBytes($buf)
        return [System.BitConverter]::ToString($buf).Replace("-","").ToLower()
    }

    $osPass   = "SocLab!" + ((GenHex 4).ToUpper()) + "1"
    $wazuhPw  = "Wazuh!" + (GenHex 6)
    $thSecret = GenHex 32
    $cxSecret = GenHex 32
    $shKey    = GenHex 32

    # WSL2 path for Cortex jobs (must be accessible from Docker)
    $jobsPath = $ScriptDir.Replace("\", "/").Replace("C:", "/c") + "/platform/cortex/jobs"

    $env = Get-Content ".env"
    $env = $env -replace "OPENSEARCH_ADMIN_PASSWORD=GENERATED", "OPENSEARCH_ADMIN_PASSWORD=$osPass"
    $env = $env -replace "WAZUH_API_PASSWORD=GENERATED",        "WAZUH_API_PASSWORD=$wazuhPw"
    $env = $env -replace "THEHIVE_SECRET=GENERATED",             "THEHIVE_SECRET=$thSecret"
    $env = $env -replace "CORTEX_SECRET=GENERATED",              "CORTEX_SECRET=$cxSecret"
    $env = $env -replace "SHUFFLE_ENCRYPTION_KEY=GENERATED",     "SHUFFLE_ENCRYPTION_KEY=$shKey"
    $env = $env -replace "CORTEX_JOBS_PATH=.*",                  "CORTEX_JOBS_PATH=$jobsPath"
    $env | Set-Content ".env"
    ok ".env created with generated secrets"
} else {
    ok ".env already exists — skipping secret generation"
}

# Source .env values
$envVars = @{}
Get-Content ".env" | Where-Object { $_ -match "^[A-Z]" -and $_ -notmatch "^#" } | ForEach-Object {
    $parts = $_ -split "=", 2
    $envVars[$parts[0]] = $parts[1]
}

# ── Cortex jobs directory ──────────────────────────────────────────────────

info "Creating Cortex jobs directory..."
$jobsWin = Join-Path $ScriptDir "platform\cortex\jobs"
New-Item -ItemType Directory -Force -Path $jobsWin | Out-Null
ok "Cortex jobs: $jobsWin"

# ── OpenSearch certs ───────────────────────────────────────────────────────

$certDir = ".\platform\opensearch\certs"
if (-not (Test-Path "$certDir\node.pem")) {
    info "Generating OpenSearch TLS certificates..."
    New-Item -ItemType Directory -Force -Path $certDir | Out-Null
    # Use openssl via WSL2 if available, else skip and warn
    try {
        wsl openssl genrsa -out "$certDir/root-ca-key.pem" 2048 2>$null
        wsl openssl req -new -x509 -sha256 -key "$certDir/root-ca-key.pem" -subj "/CN=SOC-Root-CA/O=FortarkSOCLab" -out "$certDir/root-ca.pem" -days 3650 2>$null
        wsl openssl genrsa -out "$certDir/node-key.pem" 2048 2>$null
        wsl openssl req -new -key "$certDir/node-key.pem" -subj "/CN=opensearch/O=FortarkSOCLab" -out "$certDir/node.csr" 2>$null
        wsl openssl x509 -req -in "$certDir/node.csr" -CA "$certDir/root-ca.pem" -CAkey "$certDir/root-ca-key.pem" -CAcreateserial -sha256 -out "$certDir/node.pem" -days 3650 2>$null
        Remove-Item "$certDir\node.csr" -ErrorAction SilentlyContinue
        ok "TLS certificates generated"
    } catch {
        warn "Could not generate certs via WSL2. Run setup.sh in WSL2 instead, or manually generate certs."
    }
} else {
    ok "TLS certificates already exist"
}

# ── Pull & start ───────────────────────────────────────────────────────────

info "Pulling Docker images (5-15 minutes on first run)..."
docker compose -f docker-compose.yml -f docker-compose.win.yml pull
ok "Images pulled"

info "Starting SOC lab stack..."
docker compose -f docker-compose.yml -f docker-compose.win.yml up -d
ok "Stack started"

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "  Stack is starting. Services take 3-5 minutes to be ready." -ForegroundColor Cyan
Write-Host ""
Write-Host "  Access:" -ForegroundColor White
Write-Host "    Wazuh Dashboard    -> http://localhost:5601"
Write-Host "    TheHive            -> http://localhost:9000"
Write-Host "    Cortex             -> http://localhost:9001"
Write-Host "    Shuffle SOAR       -> http://localhost:3001"
Write-Host "    Kali Desktop       -> http://localhost:7681"
Write-Host "    SOC Tools          -> http://localhost:8000"
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "    1. Wait ~5 min, then open the URLs above"
Write-Host "    2. In WSL2: bash platform/scripts/post-start.sh"
Write-Host "    3. Add API keys to .env, then: bash platform/scripts/configure-cortex-analyzers.sh"
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""
