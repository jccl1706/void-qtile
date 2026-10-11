"""
inputs - pointer and keyboard behaviour, Wayland only.

`wl_input_rules` is read only by the Wayland backend; under X11 the name is
simply unused, so this module defines it as None there rather than leaving it
undefined and making config.py test for it.

Device identifiers come from

    qtile cmd-obj -o core -f get_inputs

and the most specific matching key wins - so the "type:" entries here are
deliberate defaults that a per-device rule can override later without
disturbing them.
"""

from env import WAYLAND

if WAYLAND:
    from libqtile.backend.wayland import InputConfig

    wl_input_rules = {
        "type:touchpad": InputConfig(
            tap=True,
            natural_scroll=True,
            # dwt - disable while typing. Without it the heel of a hand moves
            # the cursor mid-sentence, which reads as the editor losing focus
            # at random.
            dwt=True,
            click_method="clickfinger",
            pointer_accel=0.3,
        ),
        "type:keyboard": InputConfig(
            kb_repeat_rate=40,
            kb_repeat_delay=250,
        ),
    }
else:
    wl_input_rules = None
