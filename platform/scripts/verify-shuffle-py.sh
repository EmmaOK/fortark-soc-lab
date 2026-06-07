#!/usr/bin/env bash
# verify-shuffle-py.sh — Check that Wazuh's shuffle.py is our custom script,
# not the bundled Shuffle version. Run after any wazuh-manager restart.

set -euo pipefail

HEADER=$(docker exec soc-wazuh-manager head -3 /var/ossec/integrations/shuffle.py 2>/dev/null || echo "ERROR")

if echo "$HEADER" | grep -q "Wazuh integration: brute force"; then
    echo "[✓] shuffle.py is correct (our custom script)"
elif echo "$HEADER" | grep -qi "Created by Shuffle"; then
    echo "[✗] shuffle.py was OVERWRITTEN by Wazuh startup!"
    echo "    Re-deploying..."
    # The bind mount picks up the host file — no copy needed, just verify mount
    docker exec soc-wazuh-manager cat /var/ossec/integrations/shuffle.py | head -1
    echo ""
    echo "    If still wrong, restart the container:"
    echo "    docker compose restart wazuh-manager"
else
    echo "[?] Unknown shuffle.py content:"
    echo "$HEADER"
fi
