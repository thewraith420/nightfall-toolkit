# SPDX-License-Identifier: GPL-3.0-or-later
# Backups of files a fix patches in place, kept as <file>.chromebook-fixer.orig.
#
# Sourced by apply/revert scripts, usually inside their single root step.
#
# Why this exists: the first version took the backup once and never again.
# A package upgrade replaces the patched file with the new version's, the
# next apply patches that, and the backup is still the OLD version's file -
# so revert would put waydroid 1.6.2's script back over 1.6.3 (real, on the
# Slate, 2026-11-04: waydroid-net.sh.chromebook-fixer.orig dated 2026-08-14).
#
# For files a package owns, dpkg records the md5 of what it shipped. A file
# that still matches it IS the current original, so the backup is re-taken
# from it every time. Files no package owns (configs waydroid generates under
# /var/lib) have no such record, so the caller says whether the file carries
# none of its changes yet.
#
# Overridable for tests: FIXER_DPKG_INFO (default /var/lib/dpkg/info).

ORIG_SUFFIX=".chromebook-fixer.orig"

_orig_md5() { md5sum < "$1" 2>/dev/null | cut -d' ' -f1; }

# "<md5> <package>" for the package that ships FILE, or nothing.
orig_shipped() {
    local rel="${1#/}" info="${FIXER_DPKG_INFO:-/var/lib/dpkg/info}" f
    for f in "$info"/*.md5sums; do
        [ -r "$f" ] || continue
        local sum
        sum=$(awk -v p="$rel" '$2 == p { print $1; exit }' "$f")
        if [ -n "$sum" ]; then
            local pkg="${f##*/}"; pkg="${pkg%.md5sums}"
            echo "$sum ${pkg%%:*}"
            return 0
        fi
    done
    return 1
}

# orig_backup FILE [UNPATCHED]
#   Call just before patching FILE. UNPATCHED=1 means the caller knows FILE
#   carries none of its changes; it only matters for files no package owns.
orig_backup() {
    local file="$1" unpatched="${2:-0}" backup="$1$ORIG_SUFFIX" shipped
    if shipped=$(orig_shipped "$file"); then
        if [ "$(_orig_md5 "$file")" = "${shipped%% *}" ]; then
            cp -a "$file" "$backup"         # the current package's own file
            return 0
        fi
        # Modified locally, by us or someone else: the first backup is the
        # best record of the original there is, so keep it.
        [ -f "$backup" ] || cp -a "$file" "$backup"
        return 0
    fi
    if [ "$unpatched" = 1 ] || [ ! -f "$backup" ]; then
        cp -a "$file" "$backup"
    fi
}

# orig_restore FILE
#   0 = restored or already original, 1 = refused (message printed),
#   2 = no backup (nothing to do).
orig_restore() {
    local file="$1" backup="$1$ORIG_SUFFIX" shipped
    shipped=$(orig_shipped "$file") || shipped=""
    if [ -n "$shipped" ] && [ "$(_orig_md5 "$file")" = "${shipped%% *}" ]; then
        echo "$file is already the packaged original"
        return 0
    fi
    [ -f "$backup" ] || return 2
    if [ -n "$shipped" ] && [ "$(_orig_md5 "$backup")" != "${shipped%% *}" ]; then
        echo "not restoring $file: the backup is from a different version of" \
             "${shipped#* } than the one installed. To get the packaged file back:" \
             "sudo apt install --reinstall ${shipped#* }"
        return 1
    fi
    cp -a "$backup" "$file"
    echo "restored $file"
}

# orig_replaced FILE: true when a backup exists and FILE has since been
# replaced by something else (a package upgrade, or a regenerated config).
# After a revert the two are identical, so this stays quiet then.
orig_replaced() {
    [ -f "$1$ORIG_SUFFIX" ] && [ -f "$1" ] && ! cmp -s "$1" "$1$ORIG_SUFFIX"
}
