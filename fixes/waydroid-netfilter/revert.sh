#!/bin/bash
set -euo pipefail

# Escalation is chosen by the caller: plain sudo in a terminal, pkexec
# under the GUI, which has no tty to prompt on.
SUDO="${FIXER_SUDO:-sudo}"
FIXER_REPO="${FIXER_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SCRIPT="${WAYDROID_NET_SCRIPT:-/usr/lib/waydroid/data/scripts/waydroid-net.sh}"
BACKUP="$SCRIPT.chromebook-fixer.orig"
grep -q "chromebook-fixer" "$SCRIPT" || { echo "$SCRIPT is not patched; nothing to revert"; exit 0; }
[ -f "$BACKUP" ] || { echo "no backup found at $BACKUP"; exit 1; }
# orig_restore refuses a backup taken from a different waydroid version.
$SUDO env FIXER_DPKG_INFO="${FIXER_DPKG_INFO:-}" bash -s -- "$SCRIPT" "$FIXER_REPO/lib/orig-backup.sh" <<'ROOT'
set -u
[ -n "${FIXER_DPKG_INFO:-}" ] || unset FIXER_DPKG_INFO
. "$2"
orig_restore "$1"
ROOT
