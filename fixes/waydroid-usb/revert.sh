#!/bin/bash
set -uo pipefail

# Escalation is chosen by the caller: plain sudo in a terminal, pkexec
# under the GUI, which has no tty to prompt on.
SUDO="${FIXER_SUDO:-sudo}"
FIXER_REPO="${FIXER_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
NODES="${WAYDROID_CONFIG_NODES:-/var/lib/waydroid/lxc/waydroid/config_nodes}"
LXCPY="${WAYDROID_LXC_PY:-/usr/lib/waydroid/tools/helpers/lxc.py}"

# One root step. orig_restore refuses a backup taken from a different
# waydroid version than the one installed (lib/orig-backup.sh).
$SUDO env FIXER_DPKG_INFO="${FIXER_DPKG_INFO:-}" bash -s -- "$FIXER_REPO/lib/orig-backup.sh" "$NODES" "$LXCPY" <<'ROOT'
set -u
[ -n "${FIXER_DPKG_INFO:-}" ] || unset FIXER_DPKG_INFO
. "$1"; shift
rc=0
for f in "$@"; do
    [ -f "$f" ] || continue
    grep -q "dev/bus/usb" "$f" || continue      # not patched: nothing to undo
    orig_restore "$f"; r=$?
    [ "$r" = 1 ] && rc=1
done
exit "$rc"
ROOT
