"""
qtile configuration - void-qtile, Framework 13 AMD

THE ENTRY POINT ONLY. qtile reads this file and takes the module-level names it
recognises; everything of substance lives in a module beside it, mirroring how
niri is split across binds/apps/rules/layers/autostart in the sibling repo.

    env.py         the backend, the modifier, the terminal - imported by all
    theme.py       colours and sizes
    keys.py        keybindings
    groups.py      the nine workspaces and the keys that reach them
    layouts.py     layouts and the floating rules
    screens.py     the bar
    inputs.py      touchpad and keyboard, Wayland only
    autostart.py   hooks; imported for its side effects

A STARTING POINT, NOT A FINISHED DESKTOP. The aim is a config that boots to
something usable, with keys that already match the muscle memory from the other
machines here, so the work later is making it nice rather than making it work.

--- two things about splitting a qtile config ---

RELOADING NEEDS HELP, AND WITHOUT IT THE SPLIT IS A TRAP. Python caches
imported modules in sys.modules, so `lazy.reload_config()` re-executes THIS
file while the submodules keep the values they had at first import: the config
appears to reload and silently does not change. This is a known problem with
split qtile configs. The importlib.reload loop below is the fix, and it has to
run before the imports whose results are used.

`qtile check` ONLY COPIES config.py (qtile issue #2223), so it cannot see these
modules and its type checking will fail on them. That has no workaround; it
just means `qtile check` is less useful here than it would be on a single file.
Worth knowing before trusting a clean run of it.
"""

import importlib
import sys

# --- make a reload actually reload -------------------------------------------
#
# Every module of this config, dropped from the cache so the imports below
# re-execute their source rather than handing back a cached object from the
# previous load. Listed explicitly rather than discovered by globbing the
# directory, because a stray .py left beside the config should not become part
# of it by accident.
for _mod in ("env", "theme", "keys", "groups", "layouts", "screens",
             "inputs", "autostart"):
    if _mod in sys.modules:
        importlib.reload(sys.modules[_mod])

import autostart  # noqa: F401  - imported for the hooks it registers
import groups as _groups
import inputs as _inputs
import keys as _keys
import layouts as _layouts
import screens as _screens
import theme as _theme

# --- the names qtile looks for ------------------------------------------------

# The per-group bindings are generated from the group list, so they are
# assembled here rather than written out twice.
keys = _keys.keys + _groups.group_keys

groups = _groups.groups
layouts = _layouts.layouts
floating_layout = _layouts.floating_layout
screens = _screens.screens

widget_defaults = _theme.WIDGET_DEFAULTS
extension_defaults = _theme.WIDGET_DEFAULTS.copy()

wl_input_rules = _inputs.wl_input_rules

# THE CURSOR, AND IT HAS TO BE SET HERE - NOT IN THE ENVIRONMENT.
#
# qtile's Wayland core does
#
#     os.environ["XCURSOR_SIZE"] = str(self.qtile.config.wl_xcursor_size)
#
# at startup, so it OVERWRITES whatever the session exported. Setting
# XCURSOR_SIZE in .bash_profile looks correct, survives into the session's
# environment where it can be inspected, and is then silently replaced by
# qtile's own default of 24 before the cursor is ever drawn. Two different
# values were tried that way before reading the source.
#
# THE SIZE IS A PHYSICAL MEASUREMENT, NOT A PREFERENCE. wlroots asks the theme
# for size x output scale, so on this 1.5-scaled panel 28 means 42 real pixels.
#
# Adwaita - the only cursor theme a fresh Void install has - ships exactly TWO
# bitmap sizes, 24 and 72. At this scale that offers 36px or 72px and nothing
# between, and both were tried and rejected as too small and too large.
#
# Bibata ships 16, 28, 56 and 88, so 42px downscales cleanly from the 56
# bitmap instead of blowing up a 24. It is NOT packaged for Void and lives in
# ~/.local/share/icons, which means it does not survive a reinstall - the same
# situation as the Reversal icons on the Fedora machine. docs/CURSOR.md says
# how to put it back.
wl_xcursor_theme = "Bibata-Modern-Classic"
wl_xcursor_size = 28

# --- mouse --------------------------------------------------------------------

from libqtile.config import Click, Drag  # noqa: E402
from libqtile.lazy import lazy  # noqa: E402

from env import MOD  # noqa: E402

mouse = [
    Drag([MOD], "Button1", lazy.window.set_position_floating(),
         start=lazy.window.get_position()),
    Drag([MOD], "Button3", lazy.window.set_size_floating(),
         start=lazy.window.get_size()),
    Click([MOD], "Button2", lazy.window.bring_to_front()),
]

# --- the settings qtile asks for explicitly -----------------------------------

dgroups_key_binder = None
dgroups_app_rules = []
follow_mouse_focus = False          # focus follows intent, not the pointer
bring_front_click = "floating_only"
cursor_warp = False
auto_fullscreen = True
focus_on_window_activation = "urgent"
reconfigure_screens = True
auto_minimize = False

# qtile's Wayland backend starts XWayland on demand, which is wanted: X11-only
# applications should work without anybody thinking about it.
wmname = "LG3D"
