#!/bin/bash
set -uo pipefail
# Overridable so this can be driven fixture-only (see tests/) - defaults are
# the real paths, unchanged.
CONFIGS="${WAYDROID_LXC_CONFIGS:-/usr/lib/waydroid/data/configs/config_base /var/lib/waydroid/lxc/waydroid/config}"

# Matches only the broken ",ro," form this fix briefly shipped (c6f3110,
# fixed 2026-10-01: a read-only bind makes Android's first-stage init abort
# with EROFS on its fatal chmod("/proc/cmdline", 0440), killing the
# container on every boot - see apply.sh). A config carrying it needs this
# fix just as much as one with no containment line at all; it must not read
# as "already applied" just because a healthy-looking line is present.
is_broken_ro_mount() { grep -qE 'proc/cmdline[[:space:]]+none[[:space:]]+bind,ro,' "$1" 2>/dev/null; }

FIXER_REPO="${FIXER_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "$FIXER_REPO/lib/orig-backup.sh"

FOUND=0
REPLACED=0
MSG=""
for f in $CONFIGS; do
    [ -f "$f" ] || continue
    orig_replaced "$f" && ! grep -qF "proc/cmdline" "$f" 2>/dev/null && REPLACED=1
    if grep -q "^lxc.hook.post-stop *= */dev/null" "$f" 2>/dev/null; then
        MSG+="$f still sets post-stop to /dev/null"$'\n'
        FOUND=1
    fi
    if is_broken_ro_mount "$f"; then
        MSG+="$f carries the read-only containment mount, which stops the container booting at all - needs migrating"$'\n'
        FOUND=1
    elif ! grep -qF "proc/cmdline" "$f" 2>/dev/null; then
        MSG+="$f does not contain the Android container's access to /proc/cmdline"$'\n'
        FOUND=1
    fi
done
if [ "$FOUND" = 1 ]; then
    # The GUI shows only the first line: lead with the cause when it is known.
    [ "$REPLACED" = 1 ] && echo "a waydroid update replaced the patched config; apply again"
    printf '%s' "$MSG"
    exit 0
fi
# waydroid absent entirely?
set -- $CONFIGS
[ -f "$1" ] || exit 1
exit 1
