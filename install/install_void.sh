#!/usr/bin/env bash
# =============================================================================
# install_void.sh - Void Linux on the Framework 13 AMD, with GRUB, LUKS2,
#                   btrfs, runit and qtile
# =============================================================================
#
# WHERE THIS RUNS: from a Void live ISO, as root. It needs xbps-install,
# xchroot and xgenfstab, which exist only on Void - so unlike a distribution
# installer that bootstraps itself, this one requires a Void environment to
# install Void from. `--preflight` says so plainly rather than failing later.
#
# Usage:  ./install_void.sh --disk /dev/nvme0n1 [options]
#         ./install_void.sh --dry-run --disk /dev/nvme0n1
#         ./install_void.sh --preflight
#
# Options:
#   --disk DEV        the disk to WIPE and install onto. Required, no default:
#                     there is no sensible default for a destructive operation.
#   --hostname NAME   default: void
#   --user NAME       default: jc
#   --backend B       wayland (default) or x11. Both are the same qtile
#                     package; this only decides what the session starts.
#   --dry-run         resolve everything, print every command, touch nothing.
#   --preflight       run the checks and stop.
#   --unattended      do not ask for confirmation before wiping the disk.
#
# WHAT THIS BUILDS, and the reasoning is in README.md rather than repeated here:
#
#     p1   1G     vfat    /boot/efi     ESP
#     p2   1G     ext4    /boot         kernel + initramfs, UNENCRYPTED
#     p3   rest   LUKS2   argon2id
#          \-- btrfs    @root  @home  @snapshots
#
# NO LVM: btrfs subvolumes share free space instead of needing sizes chosen in
# advance, and the one thing LVM would add - an encrypted swap volume for
# hibernation - is deliberately absent on this hardware.
#
# /boot IS NOT ENCRYPTED, ON PURPOSE. Void ships GRUB 2.12, which can unlock
# LUKS2 only with PBKDF2; argon2id arrived in GRUB 2.14. Encrypting /boot would
# therefore mean giving up the KDF that matters against a stolen laptop, in
# exchange for raising the effort of an evil-maid attack that Secure Boot being
# disabled on this machine already leaves wide open. Dracut unlocks the root,
# so there is exactly one passphrase prompt.
#
# NO HIBERNATION, NO SWAP PARTITION, NO resume=. Resuming from hibernation is
# unreliable on Framework AMD hardware. That is a decision taken deliberately,
# not an unfinished install - see README.md.

set -euo pipefail

VERSION=0.1

# Where this script lives, so it can find the files that ship beside it -
# resolved from BASH_SOURCE rather than $PWD, because the installer is as
# likely to be run as ./install/install_void.sh from the repo root as from
# inside install/.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- repository ---------------------------------------------------------------
#
# repo-default redirects to a mirror. Pinning a specific mirror here would age
# badly; the redirect is the supported entry point.
REPO="https://repo-default.voidlinux.org/current"
ARCH=x86_64

# --- defaults -----------------------------------------------------------------
disk=""
hostname=void
username=jc
backend=wayland
dry_run=false
preflight_only=false
unattended=false

ESP_SIZE=1GiB
BOOT_SIZE=1GiB

# =============================================================================
# Output
# =============================================================================
c_g=$'\033[1;32m'; c_y=$'\033[1;33m'; c_r=$'\033[1;31m'; c_d=$'\033[2m'; c_0=$'\033[0m'

log()  { printf '%s==>%s %s\n' "$c_g" "$c_0" "$*"; }
warn() { printf '%s==>%s %s\n' "$c_y" "$c_0" "$*" >&2; }
die()  { printf '%s==>%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }
note() { printf '    %s%s%s\n' "$c_d" "$*" "$c_0"; }

# Every mutating command goes through run(), which is what makes --dry-run
# exercise the whole control flow rather than a separate pretend path.
run() {
    if $dry_run; then
        printf '    %swould:%s %s\n' "$c_d" "$c_0" "$*"
        return 0
    fi
    "$@"
}

# Same, for a shell pipeline that cannot be an argv.
run_sh() {
    if $dry_run; then
        printf '    %swould:%s %s\n' "$c_d" "$c_0" "$1"
        return 0
    fi
    bash -c "$1"
}

# WRITE A CONFIG FILE FROM A REAL HEREDOC, which run_sh cannot do.
#
# The obvious spelling, `run_sh "cat > file <<'EOF' ... EOF"`, puts the whole
# heredoc inside a double-quoted bash string - so the first double quote in the
# CONTENT closes the argument. That is not hypothetical: it silently truncated
# earlyoom's OPTS= line to `OPTS=-m`, which would have installed a service that
# either refused to start or ran with none of its thresholds. Any config
# containing a quote, a $, or a backtick is hostile to that pattern.
#
# Contents arrive on stdin from a quoted heredoc at the call site, where bash
# does no substitution at all and nothing needs escaping.
write_file() {
    local dst="$1"
    if $dry_run; then
        printf '    %swould write:%s %s\n' "$c_d" "$c_0" "$dst"
        sed 's/^/        /'
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    cat > "$dst"
}

# Run a command inside the target. xchroot handles /proc, /sys, /dev and
# resolv.conf, which is why this does not mount them by hand.
xch() {
    if $dry_run; then
        printf '    %swould (in chroot):%s %s\n' "$c_d" "$c_0" "$*"
        return 0
    fi
    xchroot /mnt /bin/bash -c "$*"
}

# =============================================================================
# Arguments
# =============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk)       disk="${2:?--disk needs a device}"; shift ;;
        --hostname)   hostname="${2:?--hostname needs a name}"; shift ;;
        --user)       username="${2:?--user needs a name}"; shift ;;
        --backend)    backend="${2:?--backend needs wayland or x11}"; shift ;;
        --dry-run)    dry_run=true ;;
        --preflight)  preflight_only=true ;;
        --unattended) unattended=true ;;
        -h|--help)    sed -n '2,40p' "$0"; exit 0 ;;
        *)            die "unknown argument: $1" ;;
    esac
    shift
done

case "$backend" in
    wayland|x11) ;;
    *) die "--backend must be wayland or x11, not $backend" ;;
esac

log "install_void.sh v$VERSION  -  backend: $backend"

# =============================================================================
# Preflight
#
# Everything checkable before the disk is touched, checked BEFORE the disk is
# touched. A failure here costs nothing; the same failure three minutes later
# costs a wiped disk and a machine that will not boot.
# =============================================================================
log "Preflight"

fail=0
check() {
    local what="$1" cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        printf '    %sok%s      %s\n' "$c_g" "$c_0" "$what"
    else
        printf '    %sFAIL%s    %s\n' "$c_r" "$c_0" "$what"
        fail=$((fail + 1))
    fi
}

check "running as root"            '[[ $EUID -eq 0 ]]'
check "UEFI, not legacy BIOS"      '[[ -d /sys/firmware/efi ]]'
# -L MATTERS: repo-default.voidlinux.org is a redirector to a mirror, and
# `curl -f` without it treats the 3xx as a failure. A check that fails
# intermittently depending on whether the redirect fires is worse than no
# check, because it teaches you to ignore it. 30s rather than 15 for the same
# reason - this is the one check that depends on somebody else's network.
# --head, because this proves reachability and must not DOWNLOAD anything:
# fetching x86_64-repodata for real pulled 2.2MB on every preflight, which
# turned three dry runs into a two-minute wait. Asking for the headers of the
# file the install actually needs still proves the mirror serves it.
check "network reaches the repo"   "curl -fsSL --head --max-time 20 -o /dev/null '$REPO/x86_64-repodata'"
check "xbps-install present"       'command -v xbps-install'
check "xchroot present"            'command -v xchroot'
check "xgenfstab present"          'command -v xgenfstab'
check "cryptsetup present"         'command -v cryptsetup'
check "sgdisk present"             'command -v sgdisk'
check "mkfs.btrfs present"         'command -v mkfs.btrfs'
check "xbps signing keys present"  'compgen -G "/var/db/xbps/keys/*.plist"'

# cryptsetup must actually support argon2id, which is the whole basis of the
# layout decision. An old build that silently falls back to pbkdf2 would hand
# us a weaker volume than the README claims.
# NO PIPE HERE, AND THAT IS THE POINT. The obvious spelling,
#
#     cryptsetup --help | grep -q argon2id || cryptsetup benchmark | grep ...
#
# is broken under `set -o pipefail`: grep -q exits the moment it matches, which
# closes the pipe, which hands cryptsetup a SIGPIPE, which pipefail reports as
# a failed pipeline - so the left side "failed" WHENEVER IT MATCHED and the
# fallback ran every time. That fallback is `cryptsetup benchmark`, which
# deliberately spends about thirty seconds measuring KDFs, and it turned every
# preflight into a thirty-second wait for a check that had already passed.
check "cryptsetup knows argon2id"  '[[ "$(cryptsetup --help 2>&1)" == *argon2id* ]]'

if [[ -n "$disk" ]]; then
    check "disk $disk exists"      "[[ -b '$disk' ]]"
    check "disk is not mounted"    "! grep -q '^$disk' /proc/mounts"
fi

# A DRY RUN MUST NOT BE STOPPED BY THE ENVIRONMENT, because then it can only
# be exercised on Void - and the entire value of --dry-run is walking the whole
# control flow somewhere safe. The sibling fd44_hyprdot installer learned this
# the expensive way: an undefined variable under `set -u` broke EVERY install
# for several commits, and a dry run that reached the end would have exited
# non-zero the day it landed. So here the checks still report, and still decide
# a real install, but a dry run carries on past them.
if (( fail > 0 )); then
    if $dry_run; then
        warn "$fail preflight check(s) failed - continuing anyway because this is a dry run"
        note "a real install would stop here"
    else
        die "$fail preflight check(s) failed - nothing has been changed"
    fi
fi

# =============================================================================
# The package list, and proving every name in it exists
#
# RESOLVED BEFORE THE DISK IS TOUCHED, because the alternative is discovering a
# renamed or mistyped package in the middle of a transaction, on a disk that
# has already been wiped. The sibling Fedora installer grew the same check
# after a wizard branch referred to a package that had never existed under that
# name, and it is the cheapest check in this script: it reads repository
# metadata and changes nothing.
#
# It does NOT prove a package will install - a broken build or a missing
# dependency at install time still gets through. It proves the NAME resolves,
# which is the failure this script is actually capable of causing by itself.
# =============================================================================
base=(
    base-system
    # The pieces this layout cannot boot without. base-system does not imply
    # them: an installer that leaves these out produces a system that installs
    # cleanly and then cannot find its own root.
    cryptsetup
    btrfs-progs
    grub-x86_64-efi
    dracut
    # Firmware. Without linux-firmware-amd the GPU does not initialise, and
    # without the network firmware the MT7922 wifi is detected and useless.
    linux-firmware
    linux-firmware-amd
    linux-firmware-network
    # Microcode, which is not optional on a CPU this new.
    # (Void ships AMD microcode inside linux-firmware-amd.)
    NetworkManager
    elogind
    dbus
    polkit
    sudo
    git
    vim
    curl
    # ZRAM, AND NOT AS AN OPTION. This machine has no swap partition and no
    # hibernation by design, which makes compressed swap in RAM the ONLY memory
    # valve it has - without it the kernel has nowhere to put an anonymous page
    # and skips straight to killing something.
    #
    # The sibling Fedora installer got this wrong in exactly the way that is
    # easy to get wrong: zram-generator-defaults was gated behind
    # `[[ -n "$zram_size" ]]`, and $zram_size was empty by default, so every
    # ordinary install - and every --swap none install, which is what a machine
    # that must not hibernate gets - came up with no swap of any kind. Found
    # months later on a 54 GiB machine with zero swap devices. Unconditional
    # here, and asserted in the verification pass, so the same mistake cannot
    # be made quietly twice.
    zramen
    # EARLYOOM, the companion to a swapless machine. zram is a valve, not extra
    # memory: once it is full the kernel has nowhere left to go, and the
    # in-kernel OOM killer acts so late that the machine has usually already
    # spent a minute unresponsive. earlyoom watches from userspace and kills
    # the worst offender while there is still enough memory to do it cleanly.
    earlyoom
    # --- the desktop ---------------------------------------------------------
    #
    # qtile ALONE IS X11-ONLY. Void splits the Wayland backend into the
    # qtile-wayland subpackage, which carries libqtile/backend/wayland and the
    # session entry - install only `qtile` and `qtile start -b wayland` has no
    # backend to start. It pulls xorg-server-xwayland for X11 clients and wants
    # a sans-serif font, hence dejavu.
    qtile
    foot
    wl-clipboard
    dejavu-fonts-ttf
    # SSHD, so that a session that will not start is an inconvenience rather
    # than a reinstall. On a machine being set up for a brand new window
    # manager this is not optional equipment.
    openssh
    # --- what the qtile config actually calls ---------------------------------
    #
    # Every one of these is named by a keybinding or an autostart line in
    # qtile/config.py. A desktop whose volume keys do nothing is not configured,
    # it is a list of good intentions - so the two files are kept in step
    # deliberately, and the verification pass checks the binaries exist.
    #
    # pipewire already depends on libspa-alsa, so hardware audio needs nothing
    # further. wireplumber is the session manager and provides wpctl, which is
    # what the volume keys call.
    pipewire
    wireplumber
    alsa-pipewire
    brightnessctl
    grim
    slurp
    dunst
    libnotify
    # wlr-randr sets the panel scale, which qtile's Wayland backend cannot
    # express in its config file at all - see the note in qtile/config.py.
    wlr-randr
)

# The backend decides what else is needed. Wayland needs nothing beyond
# qtile-wayland; X11 needs an actual X server and something to start it.
case "$backend" in
    wayland) base+=(qtile-wayland) ;;
    # xterm on X11, not by preference: foot is a Wayland client and the config
    # falls back to xterm there. A config naming a terminal nobody installed
    # has no way to open a window to fix itself.
    x11)     base+=(xorg-minimal xorg-server xinit xrandr xsetroot xterm) ;;
esac

log "Resolving every package name against the repo"
if command -v xbps-query >/dev/null 2>&1; then
    missing=()
    for pkg in "${base[@]}"; do
        if XBPS_ARCH="$ARCH" xbps-query -R --repository="$REPO" -S "$pkg" >/dev/null 2>&1; then
            printf '    %sok%s      %s\n' "$c_g" "$c_0" "$pkg"
        else
            printf '    %sFAIL%s    %s\n' "$c_r" "$c_0" "$pkg"
            missing+=("$pkg")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        if $dry_run; then
            warn "${#missing[@]} package name(s) did not resolve - continuing, this is a dry run"
        else
            die "${#missing[@]} package name(s) did not resolve: ${missing[*]}"
        fi
    else
        log "${#base[@]}/${#base[@]} package names resolved"
    fi
else
    warn "xbps-query not present - cannot resolve package names"
    $dry_run || die "refusing to wipe a disk without checking the package list first"
fi

if $preflight_only; then
    log "Preflight only - stopping here"
    exit 0
fi

if [[ -z "$disk" ]]; then
    $dry_run || die "--disk is required (there is no safe default for a wipe)"
    disk=/dev/DRYRUN
    note "no --disk given; using $disk so the rest of the flow can be walked"
fi

# Partition names differ between nvme and sd devices: nvme0n1 -> nvme0n1p1,
# sda -> sda1. Getting this wrong formats the wrong thing.
if [[ "$disk" =~ (nvme|mmcblk|loop) ]]; then
    p1="${disk}p1"; p2="${disk}p2"; p3="${disk}p3"
else
    p1="${disk}1"; p2="${disk}2"; p3="${disk}3"
fi

# =============================================================================
# Confirm
# =============================================================================
if ! $unattended && ! $dry_run; then
    echo
    warn "This will DESTROY everything on $disk:"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$disk" 2>/dev/null | sed 's/^/    /'
    echo
    read -r -p "    Type the disk name to confirm ($disk): " answer < /dev/tty
    [[ "$answer" == "$disk" ]] || die "not confirmed - nothing has been changed"
fi

# =============================================================================
# Partition
# =============================================================================
log "Partitioning $disk"

run wipefs -a "$disk"
run sgdisk --zap-all "$disk"
run sgdisk \
    -n "1:0:+$ESP_SIZE"  -t 1:ef00 -c 1:"EFI System" \
    -n "2:0:+$BOOT_SIZE" -t 2:8300 -c 2:"boot" \
    -n "3:0:0"           -t 3:8309 -c 3:"cryptroot" \
    "$disk"
run partprobe "$disk"
run udevadm settle

# =============================================================================
# Encrypt
# =============================================================================
log "Creating the LUKS2 container on $p3"
note "argon2id, which is the point of leaving /boot unencrypted"

if ! $dry_run; then
    # The passphrase is typed twice by cryptsetup itself, on the tty. It is
    # never passed through this script, never in a variable, never in the
    # process list - which also means this cannot be run with stdin redirected.
    cryptsetup luksFormat \
        --type luks2 \
        --pbkdf argon2id \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha512 \
        "$p3"
    cryptsetup open "$p3" cryptroot
else
    note "would: cryptsetup luksFormat --type luks2 --pbkdf argon2id ... $p3"
    note "would: cryptsetup open $p3 cryptroot"
fi

# =============================================================================
# Filesystems
# =============================================================================
log "Making filesystems"

run mkfs.vfat -F32 -n EFI "$p1"
run mkfs.ext4 -q -L boot "$p2"
run mkfs.btrfs -q -L void /dev/mapper/cryptroot

# --- subvolumes ---------------------------------------------------------------
#
# @root and @home separately so that a snapshot of the system does not drag the
# home directory with it, and @snapshots as its own subvolume so snapshots are
# not inside the thing being snapshotted.
log "Creating btrfs subvolumes"
run mount /dev/mapper/cryptroot /mnt
for sub in @root @home @snapshots; do
    run btrfs subvolume create "/mnt/$sub"
done
run umount /mnt

# --- mount --------------------------------------------------------------------
#
# compress=zstd:1 rather than a higher level: level 1 is nearly free on this
# CPU and still halves the kernel tree. noatime because nothing here reads
# access times and every read would otherwise be a write.
MOPTS="rw,noatime,compress=zstd:1,ssd,space_cache=v2"

log "Mounting the target"
run mount -o "$MOPTS,subvol=@root" /dev/mapper/cryptroot /mnt
run mkdir -p /mnt/home /mnt/.snapshots /mnt/boot
run mount -o "$MOPTS,subvol=@home"      /dev/mapper/cryptroot /mnt/home
run mount -o "$MOPTS,subvol=@snapshots" /dev/mapper/cryptroot /mnt/.snapshots
run mount "$p2" /mnt/boot
run mkdir -p /mnt/boot/efi
run mount "$p1" /mnt/boot/efi

# =============================================================================
# Bootstrap
# =============================================================================
log "Installing the base system"

# The signing keys must be in place BEFORE the first xbps-install into the
# target, or every package fails verification.
run mkdir -p /mnt/var/db/xbps/keys
run_sh "cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/"



run_sh "XBPS_ARCH=$ARCH xbps-install -Sy -r /mnt -R '$REPO' ${base[*]}"

# =============================================================================
# fstab
# =============================================================================
log "Generating fstab"
run_sh "xgenfstab -U /mnt > /mnt/etc/fstab"

# =============================================================================
# Inside the target
# =============================================================================
log "Configuring the installed system"

luks_uuid=""
if ! $dry_run; then
    luks_uuid="$(blkid -s UUID -o value "$p3")"
    [[ -n "$luks_uuid" ]] || die "could not read the LUKS UUID of $p3"
else
    luks_uuid="<luks-uuid>"
fi
note "LUKS UUID: $luks_uuid"

run_sh "echo '$hostname' > /mnt/etc/hostname"

# --- locale -------------------------------------------------------------------
#
# Void generates only the locales named in /etc/default/libc-locales, and
# xbps-reconfigure is what acts on the file. Skipping this leaves a system
# whose locale is "C" and whose terminal cannot draw a UTF-8 character.
run_sh "sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /mnt/etc/default/libc-locales"
run_sh "echo 'LANG=en_US.UTF-8' > /mnt/etc/locale.conf"
xch "xbps-reconfigure -f glibc-locales"

# --- crypttab -----------------------------------------------------------------
#
# `none` as the key file means dracut prompts on the console. The keyfile dance
# in Void's own FDE guide exists to avoid a SECOND prompt when GRUB has already
# asked for one - with /boot unencrypted there is only ever one, so there is no
# keyfile to protect and no chmod 000 to get wrong.
run_sh "printf 'cryptroot  UUID=%s  none  luks,discard\\n' '$luks_uuid' > /mnt/etc/crypttab"

# --- dracut -------------------------------------------------------------------
#
# hostonly builds an initramfs for THIS machine rather than every machine,
# which is smaller and faster. The modules are named explicitly rather than
# left to detection: detection reads the running system, and the running system
# is the live ISO, not the target.
run mkdir -p /mnt/etc/dracut.conf.d
write_file /mnt/etc/dracut.conf.d/10-void-qtile.conf <<'DRACUT'
hostonly="yes"
hostonly_cmdline="no"
add_dracutmodules+=" crypt btrfs "
install_items+=" /etc/crypttab "
compress="zstd"
DRACUT

# --- GRUB ---------------------------------------------------------------------
#
# rd.luks.uuid is how dracut is told which container to open; root= and
# rootflags= are how the kernel is told which subvolume is /.
#
# NO resume= AND NO SWAP, deliberately - see the header.
#
# amd_pstate=active because this CPU's governor set depends on it: with
# amd_pstate in passive mode `schedutil` exists and `powersave` behaves
# differently. Chosen here so the installed system matches what the power
# configuration expects rather than discovering it afterwards.
#
# GRUB_ENABLE_CRYPTODISK is absent ON PURPOSE. It is for a GRUB that must
# itself unlock a container; ours reads a plain /boot. Setting it would make
# GRUB prompt for a passphrase it does not need and cannot use on an argon2id
# volume.
cmdline="rd.luks.uuid=$luks_uuid root=UUID=<btrfs> rootflags=subvol=@root rw amd_pstate=active loglevel=4"
if ! $dry_run; then
    btrfs_uuid="$(blkid -s UUID -o value /dev/mapper/cryptroot)"
    cmdline="rd.luks.uuid=$luks_uuid root=UUID=$btrfs_uuid rootflags=subvol=@root rw amd_pstate=active loglevel=4"
fi
note "kernel cmdline: $cmdline"

# UNQUOTED heredoc here, unlike the others, because $cmdline must expand. That
# is safe with write_file: the expansion happens at this call site, in the
# script's own syntax, rather than inside a double-quoted string being handed
# to another shell.
write_file /mnt/etc/default/grub <<GRUBCFG
GRUB_DEFAULT=0
GRUB_TIMEOUT=2
GRUB_DISTRIBUTOR="Void"
GRUB_CMDLINE_LINUX_DEFAULT="$cmdline"
GRUB_TERMINAL_OUTPUT="console"
GRUB_DISABLE_OS_PROBER=true
GRUBCFG

xch "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Void"

# --- user ---------------------------------------------------------------------
log "Creating $username"
xch "useradd -m -G wheel,audio,video,input,storage,network -s /bin/bash '$username'"
run_sh "echo '%wheel ALL=(ALL:ALL) ALL' > /mnt/etc/sudoers.d/wheel"
run chmod 0440 /mnt/etc/sudoers.d/wheel

if ! $dry_run; then
    echo
    log "Set the password for $username"
    xchroot /mnt /bin/bash -c "passwd '$username'" < /dev/tty
    log "Set the root password"
    xchroot /mnt /bin/bash -c "passwd root" < /dev/tty
fi

# --- wifi ---------------------------------------------------------------------
#
# THE MT7922 NEEDS POWER SAVING OFF. It is the documented fix for the dropout
# instability this chip is known for, and it is set here rather than left as a
# thing to discover after the first week of flaky wifi.
run mkdir -p /mnt/etc/NetworkManager/conf.d
write_file /mnt/etc/NetworkManager/conf.d/10-wifi-powersave.conf <<'NMCONF'
# 2 = disable power saving. The MT7922/RZ616 in this laptop drops its
# association with power saving on; this is the documented remedy.
[connection]
wifi.powersave = 2
NMCONF

# --- zram ---------------------------------------------------------------------
#
# zramen's own defaults are ZRAM_SIZE=25 (percent of RAM) capped by
# ZRAM_MAX_SIZE=4096 MB. On a 54 GiB machine that cap binds at 4 GB, which is
# half what the Fedora install on the same hardware ended up with. 8 GB is
# chosen to match it: enough to be a real valve, small enough that compressing
# into it never competes seriously with the memory it is protecting.
#
# zstd rather than zramen's lz4 default: this CPU compresses zstd fast enough
# that the better ratio is free, and the whole point of zram is ratio - a valve
# that holds more per byte of RAM spent.
#
# /etc/sv/zramen/conf is a conf_file in the package, so xbps will not overwrite
# what is written here on update.
log "Configuring zram"
write_file /mnt/etc/sv/zramen/conf <<'ZRAMCONF'
# Written by install_void.sh. This machine has NO swap partition and NO
# hibernation on purpose, so this is its only memory valve.
export ZRAM_COMP_ALGORITHM=zstd
export ZRAM_SIZE=25
export ZRAM_MAX_SIZE=8192
export ZRAM_PRIORITY=100
ZRAMCONF

# --- earlyoom -----------------------------------------------------------------
#
# THE PERCENTAGE DEFAULT IS WRONG ON A MACHINE THIS SIZE. earlyoom defaults to
# -m 10, and 10% of 54 GiB is 5.4 GB held in reserve - it would start killing
# things with more memory free than most machines have in total. Upstream's own
# idiom for this is to pass both forms, because "if you pass both -M and -m,
# the lower value is used": so -m 10 -M 2097152 reads as "10% of RAM, but at
# most 2 GiB", and on this machine the 2 GiB cap is what binds.
#
# SIGTERM FIRES ONLY WHEN BOTH MEMORY AND SWAP ARE LOW, which is why -s matters
# here rather than being redundant: with 8 GB of zram, -s 10 means earlyoom
# holds off until the valve itself is nearly full. SIGKILL follows at half
# those figures, which is earlyoom's default and is left alone.
#
# --avoid PROTECTS THE SESSION. Killing the browser costs a browser; killing
# qtile costs every window on the desktop at once. dbus and elogind are in
# there for the same reason - the session does not survive losing them.
#
# --prefer NAMES THE USUAL CULPRITS: browsers, electron apps, and a runaway
# compile, which should die before an editor with unsaved work does.
#
# BOTH REGEXES MATCH `comm`, WHICH IS THE FIRST 15 BYTES OF THE PROCESS NAME
# AND NOTHING MORE. A pattern written against a longer name silently never
# matches, so everything here is short enough to survive the truncation.
#
# --syslog so that a kill is findable afterwards. The service sends stdout to
# /dev/null, so without it the only record of why something vanished would be
# gone by the time anybody asked.
log "Configuring earlyoom"
run mkdir -p /mnt/etc/sv/earlyoom
write_file /mnt/etc/sv/earlyoom/conf <<'EOCONF'
# Written by install_void.sh. Read by /etc/sv/earlyoom/run as the OPTS variable.
#
# -m 10 -M 2097152 : 10% of RAM but at most 2 GiB (the lower wins)
# -s 10            : and only once the zram swap is nearly full too
OPTS="-m 10 -M 2097152 -s 10 --syslog --avoid '^(qtile|Xwayland|sshd|dbus-daemon|elogind|runsvdir|runit)$' --prefer '^(chromium|firefox|electron|node|cc1plus|rustc|ld)$'"
EOCONF

# --- elogind in PAM -----------------------------------------------------------
#
# WITHOUT THIS THERE IS NO XDG_RUNTIME_DIR AND NO WAYLAND SESSION. elogind
# creates /run/user/$UID through its PAM session module, and a user cannot
# create that directory themselves - /run/user is root-owned - so a fallback in
# the shell profile is not an option either. The session simply fails with
# "XDG_RUNTIME_DIR not set".
#
# Added explicitly rather than assumed: whether a distribution wires this up by
# default is exactly the kind of thing that is true until it is not, and the
# cost of checking is one grep.
log "Wiring elogind into PAM"
if ! $dry_run; then
    if ! grep -q pam_elogind /mnt/etc/pam.d/system-login 2>/dev/null; then
        printf 'session  optional  pam_elogind.so\n' >> /mnt/etc/pam.d/system-login
        note "added pam_elogind.so to system-login"
    else
        note "already present"
    fi
else
    note "would add pam_elogind.so to /etc/pam.d/system-login if absent"
fi

# --- autologin on tty1 --------------------------------------------------------
#
# The same arrangement as the sibling Fedora machine: no display manager at
# all. A display manager on a single-user laptop whose disk is already
# encrypted asks for a second password to protect nothing - the LUKS passphrase
# is the gate, and it has already been typed by this point.
#
# --noclear is kept from Void's own default; losing it means the boot messages
# are wiped before they can be read, which is the opposite of helpful on a
# machine still being built.
log "Enabling autologin for $username on tty1"
write_file /mnt/etc/sv/agetty-tty1/conf <<AGETTY
# Written by install_void.sh.
#
# Autologin, because there is no display manager: the LUKS passphrase is the
# gate and it has already been answered by the time this runs.
GETTY_ARGS="--noclear --autologin $username"
BAUD_RATE=38400
TERM_NAME=linux
AGETTY

# --- the session -------------------------------------------------------------
#
# ON tty1 ONLY, AND THAT GUARD IS THE IMPORTANT PART. A profile that starts a
# compositor unconditionally starts one down an ssh connection too, where it
# fails, taking the login with it - so the one route in that still works when
# the session is broken would break along with it.
#
# `exec` so the compositor replaces the shell: without it, quitting qtile drops
# to a logged-in shell on tty1, which is a session nobody asked for.
#
# dbus-run-session rather than bare qtile, because a Wayland desktop talks to
# dbus constantly - portals, notifications, polkit agents - and starting
# without a session bus leaves all of it half working in ways that look like
# unrelated bugs.
log "Writing the session startup"
if [[ "$backend" == wayland ]]; then
    session_cmd='exec dbus-run-session qtile start -b wayland'
else
    session_cmd='exec startx /usr/bin/qtile start -b x11'
fi

write_file "/mnt/home/$username/.bash_profile" <<PROFILE
# Written by install_void.sh.
[ -f ~/.bashrc ] && . ~/.bashrc

# Start the desktop on tty1 and NOWHERE ELSE. An ssh login, or any other tty,
# must fall through to a plain shell: if this ran everywhere, a session that
# will not start would also break the way back in to fix it.
if [ "\$(tty)" = "/dev/tty1" ] && [ -z "\${WAYLAND_DISPLAY:-}" ] && [ -z "\${DISPLAY:-}" ]; then
    $session_cmd
fi
PROFILE
run chown "1000:1000" "/mnt/home/$username/.bash_profile"

# --- the qtile config ---------------------------------------------------------
#
# Copied, not symlinked: at this point the repo exists only on the machine
# running the installer, not on the target. The dotfile link step belongs after
# the clone; this is just enough to boot into something usable with the keys
# already right.
log "Installing the qtile config"
if [[ -f "$here/qtile/config.py" ]]; then
    run mkdir -p "/mnt/home/$username/.config/qtile"
    run cp "$here/qtile/config.py" "/mnt/home/$username/.config/qtile/config.py"
    run chown -R 1000:1000 "/mnt/home/$username/.config"
else
    warn "no qtile/config.py beside the installer - qtile will use its own default"
fi

# =============================================================================
# Services
#
# runit has no presets and no enable command: a service is a symlink from
# /etc/sv/<name> into /var/service. Nothing is running because a package is
# installed, which is a difference from systemd worth internalising.
# =============================================================================
log "Enabling runit services"

services=(dbus elogind NetworkManager polkitd zramen earlyoom sshd agetty-tty1)
for s in "${services[@]}"; do
    xch "[ -d /etc/sv/$s ] && ln -sfn /etc/sv/$s /var/service/$s || echo '  (no /etc/sv/$s - skipped)'"
done

# =============================================================================
# Reconfigure - this is what builds the initramfs and grub.cfg
# =============================================================================
log "Reconfiguring everything (this builds the initramfs and grub.cfg)"
xch "xbps-reconfigure -fa"

# =============================================================================
# Verify
#
# The install is finished; this is the pass that decides whether it WORKED.
# Every check here exists because its absence produces a system that installed
# without complaint and does not boot.
# =============================================================================
log "Verifying"

vfail=0
vcheck() {
    local what="$1" cmd="$2"
    if $dry_run; then printf '    %sskip%s    %s\n' "$c_d" "$c_0" "$what"; return 0; fi
    if eval "$cmd" >/dev/null 2>&1; then
        printf '    %sok%s      %s\n' "$c_g" "$c_0" "$what"
    else
        printf '    %sFAIL%s    %s\n' "$c_r" "$c_0" "$what"
        vfail=$((vfail + 1))
    fi
}

vcheck "kernel in /boot"             'compgen -G "/mnt/boot/vmlinuz-*"'
vcheck "initramfs built"             'compgen -G "/mnt/boot/initramfs-*.img"'
vcheck "grub.cfg written"            '[[ -s /mnt/boot/grub/grub.cfg ]]'
vcheck "grub.cfg names the LUKS uuid" "grep -q '$luks_uuid' /mnt/boot/grub/grub.cfg"
vcheck "EFI binary on the ESP"       '[[ -f /mnt/boot/efi/EFI/Void/grubx64.efi ]]'
vcheck "crypttab written"            '[[ -s /mnt/etc/crypttab ]]'
vcheck "fstab names @root"           'grep -q "subvol=@root" /mnt/etc/fstab'
vcheck "fstab names @home"           'grep -q "subvol=@home" /mnt/etc/fstab'
vcheck "the user exists"             "grep -q '^$username:' /mnt/etc/passwd"
vcheck "wheel may sudo"              '[[ -s /mnt/etc/sudoers.d/wheel ]]'
vcheck "dbus service enabled"        '[[ -L /mnt/var/service/dbus ]]'
vcheck "elogind service enabled"     '[[ -L /mnt/var/service/elogind ]]'
vcheck "NetworkManager enabled"      '[[ -L /mnt/var/service/NetworkManager ]]'
vcheck "wifi powersave disabled"     'grep -q "wifi.powersave = 2" /mnt/etc/NetworkManager/conf.d/10-wifi-powersave.conf'
vcheck "amd microcode present"       'compgen -G "/mnt/boot/*amd*" || compgen -G "/mnt/usr/lib/firmware/amd*"'
# The initramfs must contain the crypt module, or the machine boots to a dracut
# shell with no way to open its own root. Checking the file rather than trusting
# the config that asked for it.
vcheck "initramfs contains crypt"    'lsinitrd /mnt/boot/initramfs-*.img 2>/dev/null | grep -q crypt'
# Both halves, because a missing swap device presents as nothing at all - the
# machine boots and behaves until the day it runs out of memory.
vcheck "zramen installed"            '[[ -x /mnt/usr/bin/zramen ]]'
vcheck "zramen service enabled"      '[[ -L /mnt/var/service/zramen ]]'
vcheck "zram sized, not defaulted"   'grep -q "ZRAM_MAX_SIZE=8192" /mnt/etc/sv/zramen/conf'
vcheck "earlyoom installed"          '[[ -x /mnt/usr/bin/earlyoom ]]'
vcheck "earlyoom service enabled"    '[[ -L /mnt/var/service/earlyoom ]]'
vcheck "earlyoom capped at 2GiB"     'grep -q "M 2097152" /mnt/etc/sv/earlyoom/conf'
vcheck "earlyoom protects qtile"     'grep -q "avoid.*qtile" /mnt/etc/sv/earlyoom/conf'
vcheck "qtile installed"             '[[ -x /mnt/usr/bin/qtile ]]'
# The backend is a DIRECTORY inside libqtile, not a flag: if qtile-wayland was
# missing this passes every other check and then fails at `qtile start`.
vcheck "qtile wayland backend"       "$([[ $backend == wayland ]] && echo 'compgen -G "/mnt/usr/lib/python3*/site-packages/libqtile/backend/wayland"' || echo true)"
vcheck "a terminal exists"           '[[ -x /mnt/usr/bin/foot ]]'
vcheck "sshd installed"              '[[ -x /mnt/usr/bin/sshd ]]'
vcheck "sshd service enabled"        '[[ -L /mnt/var/service/sshd ]]'
vcheck "autologin configured"        "grep -q 'autologin $username' /mnt/etc/sv/agetty-tty1/conf"
vcheck "agetty-tty1 enabled"         '[[ -L /mnt/var/service/agetty-tty1 ]]'
vcheck "session starts on tty1 only" "grep -q 'tty1' /mnt/home/$username/.bash_profile"
vcheck "qtile config installed"      "[[ -s /mnt/home/$username/.config/qtile/config.py ]]"
vcheck "wpctl present (volume keys)" '[[ -x /mnt/usr/bin/wpctl ]]'
vcheck "brightnessctl present"       '[[ -x /mnt/usr/bin/brightnessctl ]]'
vcheck "grim+slurp (screenshots)"    '[[ -x /mnt/usr/bin/grim && -x /mnt/usr/bin/slurp ]]'
vcheck "dunst (notifications)"       '[[ -x /mnt/usr/bin/dunst ]]'
vcheck "wlr-randr (panel scale)"     '[[ -x /mnt/usr/bin/wlr-randr ]]'
vcheck "pam_elogind wired up"        'grep -q pam_elogind /mnt/etc/pam.d/system-login'

echo
if (( vfail > 0 )); then
    warn "$vfail verification check(s) failed - DO NOT REBOOT yet"
    warn "The target is still mounted at /mnt for inspection."
    exit 1
fi

log "Done. $vfail failures."
note "The target is still mounted at /mnt."
note "To finish:  umount -R /mnt && cryptsetup close cryptroot && reboot"
echo
note "Still to do after first boot (not yet written):"
note "  - the dotfiles"
