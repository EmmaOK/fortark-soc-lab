# Fortark SOC Lab

A self-contained Security Operations Centre lab you can run locally on your own machine.  
Fork → clone → run `setup.sh` → open your browser.

---

## System Requirements

| | Minimum | Recommended |
|---|---|---|
| RAM | 16 GB | 20 GB |
| CPU | 4 cores | 8 cores |
| Disk | 40 GB free | 60 GB free |
| OS | macOS 13+, Windows 11 (WSL2), Ubuntu 22.04+ | macOS 14+ |

---

## Quick Start

### macOS / Linux

```bash
git clone https://github.com/YOUR_ORG/fortark-soc-lab.git
cd fortark-soc-lab
bash setup.sh
```

### Windows

Open PowerShell as Administrator:

```powershell
git clone https://github.com/YOUR_ORG/fortark-soc-lab.git
cd fortark-soc-lab
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\setup.ps1
```

> **WSL2 is required on Windows.** Install from Microsoft Store or run `wsl --install` in an admin terminal.

---

## Services

| Service | URL | Default credentials |
|---|---|---|
| Wazuh Dashboard | http://localhost:5601 | admin / *(see .env)* |
| TheHive | http://localhost:9000 | admin@thehive.local / secret |
| Cortex | http://localhost:9001 | *(create on first visit)* |
| Shuffle SOAR | http://localhost:3001 | admin / ChangeMe!Shuffle1 |
| Kali Desktop | http://localhost:7681 | kasm_user / *(see .env)* |
| SOC Tools | http://localhost:8000 | *(no login)* |

---

## First-Run Checklist

1. **Wait ~5 minutes** after `setup.sh` completes — OpenSearch and Cassandra take time to initialise.
2. **Complete TheHive setup** → Create the `SOC` organisation and an `analyst` user. Generate an API key and add it to `.env` as `THEHIVE_API_KEY`.
3. **Complete Cortex setup** → Create admin on first visit. Create `SOC` org + `thehive` user. Generate API key → add to `.env` as `CORTEX_THEHIVE_API_KEY`. Restart TheHive: `docker compose restart thehive`.
4. **Add your external API keys** to `.env` (see *External API Keys* below).
5. **Enable Cortex analysers**: `bash platform/scripts/configure-cortex-analyzers.sh`
6. **Enroll the Wazuh agent**: `bash platform/scripts/enroll-wazuh-agent.sh`

---

## External API Keys (self-service — free accounts)

Add these to `.env` before step 5:

| Key | Where to get it |
|---|---|
| `ABUSEIPDB_API_KEY` | https://www.abuseipdb.com/account/api |
| `VIRUSTOTAL_API_KEY` | https://www.virustotal.com/gui/my-apikey |
| `SHODAN_API_KEY` | https://account.shodan.io/ |

---

## Lab Guides

Open the HTML files directly in your browser — no server needed:

| Lab | File |
|---|---|
| Module 0: Attacker Mindset | `labs/guides/module0-attacker-mindset.html` |
| Module 1: Logs, Events, Alerts | `labs/guides/module1-logs-events-alerts.html` |
| Module 2: SOC Role | `labs/guides/module2-soc-role.html` |
| Lab 1: Brute Force Detection | `labs/guides/lab1-brute-force.html` |
| Lab 2: Investigation | `labs/guides/lab2-investigation.html` |
| Lab 3: SOAR Automation | `labs/guides/lab3-soar.html` |
| Lab 4: Ransomware Response | `labs/guides/lab4-ransomware.html` |
| Lab 5: Supply Chain Attack | `labs/guides/lab5-supply-chain.html` |
| Lab 6: C2 Beaconing | `labs/guides/lab6-c2-beaconing.html` |
| Lab 7: LLM Key Exfiltration | `labs/guides/lab7-llm-key-exfil.html` |

---

## Compose Commands

```bash
# macOS — start
docker compose -f docker-compose.yml -f docker-compose.mac.yml up -d

# macOS — stop
docker compose -f docker-compose.yml -f docker-compose.mac.yml down

# Windows — start (in WSL2)
docker compose -f docker-compose.yml -f docker-compose.win.yml up -d

# Linux — start
docker compose up -d

# View logs
docker compose logs -f wazuh-manager
docker compose logs -f thehive
```

---

## Troubleshooting

**OpenSearch won't start / crashes immediately**  
→ Linux only: run `sudo sysctl -w vm.max_map_count=262144`  
→ Windows: add `kernelCommandLine = sysctl.vm.max_map_count=262144` to `~/.wslconfig` and restart WSL2

**Wazuh dashboard shows "no index pattern"**  
→ Wait 3–5 minutes for Wazuh to create its indices, then refresh.

**TheHive shows "Cortex unreachable"**  
→ Check `CORTEX_THEHIVE_API_KEY` in `.env`. Restart after updating: `docker compose restart thehive`

**Brute force doesn't trigger rule 40112**  
→ The wordlist must have failures before the success. Use the provided `labs/scripts/lab1-brute-force-sim.sh` — it puts `password123` near the end.

**Shuffle.py overwritten after wazuh-manager restart**  
→ Run `bash platform/scripts/verify-shuffle-py.sh` to check and recover.

**Suricata not working on macOS / Windows**  
→ Expected. macOS uses pcap mode (bridge only). Windows disables Suricata entirely. Wazuh (SSH auth detection) still works on both.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  soc-internal (172.20.0.0/24)    │
│                                                  │
│  lab-target ──► wazuh-manager ──► opensearch     │
│                      │                           │
│                  shuffle.py                      │
│                      │                           │
│                   thehive ◄──► cortex            │
│                                                  │
│  kali ──────────────────────────────►            │
│  (SSH brute force via internal hostname)         │
└─────────────────────────────────────────────────┘
```

The Wazuh → TheHive integration runs **directly** via `shuffle.py` (no Shuffle workers).  
Rule 40112 = brute force followed by successful login from the same IP within 240 seconds.

---

## Resetting the Lab

```bash
# Wipe all data and start fresh (keeps images)
docker compose down -v
bash setup.sh
```
