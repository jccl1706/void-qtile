#!/usr/bin/env sh
# =============================================================================
# reload.sh - apply config changes to a running qtile session
# =============================================================================
#
# Usage:  qtile/reload.sh          validate, deploy, restart the session
#         qtile/reload.sh --check  validate only, change nothing
#
# WHY THIS IS NOT JUST `qtile restart`. On the Wayland backend it does not
# exist:
#
#     error: Command 'restart' returned error:
#     Backend does not support restarting: wayland
#
# and `reload_config` re-reads config.py without rebuilding widgets that are
# already instantiated or reliably rebinding keys - so a change appears to
# apply and does not. The only thing that genuinely applies a config change is
# ending the session and letting agetty start it again.
#
# THE SESSION DIES AND COMES BACK, taking every open window with it. That is
# the cost on Wayland and this script does not hide it.

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.config/qtile"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# VALIDATE BEFORE DEPLOYING, because a config that fails to import leaves
# agetty respawning a session that dies immediately - a login loop, with the
# reason buried in ~/.local/share/qtile/qtile.log rather than on screen.
say "checking the config imports"
python3 -I "$HERE/check.py" --backend wayland >/dev/null 2>&1 \
    || { python3 -I "$HERE/check.py" --backend wayland; die "config did not import - nothing deployed"; }
say "  ok"

[ "${1:-}" = "--check" ] && exit 0

say "deploying to $DEST"
mkdir -p "$DEST"
cp "$HERE"/*.py "$DEST/"

say "restarting the session (every open window will close)"
if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wayland-0" ]; then
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
        qtile cmd-obj -o cmd -f shutdown 2>/dev/null || true
    say "  session ended; agetty will start it again on tty1"
else
    say "  no running session found - the new config applies at next login"
fi
