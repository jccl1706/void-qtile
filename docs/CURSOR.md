# The cursor

Set in `qtile/config.py`, not in the environment:

```python
wl_xcursor_theme = "Bibata-Modern-Classic"
wl_xcursor_size = 28
```

## Why not XCURSOR_SIZE

Because qtile overwrites it. Its Wayland core runs

```python
os.environ["XCURSOR_SIZE"] = str(self.qtile.config.wl_xcursor_size)
```

at startup, so anything the session exported is replaced before a cursor is
drawn. Exporting `XCURSOR_SIZE` from `.bash_profile` looks correct, survives
into the environment where it can be inspected with `tr '\0' '\n' <
/proc/PID/environ`, and does nothing at all.

## Why 28

**The number is a physical measurement.** wlroots asks the theme for
`size x output scale`, and this panel runs at scale 1.5 — so 28 means **42 real
pixels**.

A cursor theme is a set of fixed bitmaps, not a scalable drawing. Asking for a
size the theme does not have means scaling the nearest one, and scaling *up*
looks soft.

| theme | bitmap sizes | usable at scale 1.5 |
| --- | --- | --- |
| Adwaita | 24, 72 | 36px or 72px, nothing between |
| Bibata | 16, 28, 56, 88 | 24px, 42px, 84px, 132px |

Adwaita is the only cursor theme a fresh Void install has, and at this scale it
offers exactly two choices — both of which were tried and rejected, one too
small and one too large. Bibata's 56px bitmap downscales to 42 cleanly.

## Installing the theme

**Bibata is not packaged for Void** and lives in `~/.local/share/icons`, so it
does not survive a reinstall — the same situation as the Reversal icons on the
Fedora machine.

```sh
curl -fsSLO https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Classic.tar.xz
tar -xJf Bibata-Modern-Classic.tar.xz -C ~/.local/share/icons/
```

`xz` must be installed for that to work — `base-system` does not include it,
and without it tar fails with `xz: Cannot exec` rather than saying what is
missing.

## Changing it

Every change needs the session restarted; the Wayland backend cannot reload a
cursor in place, and `qtile restart` does not exist on it at all.

```sh
qtile/reload.sh
```

Useful values on this panel, all downscaling the 56px bitmap rather than
inflating the 28:

| `wl_xcursor_size` | physical |
| --- | --- |
| 24 | 36px |
| 28 | 42px — current |
| 32 | 48px |
| 36 | 54px |
