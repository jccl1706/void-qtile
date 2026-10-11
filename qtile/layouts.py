"""
layouts - three, deliberately.

A sensible tiler, a main-plus-stack, and a plain maximised one. Enough to work
in without a guided tour of every layout qtile ships; more can be added once it
is clear which ones actually get used.
"""

from libqtile import layout
from libqtile.config import Match

from theme import LAYOUT_DEFAULTS

layouts = [
    layout.Columns(**LAYOUT_DEFAULTS, border_on_single=False),
    layout.MonadTall(**LAYOUT_DEFAULTS),
    layout.Max(**LAYOUT_DEFAULTS),
]

floating_layout = layout.Floating(
    **LAYOUT_DEFAULTS,
    float_rules=[
        # qtile's own defaults first - they catch the dialogs that must never
        # be tiled, and rewriting that list by hand is how a file picker ends
        # up as a tiled window.
        *layout.Floating.default_float_rules,
        Match(wm_class="confirmreset"),
        Match(wm_class="pavucontrol"),
        Match(title="branchdialog"),
        Match(title="pinentry"),
    ],
)
