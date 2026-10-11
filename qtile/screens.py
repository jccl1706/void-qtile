"""
screens - the bar.

The widget list is built in a function so that a widget which does not exist on
one backend cannot break the other: Systray is X11-only, and on Wayland it has
to be left out rather than merely misconfigured.
"""

from libqtile import bar, widget
from libqtile.config import Screen

from env import WAYLAND
from theme import (ACCENT, BAR_HEIGHT, BG, FG, MUTED, URGENT, WARN,
                   WIDGET_DEFAULTS)


def status_widgets():
    """Everything right of the layout indicator."""
    return [
        widget.Prompt(**WIDGET_DEFAULTS),
        widget.WindowName(**WIDGET_DEFAULTS, max_chars=60),
        widget.Chord(**WIDGET_DEFAULTS, background=WARN),
        # SYSTRAY IS X11-ONLY. On Wayland it does not merely look wrong, it
        # raises - so the slot is filled with nothing rather than conditionally
        # appended, which keeps the list readable.
        widget.Systray(**WIDGET_DEFAULTS) if not WAYLAND
        else widget.Spacer(length=0),
        widget.CPU(**WIDGET_DEFAULTS, format="cpu {load_percent:.0f}%"),
        widget.Memory(**WIDGET_DEFAULTS, format="mem {MemPercent:.0f}%"),
        widget.ThermalZone(**WIDGET_DEFAULTS, fgcolor_normal=FG),
        # The one thing a bar on a laptop must tell you is how long it has
        # left, so this reports time remaining and not just a percentage.
        widget.Battery(
            **WIDGET_DEFAULTS,
            format="{char} {percent:2.0%} {hour:d}:{min:02d}",
            charge_char="chg",
            discharge_char="bat",
            full_char="full",
            empty_char="EMPTY",
            low_percentage=0.15,
            low_foreground=URGENT,
            notify_below=15,
        ),
        widget.Clock(**WIDGET_DEFAULTS, format="%a %d %b  %H:%M"),
    ]


screens = [
    Screen(
        top=bar.Bar(
            [
                widget.GroupBox(
                    **WIDGET_DEFAULTS,
                    active=FG,
                    inactive=MUTED,
                    this_current_screen_border=ACCENT,
                    highlight_method="line",
                    # Only groups with something in them, plus the current one.
                    # Nine permanent numbers are nine pieces of furniture
                    # telling you nothing.
                    hide_unused=True,
                ),
                widget.CurrentLayout(**WIDGET_DEFAULTS),
                *status_widgets(),
            ],
            BAR_HEIGHT,
            background=BG,
        ),
    )
]
