#!/usr/bin/env bash
# =============================================================================
# fetch-themes.sh - the cursor and GTK themes xbps does not have
# =============================================================================
#
# Usage:  bin/fetch-themes.sh            fetch anything missing
#         bin/fetch-themes.sh --force    fetch again even if present
#         bin/fetch-themes.sh --status   what is installed
#
# WHY THIS EXISTS. Neither theme is packaged for Void, so both live under
# ~/.local/share and neither survives a reinstall. Without this they are two
# more things to remember at exactly the moment nobody is thinking about
# cursors - and the symptoms are confusing rather than obvious: a missing
# cursor theme gives a 24px pointer that reads as a scaling bug, and a missing
# GTK theme gives white file dialogs on a dark desktop that read as the dark
# setting being ignored.
#
# USER-LOCAL ON PURPOSE. These go in ~/.local/share, not /usr/share: they are
# not managed by xbps, and putting unmanaged files where a package manager
# expects to own things is how an upgrade overwrites them without saying so.
#
# NO ROOT NEEDED, and that is also why the archives are extracted with python
# rather than tar: Void's base-system ships no xz, and `tar -xJf` fails with
# "xz: Cannot exec" rather than naming the missing package. Python's lzma is
# in the standard library and always there.

set -euo pipefail

SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

force=false
mode=fetch
for a in "$@"; do
    case "$a" in
        --force)  force=true ;;
        --status) mode=status ;;
        -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
        *) echo "fetch-themes: unknown argument: $a" >&2; exit 2 ;;
    esac
done

c_g=$'\033[1;32m'; c_y=$'\033[1;33m'; c_d=$'\033[2m'; c_0=$'\033[0m'
say() { printf '%s==>%s %s\n' "$c_g" "$c_0" "$*"; }
warn() { printf '%s==>%s %s\n' "$c_y" "$c_0" "$*" >&2; }

# name | destination | url
THEMES=(
  "Bibata-Modern-Classic|$SHARE/icons|https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Classic.tar.xz"
  "Nordic|$SHARE/themes|https://github.com/EliverLara/Nordic/releases/download/v2.2.0/Nordic.tar.xz"
)

if [[ "$mode" == status ]]; then
    for entry in "${THEMES[@]}"; do
        IFS='|' read -r name dest _ <<<"$entry"
        if [[ -d "$dest/$name" ]]; then
            printf '  %-26s present  %s\n' "$name" "$(du -sh "$dest/$name" 2>/dev/null | cut -f1)"
        else
            printf '  %-26s MISSING  (would go in %s)\n' "$name" "${dest/#$HOME/\~}"
        fi
    done
    exit 0
fi

for entry in "${THEMES[@]}"; do
    IFS='|' read -r name dest url <<<"$entry"

    if [[ -d "$dest/$name" ]] && ! $force; then
        printf '    %salready%s  %s\n' "$c_d" "$c_0" "$name"
        continue
    fi

    say "fetching $name"
    if ! curl -fsSL --max-time 180 -o "$TMP/$name.tar.xz" "$url"; then
        warn "  could not download $name - skipping"
        continue
    fi

    # EXTRACTED INTO ITS OWN EMPTY DIRECTORY, and with python rather than tar:
    # no xz on a base Void install, and tarfile's data filter refuses absolute
    # paths and parent traversal, which a downloaded archive should never
    # contain and occasionally does.
    mkdir -p "$TMP/x-$name" "$dest"
    python3 -I -c '
import sys, tarfile
with tarfile.open(sys.argv[1]) as t:
    t.extractall(sys.argv[2], filter="data")
' "$TMP/$name.tar.xz" "$TMP/x-$name"

    if [[ ! -d "$TMP/x-$name/$name" ]]; then
        warn "  $name.tar.xz did not contain a directory called $name - skipping"
        continue
    fi

    rm -rf "${dest:?}/$name"
    cp -a "$TMP/x-$name/$name" "$dest/"
    printf '    installed %s (%s)\n' "${dest/#$HOME/\~}/$name" "$(du -sh "$dest/$name" | cut -f1)"
done

cat <<'NEXT'

  Both are user-local and unmanaged by xbps. To see them:
    cursor    qtile/reload.sh      (the compositor reads it at startup)
    GTK       restart the application
NEXT
