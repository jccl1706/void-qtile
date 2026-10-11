#!/usr/bin/env bash
# =============================================================================
# link-dotfiles.sh - put this repo's configs where the applications look
# =============================================================================
#
# Usage:  bin/link-dotfiles.sh            link everything
#         bin/link-dotfiles.sh --dry-run  say what it would do, change nothing
#         bin/link-dotfiles.sh --status   what is linked, what is not
#
# SYMLINKS, NOT COPIES, so that editing a file in the repo changes the running
# system and `git status` tells the truth about what has been changed. A copy
# means two versions that drift, and the drift is only discovered on the next
# machine.
#
# IT REFUSES TO OVERWRITE A REAL FILE. If something is already there and is not
# a link into this repo, it is left alone and reported - because the thing most
# likely to be sitting at one of these paths is configuration somebody wrote by
# hand and has not committed.
#
# qtile IS DELIBERATELY NOT LINKED HERE. Its config is nine modules that have
# to be validated before they are deployed - a config that fails to import
# leaves agetty respawning a session that dies instantly. qtile/reload.sh does
# that properly; this script does not duplicate it.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

dry_run=false
mode=link
for a in "$@"; do
    case "$a" in
        --dry-run) dry_run=true ;;
        --status)  mode=status ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *) echo "link-dotfiles: unknown argument: $a" >&2; exit 2 ;;
    esac
done

c_g=$'\033[1;32m'; c_y=$'\033[1;33m'; c_r=$'\033[1;31m'; c_d=$'\033[2m'; c_0=$'\033[0m'

made=0 already=0 fixed=0 blocked=0

# source-relative-to-repo  ->  destination
LINKS=(
    "foot/foot.ini        $CONFIG/foot/foot.ini"
    "dunst/dunstrc        $CONFIG/dunst/dunstrc"
    "gtk/settings.ini     $CONFIG/gtk-3.0/settings.ini"
    "gtk/settings.ini     $CONFIG/gtk-4.0/settings.ini"
    "gtk/gtk.css          $CONFIG/gtk-3.0/gtk.css"
    "gtk/gtk.css          $CONFIG/gtk-4.0/gtk.css"
    "portal/qtile-portals.conf  $CONFIG/xdg-desktop-portal/qtile-portals.conf"
)

link_one() {
    local src="$HERE/$1" dst="$2"

    [[ -f "$src" ]] || { printf '    %sFAIL%s    missing in the repo: %s\n' "$c_r" "$c_0" "$1"; return; }

    if [[ -L "$dst" ]]; then
        local target; target="$(readlink -f "$dst" 2>/dev/null || true)"
        if [[ "$target" == "$(readlink -f "$src")" ]]; then
            printf '    %salready%s  %s\n' "$c_d" "$c_0" "${dst/#$HOME/\~}"
            already=$((already + 1)); return
        fi
        printf '    %srepoint%s  %s\n' "$c_y" "$c_0" "${dst/#$HOME/\~}"
        $dry_run || { mkdir -p "$(dirname "$dst")"; ln -sfn "$src" "$dst"; }
        fixed=$((fixed + 1)); return
    fi

    if [[ -e "$dst" ]]; then
        # A REAL FILE. Not touched, and not backed up either - moving somebody's
        # config aside silently is how it gets lost.
        printf '    %sin the way%s  %s  (left alone)\n' "$c_r" "$c_0" "${dst/#$HOME/\~}"
        blocked=$((blocked + 1)); return
    fi

    printf '    %slink%s     %s\n' "$c_g" "$c_0" "${dst/#$HOME/\~}"
    $dry_run || { mkdir -p "$(dirname "$dst")"; ln -sfn "$src" "$dst"; }
    made=$((made + 1))
}

if [[ "$mode" == status ]]; then
    for entry in "${LINKS[@]}"; do
        read -r src dst <<<"$entry"
        state="absent"
        [[ -L "$dst" ]] && state="link -> $(readlink "$dst" | sed "s|$HERE|<repo>|")"
        [[ -f "$dst" && ! -L "$dst" ]] && state="a real file, NOT linked"
        printf '  %-34s %s\n' "${dst/#$HOME/\~}" "$state"
    done
    exit 0
fi

printf '%s==>%s Linking\n' "$c_g" "$c_0"
for entry in "${LINKS[@]}"; do
    read -r src dst <<<"$entry"
    link_one "$src" "$dst"
done

printf '\n  %d linked, %d already right, %d repointed, %d in the way\n' \
    "$made" "$already" "$fixed" "$blocked"

if (( blocked > 0 )); then
    printf '\n  Something real is where a link should go. Look at it, move it aside,\n'
    printf '  and run this again - it was not overwritten.\n'
fi

if ! $dry_run && (( made + fixed > 0 )); then
    cat <<'NEXT'

  To see the changes:
    foot      opens with the new colours; existing windows keep the old ones
    dunst     pkill dunst   (qtile's autostart starts it again at next login)
    GTK       restart the application; GTK reads these at startup only

  qtile is NOT linked by this script - use qtile/reload.sh, which validates
  the config before deploying it.
NEXT
fi
