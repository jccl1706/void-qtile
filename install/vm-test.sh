#!/usr/bin/env bash
# =============================================================================
# vm-test.sh - boot a throwaway UEFI VM to test install_void.sh
# =============================================================================
#
# Usage:  ./vm-test.sh ~/isos/void-live-x86_64-*.iso    boot the installer ISO
#         ./vm-test.sh --reboot                         boot the installed disk
#         ./vm-test.sh --clean                          throw the disk away
#         ./vm-test.sh --status                         what exists right now
#         ./vm-test.sh --keep-nvram <iso>                boot an ISO WITHOUT
#                                                        discarding the installed
#                                                        system's UEFI boot entry
#
# WHY A VM AND NOT THE REAL MACHINE. install_void.sh wipes a disk, and the
# first run of anything that wipes a disk is the one most likely to be wrong.
# The sibling fd44_hyprdot installer had six bugs found in a single afternoon
# this way, each hiding the next - including a variable that `set -u` made
# fatal, which had broken EVERY install for several commits.
#
# UEFI, NOT BIOS, and that is not a detail: install_void.sh checks for
# /sys/firmware/efi and refuses to run without it, the layout puts an ESP at
# partition 1, and GRUB is installed with --target=x86_64-efi. A BIOS VM would
# fail the preflight immediately and prove nothing about the real path.
#
# THE OVMF VARIABLE STORE IS PER-VM AND MUST BE WRITABLE. The firmware image in
# /usr/share/edk2 is read-only; its NVRAM companion holds the boot entries that
# grub-install writes with efibootmgr. Sharing the system copy would either
# fail or pollute the host's own boot entries, so a private copy is made here.

set -euo pipefail

VMDIR="${VMDIR:-$HOME/.cache/void-qtile-vm}"
DISK="$VMDIR/disk.qcow2"
NVRAM="$VMDIR/OVMF_VARS.fd"
DISK_SIZE="${DISK_SIZE:-40G}"
RAM="${RAM:-4096}"
CPUS="${CPUS:-4}"

# Where Fedora keeps the firmware. Named explicitly rather than globbed because
# a wrong guess here produces a VM that boots to a UEFI shell with no
# explanation.
OVMF_CODE=/usr/share/edk2/ovmf/OVMF_CODE.fd
OVMF_VARS=/usr/share/edk2/ovmf/OVMF_VARS.fd

c_g=$'\033[1;32m'; c_y=$'\033[1;33m'; c_r=$'\033[1;31m'; c_0=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$c_g" "$c_0" "$*"; }
warn() { printf '%s==>%s %s\n' "$c_y" "$c_0" "$*" >&2; }
die()  { printf '%s==>%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }

mode=boot
iso=""
keep_nvram=false
for a in "$@"; do
    case "$a" in
        --reboot) mode=reboot ;;
        --clean)  mode=clean ;;
        --status) mode=status ;;
        --keep-nvram) keep_nvram=true ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *.iso)    iso="$a" ;;
        *)        die "unknown argument: $a" ;;
    esac
done

case "$mode" in
status)
    printf '  %-22s %s\n' "vm directory" "$VMDIR"
    printf '  %-22s %s\n' "disk" \
        "$([[ -f "$DISK" ]] && echo "$(du -h "$DISK" | cut -f1) at $DISK" || echo "none")"
    printf '  %-22s %s\n' "nvram" "$([[ -f "$NVRAM" ]] && echo present || echo none)"
    printf '  %-22s %s\n' "qemu" "$(command -v qemu-system-x86_64 || echo 'NOT INSTALLED')"
    printf '  %-22s %s\n' "ovmf firmware" "$([[ -f "$OVMF_CODE" ]] && echo present || echo 'MISSING - install edk2-ovmf')"
    printf '  %-22s %s\n' "kvm" "$([[ -w /dev/kvm ]] && echo writable || echo 'NOT writable')"
    exit 0
    ;;
clean)
    log "Removing $VMDIR"
    rm -rf "$VMDIR"
    exit 0
    ;;
esac

# --- preconditions ------------------------------------------------------------
command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 not installed"
command -v qemu-img >/dev/null           || die "qemu-img not installed"
[[ -f "$OVMF_CODE" ]]                    || die "no OVMF firmware at $OVMF_CODE - install edk2-ovmf"
[[ -w /dev/kvm ]]                        || warn "/dev/kvm not writable - the VM will be SLOW"

mkdir -p "$VMDIR"

if [[ ! -f "$DISK" ]]; then
    log "Creating a $DISK_SIZE disk"
    qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
fi

# A private, writable copy of the variable store - see the note at the top.
#
# AND IT IS RESET WHEN BOOTING AN ISO, which is not tidiness either. Under UEFI
# the boot order lives in the NVRAM BootOrder variable, and qemu's `-boot
# order=d` is a legacy BIOS hint the firmware is free to ignore - which it
# does. So once an install has written its own entry with efibootmgr, every
# later ISO boot silently starts the INSTALLED SYSTEM instead:
#
#     BdsDxe: loading Boot0007 "Void" from HD(1,GPT,..)/EFI/Void/grubx64.efi
#
# which presents as "the live CD will not boot". Booting an ISO here means
# installing again, so the stale entry is discarded. --keep-nvram is for the
# other case: using an ISO to rescue an install whose boot entry matters.
if [[ ! -f "$NVRAM" ]] || { [[ "$mode" == boot ]] && ! $keep_nvram; }; then
    log "Resetting the OVMF variable store"
    cp "$OVMF_VARS" "$NVRAM"
    chmod u+w "$NVRAM"
fi

args=(
    -machine q35,accel=kvm
    -cpu host
    -smp "$CPUS"
    -m "$RAM"

    # SPLIT FIRMWARE: the code read-only from the system, the variables from
    # our own copy. This is what lets efibootmgr write a boot entry that
    # survives into --reboot.
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=raw,file=$NVRAM"

    # virtio-blk as nvme would be, so the installer's nvme/sd partition-naming
    # branch is NOT the one under test here - the device comes up as /dev/vda,
    # which takes the `sd`-style path. Worth knowing: this VM exercises
    # vda1/vda2/vda3, and the real machine exercises nvme0n1p1 and friends.
    -drive "file=$DISK,if=virtio,format=qcow2"

    # hostfwd puts the guest's sshd on localhost:2222, which is what lets the
    # install be DRIVEN and READ from outside instead of retyped into a window
    # and reported back by eye. The live image has openssh; it still needs a
    # key put in place inside the guest, which is one curl away.
    # THE INSTALL DIRECTORY, HANDED STRAIGHT TO THE GUEST over 9p, so that
    # getting the installer in does not depend on the guest having a download
    # tool. The live base image has NO curl and no wget - only xbps-install -
    # so the http route needs a package installed before it can fetch anything,
    # which is a bootstrap problem for a script whose job is to avoid manual
    # steps. Mount it in the guest with:
    #
    #     mkdir -p /mnt/host && mount -t 9p -o trans=virtio,version=9p2000.L host0 /mnt/host
    #
    # The http server stays as the fallback, since 9p needs the guest kernel to
    # have the modules and the live ISO is not guaranteed to.
    -virtfs "local,path=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")"),mount_tag=host0,security_model=mapped-xattr,id=host0"

    -netdev user,id=net0,hostfwd=tcp::2222-:22
    -device virtio-net-pci,netdev=net0

    # An explicit GTK window: this is meant to be watched, and the default
    # display backend varies with how qemu was built.
    -display gtk,show-cursor=on

    # Serial to a FILE rather than to stdio: stdio belongs to whoever launched
    # this, which may be a background job with no terminal, and a serial
    # console multiplexed onto a missing tty is a VM that will not start. A
    # file can be read while the VM runs.
    #
    # The live ISO does not pass console=ttyS0, so this captures firmware and
    # kernel-early output rather than the installer's own - the window is still
    # where the install is watched.
    -serial "file:$VMDIR/serial.log"
)

if [[ "$mode" == boot ]]; then
    [[ -n "$iso" ]]    || die "give me an ISO, or use --reboot"
    [[ -f "$iso" ]]    || die "no such ISO: $iso"
    log "Booting $(basename "$iso")"
    args+=(-cdrom "$iso" -boot order=d)
else
    log "Booting the installed disk"
    args+=(-boot order=c)
fi

cat <<'NEXT'

  Inside the VM, once it has booted the live ISO:

    # the live image logs in as root / voidlinux
    xbps-install -Sy curl
    curl -fsSL -o install_void.sh http://10.0.2.2:8000/install_void.sh
    chmod +x install_void.sh
    ./install_void.sh --preflight
    ./install_void.sh --disk /dev/vda

  Serve this directory to the guest first, from the host:

    cd install && python3 -m http.server 8000

  The guest reaches the host at 10.0.2.2 under qemu user networking.

NEXT

exec qemu-system-x86_64 "${args[@]}"
