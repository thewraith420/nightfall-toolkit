#!/bin/bash
# Waydroid fixes across a waydroid package upgrade, fixture-only.
#
# Real failure (Slate, 2026-11-04): an unattended upgrade took waydroid
# 1.6.2 -> 1.6.3 and replaced every file these fixes patch. Re-applying
# worked, but each .chromebook-fixer.orig was still the 1.6.2 copy, because
# the backup was taken once and never again - so revert would have put a
# 1.6.2 file back over 1.6.3. lib/orig-backup.sh re-takes the backup from
# any file that still matches what dpkg shipped, and refuses to restore one
# that does not match the installed version.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0

expect() { local name="$1" want="$2"; shift 2; "$@" >/dev/null 2>&1; local got=$?
    if [ "$got" = "$want" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $name  (want $want, got $got)"; fi; }
first()  { local name="$1" pat="$2"; shift 2; local out; out=$("$@" 2>&1 | head -1)
    if grep -q -- "$pat" <<<"$out"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $name  (first line: $out)"; fi; }
says()   { local name="$1" pat="$2"; shift 2; local out; out=$("$@" 2>&1)
    if grep -q -- "$pat" <<<"$out"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $name  (no '$pat' in: $(head -c 300 <<<"$out"))"; fi; }
same()   { local name="$1"; if cmp -s "$2" "$3"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $name  ($2 != $3)"; fi; }
holds()  { local name="$1"; shift; if "$@"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  $name"; fi; }
not()    { ! "$@"; }

# One escalation per apply/revert, counted rather than assumed.
SUDO_LOG="$T/sudo.log"
cat > "$T/sudo" <<EOF
#!/bin/bash
echo x >> "$SUDO_LOG"
exec "\$@"
EOF
chmod +x "$T/sudo"
export FIXER_SUDO="$T/sudo" FIXER_REPO="$REPO"
export FIXER_DPKG_INFO="$T/dpkg"
mkdir -p "$FIXER_DPKG_INFO"
sudo_count() { [ -f "$SUDO_LOG" ] && wc -l < "$SUDO_LOG" || echo 0; }

# The fixture "package": shipped files live under $T/root, and dpkg's md5sums
# list them by path without the leading slash, exactly as dpkg does.
ROOT="$T/root"
NET="$ROOT/usr/lib/waydroid/data/scripts/waydroid-net.sh"
BASE="$ROOT/usr/lib/waydroid/data/configs/config_base"
LXCPY="$ROOT/usr/lib/waydroid/tools/helpers/lxc.py"
NODES="$T/var/config_nodes"            # generated, owned by no package
mkdir -p "$(dirname "$NET")" "$(dirname "$BASE")" "$(dirname "$LXCPY")" "$(dirname "$NODES")"
export WAYDROID_NET_SCRIPT="$NET" WAYDROID_LXC_PY="$LXCPY" WAYDROID_CONFIG_NODES="$NODES"
export WAYDROID_LXC_CONFIGS="$BASE" WAYDROID_CMDLINE_SNAPSHOT="$T/var/snapshot" PROC_CMDLINE="$T/cmdline"
echo "root=/dev/sda2 ro quiet" > "$PROC_CMDLINE"

ship() {   # ship VERSION: install that waydroid version's files and md5sums
    local v="$1"
    printf '#!/bin/sh\n# waydroid %s\nIPTABLES_BIN="$(command -v iptables-legacy)"\nif [ ! -n "$IPTABLES_BIN" ]; then\n    IPTABLES_BIN="$(command -v iptables)"\nfi\n' "$v" > "$NET"
    printf '# waydroid %s\nlxc.rootfs.path = /var/lib/waydroid\nlxc.hook.post-stop = /dev/null\n' "$v" > "$BASE"
    printf '# waydroid %s\ndef generate_nodes_lxc_config(args):\n    make_entry("/dev/zero")\n    make_entry("/dev/null")\n    return nodes\n' "$v" > "$LXCPY"
    : > "$FIXER_DPKG_INFO/waydroid.md5sums"
    for f in "$NET" "$BASE" "$LXCPY"; do
        cp "$f" "$T/shipped-$v-$(basename "$f")"
        echo "$(md5sum < "$f" | cut -d' ' -f1)  ${f#/}" >> "$FIXER_DPKG_INFO/waydroid.md5sums"
    done
}
shipped() { echo "$T/shipped-$1-$(basename "$2")"; }

# ---- the library on its own ------------------------------------------------
. "$REPO/lib/orig-backup.sh"
ship 1.6.2
says "orig_shipped names the owning package" " waydroid$" orig_shipped "$NET"
expect "orig_shipped: an unowned file has no record" 1 orig_shipped "$NODES"
orig_backup "$NET"
same "backup of a pristine packaged file" "$NET.chromebook-fixer.orig" "$(shipped 1.6.2 "$NET")"
echo "# local edit" >> "$NET"
orig_backup "$NET"
same "a locally modified file never overwrites the existing backup" "$NET.chromebook-fixer.orig" "$(shipped 1.6.2 "$NET")"
echo "generated" > "$NODES"; orig_backup "$NODES"; echo "regenerated" > "$NODES"
orig_backup "$NODES"
says "unowned file: existing backup kept unless the caller says unpatched" "^generated$" cat "$NODES.chromebook-fixer.orig"
orig_backup "$NODES" 1
says "unowned file: re-taken when the caller says unpatched" "^regenerated$" cat "$NODES.chromebook-fixer.orig"
rm -f "$NET".chromebook-fixer.orig "$NODES" "$NODES".chromebook-fixer.orig

# ---- waydroid-netfilter ------------------------------------------------------
ship 1.6.2
: > "$SUDO_LOG"
expect "netfilter apply" 0 "$REPO/fixes/waydroid-netfilter/apply.sh"
holds "netfilter apply costs one escalation" [ "$(sudo_count)" = 1 ]
expect "netfilter verify after apply" 0 "$REPO/fixes/waydroid-netfilter/verify.sh"
same "netfilter backup is 1.6.2's file" "$NET.chromebook-fixer.orig" "$(shipped 1.6.2 "$NET")"

ship 1.6.3                                    # the upgrade
expect "netfilter verify after the upgrade: not applied" 1 "$REPO/fixes/waydroid-netfilter/verify.sh"
holds "netfilter: orig_replaced sees the upgrade" orig_replaced "$NET"
expect "netfilter re-apply" 0 "$REPO/fixes/waydroid-netfilter/apply.sh"
same "netfilter backup re-taken from 1.6.3" "$NET.chromebook-fixer.orig" "$(shipped 1.6.3 "$NET")"
: > "$SUDO_LOG"
expect "netfilter revert" 0 "$REPO/fixes/waydroid-netfilter/revert.sh"
holds "netfilter revert costs one escalation" [ "$(sudo_count)" = 1 ]
same "netfilter revert restores 1.6.3, not 1.6.2" "$NET" "$(shipped 1.6.3 "$NET")"
holds "after a revert, nothing reads as replaced" not orig_replaced "$NET"

# The state the Slate was actually in: patched 1.6.3, backup still 1.6.2.
"$REPO/fixes/waydroid-netfilter/apply.sh" >/dev/null 2>&1
cp "$(shipped 1.6.2 "$NET")" "$NET.chromebook-fixer.orig"
cp "$NET" "$T/net-patched"
expect "netfilter revert refuses a backup from another version" 1 "$REPO/fixes/waydroid-netfilter/revert.sh"
says "the refusal says how to get the packaged file back" "apt install --reinstall waydroid" "$REPO/fixes/waydroid-netfilter/revert.sh"
same "a refused revert leaves the file alone" "$NET" "$T/net-patched"
cp "$(shipped 1.6.3 "$NET")" "$NET"
says "netfilter revert of an unpatched file is a no-op" "not patched" "$REPO/fixes/waydroid-netfilter/revert.sh"

# ---- waydroid-lxc-hook (config_base) -----------------------------------------
ship 1.6.2; rm -f "$BASE.chromebook-fixer.orig"
expect "lxc-hook apply" 0 "$REPO/fixes/waydroid-lxc-hook/apply.sh"
same "lxc-hook backup is 1.6.2's config, taken before either change" "$BASE.chromebook-fixer.orig" "$(shipped 1.6.2 "$BASE")"
ship 1.6.3
first "lxc-hook detect leads with the upgrade" "waydroid update replaced the patched config" "$REPO/fixes/waydroid-lxc-hook/detect.sh"
expect "lxc-hook detect after the upgrade: needed" 0 "$REPO/fixes/waydroid-lxc-hook/detect.sh"
expect "lxc-hook re-apply" 0 "$REPO/fixes/waydroid-lxc-hook/apply.sh"
same "lxc-hook backup re-taken from 1.6.3" "$BASE.chromebook-fixer.orig" "$(shipped 1.6.3 "$BASE")"
expect "lxc-hook verify after re-apply" 0 "$REPO/fixes/waydroid-lxc-hook/verify.sh"
expect "lxc-hook revert" 0 "$REPO/fixes/waydroid-lxc-hook/revert.sh"
same "lxc-hook revert restores 1.6.3" "$BASE" "$(shipped 1.6.3 "$BASE")"
"$REPO/fixes/waydroid-lxc-hook/apply.sh" >/dev/null 2>&1
cp "$(shipped 1.6.2 "$BASE")" "$BASE.chromebook-fixer.orig"
expect "lxc-hook revert refuses a backup from another version" 1 "$REPO/fixes/waydroid-lxc-hook/revert.sh"
holds "a refused lxc-hook revert keeps the snapshot its config still binds" [ -f "$T/var/snapshot" ]
ship 1.6.3; rm -f "$BASE.chromebook-fixer.orig"
first "lxc-hook detect without a backup: plain reason, no upgrade claim" "post-stop" "$REPO/fixes/waydroid-lxc-hook/detect.sh"

# ---- waydroid-usb ------------------------------------------------------------
ship 1.6.2; printf 'lxc.mount.entry = /dev/zero dev/zero none bind 0 0\n' > "$NODES"
rm -f "$NODES.chromebook-fixer.orig" "$LXCPY.chromebook-fixer.orig"
first "usb detect, fresh" "no USB passthrough" "$REPO/fixes/waydroid-usb/detect.sh"
: > "$SUDO_LOG"
expect "usb apply" 0 "$REPO/fixes/waydroid-usb/apply.sh"
holds "usb apply costs one escalation" [ "$(sudo_count)" = 1 ]
expect "usb verify" 0 "$REPO/fixes/waydroid-usb/verify.sh"
expect "usb detect after apply: not needed" 1 "$REPO/fixes/waydroid-usb/detect.sh"
ship 1.6.3                                    # lxc.py replaced, config_nodes untouched
expect "usb verify: a replaced generator is not applied" 1 "$REPO/fixes/waydroid-usb/verify.sh"
expect "usb detect after the upgrade: needed" 0 "$REPO/fixes/waydroid-usb/detect.sh"
first "usb detect names the replaced lxc.py" "replaced the patched lxc.py" "$REPO/fixes/waydroid-usb/detect.sh"
expect "usb re-apply" 0 "$REPO/fixes/waydroid-usb/apply.sh"
same "usb lxc.py backup re-taken from 1.6.3" "$LXCPY.chromebook-fixer.orig" "$(shipped 1.6.3 "$LXCPY")"
holds "usb re-apply did not add a second bind to config_nodes" [ "$(grep -c dev/bus/usb "$NODES")" = 1 ]
expect "usb verify after re-apply" 0 "$REPO/fixes/waydroid-usb/verify.sh"
printf 'lxc.mount.entry = /dev/zero dev/zero none bind 0 0\n# regenerated\n' > "$NODES"
first "usb detect after waydroid regenerates its config" "regenerated its container config" "$REPO/fixes/waydroid-usb/detect.sh"
expect "usb apply onto the regenerated config" 0 "$REPO/fixes/waydroid-usb/apply.sh"
says "usb config_nodes backup re-taken from the regenerated file" "# regenerated" cat "$NODES.chromebook-fixer.orig"
expect "usb revert" 0 "$REPO/fixes/waydroid-usb/revert.sh"
same "usb revert restores 1.6.3's lxc.py" "$LXCPY" "$(shipped 1.6.3 "$LXCPY")"
holds "usb revert removes the bind" not grep -q dev/bus/usb "$NODES"
printf 'def nothing():\n    pass\n' > "$LXCPY"; printf 'x\n' > "$NODES"
expect "usb apply fails loudly when the generator has no make_entry" 1 "$REPO/fixes/waydroid-usb/apply.sh"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
