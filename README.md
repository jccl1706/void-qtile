# void-qtile

Void Linux on the Framework 13 AMD (Ryzen 7040): GRUB + LUKS + btrfs, runit
instead of systemd, qtile as the window manager.

This is the third machine build in this family, after `fd44_hyprdot` (Fedora,
Hyprland and niri) and `fd44_nixos`. Those two differ in distribution; this one
differs in **init**, which turns out to be where most of the work is.

## Why these choices

**runit, not systemd.** The stated point of the project. It means no
`systemd-logind`, so seats and sessions come from `elogind` or `seatd`; no
`systemd-boot`, hence GRUB; no `.service` units, so every service is a
`/etc/sv/<name>` directory symlinked into `/etc/runit/runsvdir/default/`.

**GRUB.** Required once systemd-boot is off the table, and it brings one hard
constraint - see *The encryption decision* below.

**qtile, and on Wayland.** The deciding factor is the panel: 2256x1504 on 13
inches needs fractional scaling, and X11 offers integer scaling or `Xft.dpi`
guesswork that half the toolkits ignore. Void builds qtile with
`--config-setting backend=wayland` already, so there is nothing to compile.
qtile is ONE package containing BOTH backends, so falling back to X11 is a
different startup command rather than a reinstall - which is what makes
starting on Wayland a cheap bet rather than a commitment.

The honest caveat: qtile rewrote its Wayland backend in C for 0.34.0 and now
tracks wlroots closely, but the project's own "Current Wayland Situation" page
does not enumerate what works and what does not - it points at a GitHub board.
Nobody is publicly claiming parity with X11, so neither is this README.

## Is the hardware up to it? Yes

Nothing here is exotic. Verified against `void-packages` on 2026-10-10:

| piece | Void version | note |
| --- | --- | --- |
| `linux` | 6.18 | this silicon shipped 2023 and wants ~6.5+; ample |
| `qtile` | 0.37.1 | current release, built with the Wayland backend |
| `wlroots` | 0.20 | |
| `grub` | 2.12 | `grub-x86_64-efi` is a subpackage |
| `cryptsetup` | 2.8.8 | |
| `btrfs-progs` | 6.11 | |
| `dracut` | 112 | builds the LUKS+btrfs initramfs |
| `elogind` | 252.39 | seats and sessions without systemd |
| `seatd` | 0.9.3 | the lighter alternative to elogind |
| `polkit` | 127 | |
| `pipewire` | 1.6.9 | |

**Wi-Fi** is a MediaTek MT7922 (RZ616) on the in-kernel `mt7921e` driver plus
`linux-firmware`. It works, with one adjustment to make from the start:
**disable wifi power saving**, which is the documented fix for MT7921/7922
dropout instability. The GPU needs `linux-firmware-amd`.

## Machine-specific facts this build must respect

**The front-right expansion bay does not enumerate a USB device at boot.**
Proven on this machine 2026-10-10: a card there logs `Cannot enable. Maybe the
USB cable is bad?` four times and gives up, every boot, and no software reset
recovers it - only a physical replug. Keep a passive USB-C card in that bay.
The two rear bays are the USB4 ones.

**No hibernation.** Resume is unreliable on Framework AMD hardware and the
decision to leave it out has been taken deliberately, twice, on other installs.
No swap partition, no `resume=`. zram is the memory valve - and it must
actually be installed, which is a mistake already made once elsewhere.

## The encryption decision

GRUB 2.12 - the version Void ships - supports LUKS2 **only with PBKDF2**.
Argon2id support arrived in GRUB 2.14. So "GRUB + LUKS" is really a choice:

- **unencrypted `/boot`**, LUKS2 + argon2id for root, dracut does the unlock.
  GRUB never touches LUKS, so its version constrains nothing, and the strongest
  KDF is kept. One password prompt.
- **encrypted `/boot`**, which forces LUKS2+PBKDF2 or LUKS1 - a weaker,
  non-memory-hard KDF - and a second password prompt unless a keyfile is baked
  into the initramfs.

Note while weighing it: **Secure Boot is disabled on this machine.** An
attacker with physical access can replace the bootloader regardless, so
encrypting `/boot` raises the effort of an evil-maid attack without preventing
it, while the weaker KDF is a real and permanent cost against offline brute
force.

**Decided: unencrypted `/boot`, LUKS2 + argon2id.** Secure Boot is disabled on
this machine, so an attacker with physical access can replace the bootloader
either way - encrypting `/boot` raises the effort of an evil-maid attack
without preventing it, and PBKDF2 would be a permanent cost against the threat
that actually applies to a laptop, which is theft. One prompt, strongest KDF.

## No LVM, and why

The Fedora machine runs `LUKS2 -> LVM -> one logical volume filling the whole
group -> btrfs`. That LVM layer holds exactly one volume and buys nothing
today; it exists for the option of adding more later.

btrfs subvolumes already do that job, and better: they share free space instead
of needing sizes decided in advance, and their snapshots are more capable than
LVM's. The one thing LVM would genuinely add is an encrypted swap volume inside
the same container, unlocked by the same passphrase - which is how hibernation
would work, and hibernation is deliberately off here.

So the layout is:

```
nvme0n1p1   1G     vfat     /boot/efi    ESP
nvme0n1p2   1G     ext4     /boot        kernel + initramfs, plain
nvme0n1p3   rest   LUKS2    argon2id
            \-- btrfs   @root  @home  @snapshots
```

## elogind, not seatd - and not by preference

`seatd` is the smaller daemon and the better fit for runit's philosophy, but in
Void both `polkit` and `xdg-desktop-portal-wlr` **depend on elogind**. Since
this build wants polkit (mounting, privileged actions) and the portal (screen
sharing, file pickers), elogind is installed either way. Running seatd next to
an installed-but-idle elogind is the worst of both, so elogind it is.
