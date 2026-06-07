#!/usr/bin/env python3
"""
Wazuh integration: brute force alert → TheHive alert (direct).

Wazuh calls this with three args: <alert-file> <api-key> <webhook-url>
We ignore args 2-3 (kept for Wazuh integration compatibility) and use
hard-coded constants to reach TheHive directly on soc-internal.

Fires only on rule 40112 (SSH brute force + successful login).
"""
import sys
import json
import urllib.request
import urllib.error
import syslog
import hashlib
import datetime

THEHIVE_URL = "http://soc-thehive:9000"
# Read from env (set THEHIVE_API_KEY in .env after TheHive first-run setup)
import os
THEHIVE_API_KEY = os.environ.get("THEHIVE_API_KEY", "")

TARGET_RULE = "40112"


def log(msg):
    syslog.syslog(syslog.LOG_INFO, f"shuffle-execute: {msg}")


def build_alert(alert):
    rule = alert.get("rule", {})
    agent = alert.get("agent", {})
    data = alert.get("data", {})
    ts = alert.get("timestamp", "")

    agent_name = agent.get("name", "unknown")
    src_ip = data.get("srcip", data.get("src_ip", "unknown"))
    dst_user = data.get("dstuser", data.get("user", "unknown"))
    rule_desc = rule.get("description", "SSH brute force and successful login")

    # Unique per agent+hour so re-runs in the same hour don't spam cases
    hour = ts[:13] if len(ts) >= 13 else datetime.datetime.utcnow().strftime("%Y-%m-%dT%H")
    ref_raw = f"{agent_name}-{src_ip}-{hour}"
    source_ref = "wazuh-" + hashlib.md5(ref_raw.encode()).hexdigest()[:10]

    description = (
        f"**Wazuh rule 40112 — SSH brute force succeeded**\n\n"
        f"| Field | Value |\n"
        f"|---|---|\n"
        f"| Agent | `{agent_name}` |\n"
        f"| Attacker IP | `{src_ip}` |\n"
        f"| Target user | `{dst_user}` |\n"
        f"| Rule | {rule.get('id', '?')} — {rule_desc} |\n"
        f"| Timestamp | `{ts}` |\n\n"
        f"Automated alert created by Wazuh SOAR integration."
    )

    return {
        "title": f"SSH Brute Force Success — {agent_name} from {src_ip}",
        "description": description,
        "type": "external",
        "source": "wazuh",
        "sourceRef": source_ref,
        "severity": 3,  # High
        "tags": [
            "brute-force",
            "ssh",
            f"agent:{agent_name}",
            f"src:{src_ip}",
            "rule:40112",
            "automated",
        ],
        "tlp": 2,
    }


def post_to_thehive(payload_dict):
    body = json.dumps(payload_dict).encode("utf-8")
    req = urllib.request.Request(
        f"{THEHIVE_URL}/api/v1/alert",
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {THEHIVE_API_KEY}",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.status, resp.read().decode("utf-8")


def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    try:
        with open(sys.argv[1], "r") as f:
            alert = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        log(f"failed to read alert file: {e}")
        sys.exit(1)

    rule_id = str(alert.get("rule", {}).get("id", ""))

    if rule_id != TARGET_RULE:
        sys.exit(0)

    payload = build_alert(alert)

    try:
        status, body = post_to_thehive(payload)
        if status in (200, 201):
            log(f"alert created in TheHive (HTTP {status}) ref={payload['sourceRef']}")
        else:
            log(f"TheHive returned HTTP {status}: {body[:200]}")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        if e.code == 400 and "already exist" in body.lower():
            log(f"duplicate alert ignored (sourceRef={payload['sourceRef']})")
        else:
            log(f"TheHive HTTP error {e.code}: {body[:200]}")
    except urllib.error.URLError as e:
        log(f"TheHive unreachable: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
