#!/bin/bash
set -uo pipefail
NODES="${WAYDROID_CONFIG_NODES:-/var/lib/waydroid/lxc/waydroid/config_nodes}"
LXCPY="${WAYDROID_LXC_PY:-/usr/lib/waydroid/tools/helpers/lxc.py}"
[ -f "$NODES" ] || exit 1
grep -q "dev/bus/usb" "$NODES" 2>/dev/null || exit 1
# Both halves: the generator must keep it too, or it is gone on regeneration.
[ -f "$LXCPY" ] && ! grep -q "dev/bus/usb" "$LXCPY" && exit 1
echo "USB tree bound into the waydroid container"
