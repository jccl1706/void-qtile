# Deploying to the Framework 13 AMD

This installs over whatever is on the laptop. Everything on that disk is gone.
The steps below are in the order that makes a mistake survivable rather than
the order that gets to the install fastest.

Written after the installer reached 112/112 checks in a VM and booted to a
working qtile session. **None of it has run on this hardware yet**, and the
section *What has never been tested here* is the honest list of why that
matters.

---

## Before anything

### 1. A backup that has been restored, not just taken

```sh
bin/backup.sh run            # from fd44_hyprdot
bin/backup.sh verify         # restores it and compares - do NOT skip
```

`verify` is the step that separates a backup from a hope. The repos are the
easy part and they are already on GitHub; what lives only on this laptop is

- `~/.claude` — every session transcript, including the one that built this
- `~/.ssh` — nine private keys, all passphrase-protected
- `~/.config/gh/hosts.yml` — the GitHub token
- `~/Pictures`, `~/Work/debian-xfce4`, `~/Work/t480-gentoo` — not git repos

### 2. Everything pushed

```sh
for r in fd44_hyprdot fd44_nixos void-qtile; do
    git -C ~/Work/$r status --porcelain | head -1
    git -C ~/Work/$r log --oneline @{u}.. | head -1
done
```

Both should print nothing for all three.

### 3. The repo onto the USB stick

**`void-qtile` is a private repo and a live ISO cannot clone it** — no
credentials, no `gh`, no browser. The installer refuses to start without its
nine qtile modules (preflight checks for them), so the repo has to travel with
the ISO:

```sh
# after writing the ISO, with the stick still mounted
cp -r ~/Work/void-qtile /run/media/$USER/<stick>/
```

Alternatively make the repo public for the duration, which is a decision about
the repo rather than a convenience.

### 4. The ISO, verified

```sh
curl -fsSLO https://repo-default.voidlinux.org/live/current/void-live-x86_64-20250202-base.iso
curl -fsSL  https://repo-default.voidlinux.org/live/current/sha256sum.txt | grep base.iso
sha256sum void-live-x86_64-20250202-base.iso
```

They must match. Then write it with `dd` to the stick.

---

## Which bay the stick goes in

**NOT THE FRONT-RIGHT BAY.** That bay does not enumerate a USB device at boot
on this machine — proven 2026-10-10, four `Cannot enable. Maybe the USB cable
is bad?` messages and then silence, every boot, with no software reset able to
recover it. An installer on a stick in that bay simply will not be seen.

Use a rear bay. The current layout is in
`~/.claude/.../memory/framework-usb-ethernet-slot.md`:

| bay | normally holds |
| --- | --- |
| rear-left | USB-C, the charger |
| rear-right | HDMI |
| front-left | ethernet |
| front-right | USB-C — the defective one |

---

## The install

### 5. Preflight only — touches nothing

```sh
cd /path/to/void-qtile
./install/install_void.sh --preflight
```

15 checks plus every package name resolved against the repo. If the live ISO
is older than the repo, `xbps-install` refuses everything until it updates
itself, so do that first:

```sh
xbps-install -uy xbps
```

### 6. Dry run — still touches nothing

```sh
./install/install_void.sh --dry-run --disk /dev/nvme0n1
```

Read what it says it would write. Specifically check that the partitions it
names are `nvme0n1p1`, `nvme0n1p2`, `nvme0n1p3` and **not** `nvme0n11`.

### 7. The real thing

```sh
./install/install_void.sh --disk /dev/nvme0n1 \
    --authorized-key /path/to/id_ed25519.pub
```

It asks for the disk name back before wiping. The LUKS passphrase and both
account passwords are typed at the console — `--passphrase-file` and
`--password-file` exist for automated testing and should not be used here.

`--authorized-key` is worth the trouble: it makes the machine reachable over
ssh from its first boot, which is exactly what you want if the desktop does not
start. Without it, a broken session means no way in at all.

### 8. Before rebooting

The installer refuses to say "Done" if any of its 112 checks fail, and leaves
the target mounted at `/mnt` for inspection. If it did say Done:

```sh
umount -R /mnt && cryptsetup close cryptroot && reboot
```

---

## After the first boot

```
LUKS passphrase at the dracut prompt     one prompt, not two
autologin on tty1 only                   loginctl list-sessions
qtile starts                             pgrep -f "qtile start"
a wayland socket                         ls /run/user/1000/wayland-0
DNS                                      getent hosts voidlinux.org
sudo                                     sudo true
```

If qtile does not start, the reason is in `~/.local/share/qtile/qtile.log`,
NOT on the console — the session's own output goes to
`~/.local/state/session.log`, which will only show repeated headers. The
renderer errors look like EGL problems and usually are not.

---

## What has never been tested here

Everything below worked in a VM and has never run on this hardware.

**nvme partition naming.** The VM presented `/dev/vda`, which takes the
`sd`-style branch. This machine is `nvme0n1` and takes the `p`-suffixed one.
That branch has only ever been exercised by `--dry-run`, which does not call
`sfdisk`. It is the single step that writes to the disk, so read step 6's
output carefully.

**amdgpu.** The VM used `virtio-vga-gl`; radeonsi out of `mesa-dri` is a
different driver path. Mesa being installed at all was the bug that stopped
the desktop starting in the VM, so the package is right — whether it is
sufficient for this GPU is unproven.

**The panel scale.** `autostart.py` runs
`wlr-randr --output eDP-1 --scale 1.5`, and **`eDP-1` is a guess**. If the
output is named something else the call fails silently and the desktop comes up
at scale 1 — legible, because the fonts are sized for that, but not right.
Check with `wlr-randr` and correct `qtile/autostart.py`.

**MT7922 wifi.** `wifi.powersave = 2` is written but never exercised.

**zram and earlyoom** are sized for 54 GiB of RAM; the VM had 8.

**Hibernation stays off.** No swap partition, no `resume=`. That is deliberate
on this hardware and is not an incomplete install.
