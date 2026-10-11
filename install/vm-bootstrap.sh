#!/usr/bin/env bash
# =============================================================================
# vm-bootstrap.sh - log into the live ISO and set up ssh, without a human
# =============================================================================
#
# Usage:  ./vm-bootstrap.sh          after booting the live ISO
#
# WHY. Every test cycle began with the same three lines typed by hand into the
# VM window - log in as root, install curl, fetch vm-ssh.sh. That is eight
# repetitions so far, each one a place to mistype something and a reason to
# wait for somebody to be at the keyboard.
#
# qemu's monitor can type, so the rig types them itself. The live ISO's
# credentials are published by Void and shown on its own login screen, so
# there is nothing secret here.
#
# It is deliberately slow and dumb: there is no way to read the screen and
# know when a prompt is ready - screendump is a picture, not text - so it
# types, waits, and the caller checks whether ssh answers afterwards.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSOLE="$HERE/vm-console.sh"

# The guest fetches this over HTTP from the served install/ directory, so the
# file has to be here while testing - but it is generated locally and is not
# tracked. Made now if absent, so a fresh clone can run the tests.
if [[ ! -f "$HERE/vm-ssh-key.pub" ]]; then
    [[ -f "$HOME/.ssh/void-vmtest" ]] || ssh-keygen -q -t ed25519 -N "" \
        -f "$HOME/.ssh/void-vmtest" -C "void-qtile vm test, throwaway"
    cp "$HOME/.ssh/void-vmtest.pub" "$HERE/vm-ssh-key.pub"
fi

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

# A bare Enter first: if a shell is already open the login lines would be run
# as COMMANDS, which is what happened the first time - `bash: root: command
# not found` - and there is no way to read the screen to tell the difference.
# An extra newline is harmless at a login prompt and harmless at a shell.
"$CONSOLE" key ret >/dev/null
sleep 2

say "logging in as root"
"$CONSOLE" type "root" >/dev/null
sleep 3
"$CONSOLE" type "voidlinux" >/dev/null
sleep 5

# XBPS MUST UPDATE ITSELF BEFORE IT WILL INSTALL ANYTHING. When the repo has a
# newer xbps than the ISO carries, every transaction is refused with
#
#     The 'xbps' package must be updated, please run `xbps-install -u xbps`
#
# so curl never arrives and the next line fails with "command not found". The
# ISO is a fixed image and the repo moves, so this gets more likely with age,
# not less.
say "updating xbps itself (the ISO is older than the repo)"
"$CONSOLE" type "xbps-install -uy xbps" >/dev/null
sleep 35

say "installing curl in the live environment"
"$CONSOLE" type "xbps-install -Sy curl" >/dev/null
sleep 35

say "fetching and running vm-ssh.sh"
"$CONSOLE" type "curl -fsSL http://10.0.2.2:8000/vm-ssh.sh | sh" >/dev/null
sleep 20

# ssh-keygen -A is in vm-ssh.sh, but it has been needed by hand often enough
# that doing it twice costs nothing and saves a round trip.
# vm-ssh.sh does both of these, but a restart after the keys exist is the
# single step that has had to be done by hand most often, so it is repeated
# here where repeating is free.
say "making sure host keys exist and sshd has loaded them"
"$CONSOLE" type "ssh-keygen -A && sv restart sshd" >/dev/null
sleep 8

say "checking whether ssh answers"
for _ in $(seq 1 20); do
    if timeout 4 bash -c 'exec 3<>/dev/tcp/127.0.0.1/2222' 2>/dev/null; then
        say "port 2222 is open"
        exit 0
    fi
    sleep 3
done
printf '\033[1;31m==>\033[0m ssh never came up - look at the VM window\n' >&2
exit 1
