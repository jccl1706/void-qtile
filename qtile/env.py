"""
env - what the rest of the config needs to know before it can decide anything.

Imported first by everything else, and deliberately imports nothing from this
package in return: it is the bottom of the dependency graph, which is what
keeps the module layout acyclic.
"""

import os

from libqtile import qtile

# THE BACKEND, decided once here rather than tested in five places. qtile runs
# the same config on X11 and Wayland but they do not offer the same things, so
# the difference has to be visible to every module that cares.
WAYLAND = qtile.core.name == "wayland"

MOD = "mod4"  # Super

# foot is a Wayland client and will not start under X11. xterm is not a
# preference, it is the one terminal the X11 package set is certain to pull in -
# and a config naming a terminal nobody installed has no way to open a window
# to fix itself.
TERMINAL = "foot" if WAYLAND else "xterm"

HOME = os.path.expanduser("~")
PICTURES = os.path.join(HOME, "Pictures")
