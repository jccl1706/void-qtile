#!/usr/bin/env bash
# =============================================================================
# vm-console.sh - read and type at the VM's console from outside it
# =============================================================================
#
# Usage:  ./vm-console.sh shot [out.png]      capture the console
#         ./vm-console.sh key ctrl-alt-f2    send a key combination
#         ./vm-console.sh type "some text"   type a string, then Enter
#         ./vm-console.sh cmd "info status"  any qemu monitor command
#
# WHY THIS EXISTS. A boot that stops before sshd starts leaves no way in: the
# serial log only carries firmware and early-kernel output, and Ctrl+Alt+F2 to
# reach another tty never arrives, because the host compositor claims that
# combination first. So the console had to be read out loud by whoever was
# sitting at the machine, which is slow and lossy.
#
# qemu's monitor can do both halves: screendump writes what the console is
# showing, sendkey types into it.

set -euo pipefail

SOCK="${SOCK:-$HOME/.cache/void-qtile-vm/monitor.sock}"
[[ -S "$SOCK" ]] || { echo "no monitor socket at $SOCK - is the VM running with -monitor?" >&2; exit 1; }

mon() {
    # PYTHON, BECAUSE BASH CANNOT DO THIS. `exec 3<>file` opens a UNIX socket
    # path as a FILE, which fails with "No such device or address" - bash's
    # bidirectional redirection only speaks TCP, through /dev/tcp. socat and
    # nc -U would both work and neither is installed here, while python3 is
    # already a dependency of everything else in this repo.
    #
    # The alternative - moving the monitor to a TCP port so /dev/tcp works -
    # was rejected: the qemu monitor can read and write arbitrary files, and a
    # TCP port is reachable by anything else running on the host.
    python3 -c '
import socket, sys, time
sock, cmd = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(3)
s.connect(sock)
time.sleep(0.2)
try:
    s.recv(65536)          # the banner and prompt
except Exception:
    pass
s.sendall((cmd + "\n").encode())
time.sleep(0.4)
out = b""
try:
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        out += chunk
        if out.rstrip().endswith(b"(qemu)"):
            break
except Exception:
    pass
s.close()
sys.stdout.write(out.decode(errors="replace"))
' "$SOCK" "$1"
}

action="${1:-shot}"
case "$action" in
shot)
    out="${2:-$HOME/.cache/void-qtile-vm/console.ppm}"
    rm -f "$out"
    mon "screendump $out" >/dev/null
    sleep 1
    [[ -f "$out" ]] || { echo "screendump produced nothing" >&2; exit 1; }
    echo "  captured: $out ($(du -h "$out" | cut -f1))"
    # PPM is what qemu writes; convert if anything is available, since nothing
    # reads PPM comfortably.
    if command -v magick >/dev/null; then
        magick "$out" "${out%.ppm}.png" && echo "  png: ${out%.ppm}.png"
    elif command -v convert >/dev/null; then
        convert "$out" "${out%.ppm}.png" && echo "  png: ${out%.ppm}.png"
    fi
    ;;
key)
    shift
    for k in "$@"; do mon "sendkey $k" >/dev/null; sleep 0.2; done
    echo "  sent: $*"
    ;;
type)
    shift
    text="$*"
    # sendkey takes key NAMES, not characters, so a string has to be spelled
    # out one key at a time. Only what a login prompt needs is mapped.
    for (( i=0; i<${#text}; i++ )); do
        ch="${text:i:1}"
        case "$ch" in
            [a-z0-9]) k="$ch" ;;
            [A-Z])    k="shift-$(printf '%s' "$ch" | tr 'A-Z' 'a-z')" ;;
            " ")      k="spc" ;;
            "-")      k="minus" ;;
            "_")      k="shift-minus" ;;
            ".")      k="dot" ;;
            "/")      k="slash" ;;
            *)        echo "  unmapped character: $ch" >&2; continue ;;
        esac
        mon "sendkey $k" >/dev/null
        sleep 0.08
    done
    mon "sendkey ret" >/dev/null
    echo "  typed: $text"
    ;;
cmd)
    shift
    mon "$*"
    ;;
*)
    sed -n '2,20p' "$0"; exit 1 ;;
esac
