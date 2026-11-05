#!/bin/bash
set -uo pipefail

# Escalation is chosen by the caller: plain sudo in a terminal, pkexec
# under the GUI, which has no tty to prompt on.
SUDO="${FIXER_SUDO:-sudo}"
FIXER_REPO="${FIXER_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CONFIGS="${WAYDROID_LXC_CONFIGS:-/usr/lib/waydroid/data/configs/config_base /var/lib/waydroid/lxc/waydroid/config}"
# The cmdline snapshot apply.sh may have created: harmless to leave (nothing
# references it once the mount.entry line is gone), but tidy to remove since
# this fix reverts cleanly.
CMDLINE_SNAPSHOT="${WAYDROID_CMDLINE_SNAPSHOT:-/var/lib/waydroid/chromebook-fixer-cmdline}"

# One root step. orig_restore refuses a backup taken from a different
# waydroid version than the one installed (lib/orig-backup.sh).
$SUDO env FIXER_DPKG_INFO="${FIXER_DPKG_INFO:-}" bash -s -- "$FIXER_REPO/lib/orig-backup.sh" "$CMDLINE_SNAPSHOT" $CONFIGS <<'ROOT'
set -u
[ -n "${FIXER_DPKG_INFO:-}" ] || unset FIXER_DPKG_INFO
. "$1"; snapshot="$2"; shift 2
rc=0
for f in "$@"; do
    [ -f "$f" ] || continue
    orig_restore "$f"; r=$?
    [ "$r" = 1 ] && rc=1
done
[ "$rc" = 0 ] && rm -f "$snapshot"
exit "$rc"
ROOT
