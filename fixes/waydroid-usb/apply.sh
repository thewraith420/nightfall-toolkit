#!/bin/bash
set -euo pipefail

# Escalation is chosen by the caller: plain sudo in a terminal, pkexec
# under the GUI, which has no tty to prompt on.
SUDO="${FIXER_SUDO:-sudo}"
FIXER_REPO="${FIXER_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
NODES="${WAYDROID_CONFIG_NODES:-/var/lib/waydroid/lxc/waydroid/config_nodes}"
LXCPY="${WAYDROID_LXC_PY:-/usr/lib/waydroid/tools/helpers/lxc.py}"
ENTRY="lxc.mount.entry = /dev/bus/usb dev/bus/usb none bind,create=dir,optional 0 0"

[ -f "$NODES" ] || { echo "waydroid is not initialised ($NODES missing)"; exit 1; }

DO_NODES=0; DO_LXCPY=0
grep -q "dev/bus/usb" "$NODES" || DO_NODES=1
[ -f "$LXCPY" ] && ! grep -q "dev/bus/usb" "$LXCPY" && DO_LXCPY=1
if [ "$DO_NODES" = 0 ] && [ "$DO_LXCPY" = 0 ]; then
    echo "nothing to change"
    exit 0
fi

# One root step for both files. Each backup is taken from the file as it is
# now, unpatched, so after a waydroid upgrade it is the new version's
# original (lib/orig-backup.sh).
$SUDO env FIXER_DPKG_INFO="${FIXER_DPKG_INFO:-}" bash -s -- "$FIXER_REPO/lib/orig-backup.sh" \
    "$NODES" "$DO_NODES" "$LXCPY" "$DO_LXCPY" "$ENTRY" <<'ROOT'
set -eu
[ -n "${FIXER_DPKG_INFO:-}" ] || unset FIXER_DPKG_INFO
. "$1"; nodes="$2" do_nodes="$3" lxcpy="$4" do_lxcpy="$5" entry="$6"

# Live config, for the current session.
if [ "$do_nodes" = 1 ]; then
    orig_backup "$nodes" 1
    printf '%s\n' "$entry" >> "$nodes"
    echo "added USB bind to $nodes"
fi

# Generator, so it survives the config being regenerated.
if [ "$do_lxcpy" = 1 ]; then
    orig_backup "$lxcpy" 1
    python3 - "$lxcpy" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
if "dev/bus/usb" not in s:
    # Append after the last make_entry call in the nodes generator.
    marker = re.search(r'\n(\s*)make_entry\([^\n]*\)\n', s)
    if not marker:
        sys.exit(f"no make_entry call found in {p}; waydroid changed the generator, not patching it")
    indent = marker.group(1)
    add = (f'\n{indent}# USB passthrough (security keys etc). Bind the whole tree:\n'
           f'{indent}# bus/device numbers change on reconnect, so per-node entries break.\n'
           f'{indent}make_entry("/dev/bus/usb", options="bind,create=dir,optional 0 0")\n')
    idx = s.rfind(marker.group(0))
    s = s[:idx + len(marker.group(0))] + add + s[idx + len(marker.group(0)):]
    open(p, "w").write(s)
PY
    echo "patched $lxcpy so regenerated configs keep it"
fi
ROOT
echo "restart the waydroid session for this to take effect:"
echo "  waydroid session stop && waydroid session start"
