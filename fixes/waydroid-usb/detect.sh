#!/bin/bash
set -uo pipefail
FIXER_REPO="${FIXER_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
NODES="${WAYDROID_CONFIG_NODES:-/var/lib/waydroid/lxc/waydroid/config_nodes}"
LXCPY="${WAYDROID_LXC_PY:-/usr/lib/waydroid/tools/helpers/lxc.py}"
. "$FIXER_REPO/lib/orig-backup.sh"
[ -f "$NODES" ] || exit 1                     # waydroid not initialised

if ! grep -q "dev/bus/usb" "$NODES" 2>/dev/null; then
    if orig_replaced "$NODES"; then
        echo "waydroid regenerated its container config and dropped USB passthrough; apply again"
    else
        echo "waydroid container has no USB passthrough configured"
    fi
    exit 0
fi
# The live config has it, but a waydroid upgrade may have replaced the
# generator: USB passthrough then disappears the next time the config is
# regenerated.
if [ -f "$LXCPY" ] && ! grep -q "dev/bus/usb" "$LXCPY" && [ -f "$LXCPY.chromebook-fixer.orig" ]; then
    echo "a waydroid update replaced the patched lxc.py; apply again, or USB passthrough goes the next time waydroid regenerates its config"
    exit 0
fi
exit 1
