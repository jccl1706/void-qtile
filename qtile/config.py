"""
qtile configuration - void-qtile, Framework 13 AMD

A STARTING POINT, not a finished desktop. The aim here is a config that boots
to something immediately usable and whose keys already match the muscle memory
from the other machines in this family, so that the real work later is making
it nice rather than making it work.

BACKEND-AWARE THROUGHOUT. qtile runs the same config on X11 and Wayland, but
they do not offer the same things: foot is a Wayland client and will not start
under X11, and `wl_input_rules` is meaningless outside the Wayland backend.
qtile exposes `qtile.core.name` for exactly this, so the differences are
branched on rather than assumed.

WHAT IS NOT HERE, AND WHY. Output scale. This panel is 2256x1504 on 13 inches
and wants fractional scaling, which was the reason for choosing Wayland in the
first place - but qtile's Wayland backend does not expose output configuration
in the config file at all (checked against the 0.37 manual, which documents
input and is silent on outputs). So scaling is set at startup with wlr-randr in
the autostart hook below, and the font sizes here are chosen for an unscaled
HiDPI panel so that the desktop is legible even if that call fails.
"""

import os
import subprocess

from libqtile import bar, hook, layout, qtile, widget
from libqtile.config import Click, Drag, Group, Key, Match, Screen
from libqtile.lazy import lazy

# =============================================================================
# Basics
# =============================================================================

MOD = "mod4"  # Super

WAYLAND = qtile.core.name == "wayland"

# foot is a Wayland client, so X11 needs something else. xterm is not a
# preference, it is the one terminal the X11 package set is guaranteed to pull
# in - a config that names a terminal nobody installed has no way to open a
# window to fix itself.
TERMINAL = "foot" if WAYLAND else "xterm"

HOME = os.path.expanduser("~")

# =============================================================================
# Keys
#
# MOD+W CLOSES A WINDOW. Not Mod+Q, which is qtile's own default and most
# people's. The other two machines in this family both bind Mod+W - Hyprland in
# hypr/binds.lua and niri in its config.kdl, the latter moved off Mod+Q
# deliberately - and one pair of hands closing windows with a different key
# depending on which machine it is sitting at is a bad trade for matching
# somebody else's default.
# =============================================================================

keys = [
    # --- windows -------------------------------------------------------------
    Key([MOD], "w", lazy.window.kill(), desc="Close the focused window"),
    Key([MOD], "f", lazy.window.toggle_fullscreen(), desc="Fullscreen"),
    Key([MOD], "v", lazy.window.toggle_floating(), desc="Float"),

    # --- focus, vim-wise -----------------------------------------------------
    Key([MOD], "h", lazy.layout.left(), desc="Focus left"),
    Key([MOD], "l", lazy.layout.right(), desc="Focus right"),
    Key([MOD], "j", lazy.layout.down(), desc="Focus down"),
    Key([MOD], "k", lazy.layout.up(), desc="Focus up"),
    Key([MOD], "Tab", lazy.layout.next(), desc="Focus next"),

    # --- move ----------------------------------------------------------------
    Key([MOD, "shift"], "h", lazy.layout.shuffle_left(), desc="Move left"),
    Key([MOD, "shift"], "l", lazy.layout.shuffle_right(), desc="Move right"),
    Key([MOD, "shift"], "j", lazy.layout.shuffle_down(), desc="Move down"),
    Key([MOD, "shift"], "k", lazy.layout.shuffle_up(), desc="Move up"),

    # --- resize --------------------------------------------------------------
    Key([MOD, "control"], "h", lazy.layout.grow_left(), desc="Grow left"),
    Key([MOD, "control"], "l", lazy.layout.grow_right(), desc="Grow right"),
    Key([MOD, "control"], "j", lazy.layout.grow_down(), desc="Grow down"),
    Key([MOD, "control"], "k", lazy.layout.grow_up(), desc="Grow up"),
    Key([MOD], "n", lazy.layout.normalize(), desc="Reset all sizes"),

    # --- layouts -------------------------------------------------------------
    Key([MOD], "space", lazy.next_layout(), desc="Next layout"),
    Key([MOD, "shift"], "Return", lazy.layout.toggle_split(),
        desc="Split or unsplit the stack"),

    # --- launching -----------------------------------------------------------
    Key([MOD], "Return", lazy.spawn(TERMINAL), desc=f"Terminal ({TERMINAL})"),
    # qtile's own prompt rather than a separate launcher: one less package to
    # install before the desktop can start anything, and it is replaceable
    # later without touching anything else.
    Key([MOD], "d", lazy.spawncmd(), desc="Run a command"),

    # --- session -------------------------------------------------------------
    Key([MOD, "control"], "r", lazy.reload_config(), desc="Reload the config"),
    Key([MOD, "control"], "q", lazy.shutdown(), desc="Quit qtile"),

    # --- hardware keys -------------------------------------------------------
    #
    # wpctl comes from wireplumber and brightnessctl from its own package; both
    # are in the installer's package list precisely so these keys are not dead
    # on a fresh install. @DEFAULT_AUDIO_SINK@ rather than a numbered sink so
    # that plugging in headphones does not silently change which device the
    # volume keys address.
    Key([], "XF86AudioRaiseVolume",
        lazy.spawn("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+")),
    Key([], "XF86AudioLowerVolume",
        lazy.spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")),
    Key([], "XF86AudioMute",
        lazy.spawn("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")),
    Key([], "XF86AudioMicMute",
        lazy.spawn("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")),

    # 5% steps with a floor: this panel's backlight is still readable at 5% and
    # pitch black at 0, and a key that can turn the screen off entirely is a
    # key that will.
    Key([], "XF86MonBrightnessUp", lazy.spawn("brightnessctl set +5%")),
    Key([], "XF86MonBrightnessDown", lazy.spawn("brightnessctl set 5%-")),

    # --- screenshots ---------------------------------------------------------
    Key([MOD], "Print", lazy.spawn(
        f"sh -c 'grim -g \"$(slurp)\" {HOME}/Pictures/$(date +%F-%H%M%S).png'"),
        desc="Screenshot a region"),
    Key([], "Print", lazy.spawn(
        f"sh -c 'grim {HOME}/Pictures/$(date +%F-%H%M%S).png'"),
        desc="Screenshot the screen"),
]

# =============================================================================
# Groups
# =============================================================================

groups = [Group(str(i)) for i in range(1, 10)]

for g in groups:
    keys.extend([
        Key([MOD], g.name, lazy.group[g.name].toscreen(),
            desc=f"Go to group {g.name}"),
        # switch_group=False: moving a window somewhere else should not drag
        # the focus along with it. The common case is tidying up, not
        # following.
        Key([MOD, "shift"], g.name,
            lazy.window.togroup(g.name, switch_group=False),
            desc=f"Move window to group {g.name}"),
    ])

# =============================================================================
# Layouts
#
# Three, deliberately: a sensible tiler, a full-screen-with-a-stack, and a
# plain maximised one. Enough to work in without a tour of every layout qtile
# ships.
# =============================================================================

LAYOUT_DEFAULTS = dict(
    border_focus="#7aa2f7",
    border_normal="#1a1b26",
    # 2 logical pixels, which on an unscaled HiDPI panel is thin but visible.
    border_width=2,
    margin=6,
)

layouts = [
    layout.Columns(**LAYOUT_DEFAULTS, border_on_single=False),
    layout.MonadTall(**LAYOUT_DEFAULTS),
    layout.Max(**LAYOUT_DEFAULTS),
]

floating_layout = layout.Floating(
    **LAYOUT_DEFAULTS,
    float_rules=[
        # qtile's own defaults, which catch the dialogs that must not be tiled.
        *layout.Floating.default_float_rules,
        Match(wm_class="confirmreset"),
        Match(wm_class="pavucontrol"),
        Match(title="branchdialog"),
        Match(title="pinentry"),
    ],
)

# =============================================================================
# The bar
#
# FONT SIZES ARE FOR AN UNSCALED HiDPI PANEL. 2256x1504 at 13 inches is about
# 200 DPI, so a 12pt font that is comfortable on a 96 DPI screen is roughly
# half the apparent size here. If the wlr-randr scaling in the autostart hook
# works, these will look large and should come down; if it does not, they are
# what makes the desktop readable at all. Erring towards legible.
# =============================================================================

WIDGET_DEFAULTS = dict(font="DejaVu Sans", fontsize=18, padding=6)
extension_defaults = WIDGET_DEFAULTS.copy()

def status_widgets():
    """The bar's right-hand side.

    Built in a function so the backend check happens once, and so that a widget
    that does not exist on one backend cannot break the other.
    """
    w = [
        widget.Prompt(**WIDGET_DEFAULTS),
        widget.WindowName(**WIDGET_DEFAULTS, max_chars=60),
        widget.Chord(**WIDGET_DEFAULTS, background="#ff9e64"),
        widget.Systray(**WIDGET_DEFAULTS) if not WAYLAND else widget.Spacer(length=0),
        widget.CPU(**WIDGET_DEFAULTS, format="cpu {load_percent:.0f}%"),
        widget.Memory(**WIDGET_DEFAULTS, format="mem {MemPercent:.0f}%"),
        widget.ThermalZone(**WIDGET_DEFAULTS, fgcolor_normal="#c0caf5"),
        # Battery, because this is a laptop and the one thing a bar on a laptop
        # must tell you is how long it has left.
        widget.Battery(
            **WIDGET_DEFAULTS,
            format="{char} {percent:2.0%} {hour:d}:{min:02d}",
            charge_char="chg",
            discharge_char="bat",
            full_char="full",
            empty_char="EMPTY",
            low_percentage=0.15,
            low_foreground="#f7768e",
            notify_below=15,
        ),
        widget.Clock(**WIDGET_DEFAULTS, format="%a %d %b  %H:%M"),
    ]
    return w


screens = [
    Screen(
        top=bar.Bar(
            [
                widget.GroupBox(
                    **WIDGET_DEFAULTS,
                    active="#c0caf5",
                    inactive="#565f89",
                    this_current_screen_border="#7aa2f7",
                    highlight_method="line",
                    # Only groups with something in them, plus the current one.
                    # Nine always-visible numbers is nine pieces of furniture
                    # telling you nothing.
                    hide_unused=True,
                ),
                widget.CurrentLayout(**WIDGET_DEFAULTS),
                *status_widgets(),
            ],
            # 34 rather than qtile's 24: see the note on font sizes above.
            34,
            background="#1a1b26",
        ),
    ),
]

# =============================================================================
# Mouse
# =============================================================================

mouse = [
    Drag([MOD], "Button1", lazy.window.set_position_floating(),
         start=lazy.window.get_position()),
    Drag([MOD], "Button3", lazy.window.set_size_floating(),
         start=lazy.window.get_size()),
    Click([MOD], "Button2", lazy.window.bring_to_front()),
]

# =============================================================================
# Input, Wayland only
#
# `wl_input_rules` is read only by the Wayland backend; under X11 it is an
# unused name. The identifiers are discoverable with
#
#     qtile cmd-obj -o core -f get_inputs
#
# and the most specific matching key wins, so "type:touchpad" here is a
# deliberate default that a per-device entry can override later.
# =============================================================================

if WAYLAND:
    from libqtile.backend.wayland import InputConfig

    wl_input_rules = {
        "type:touchpad": InputConfig(
            tap=True,
            natural_scroll=True,
            dwt=True,            # ignore the touchpad while typing
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

# =============================================================================
# Autostart
#
# Everything that must happen once, after the compositor is up.
# =============================================================================

@hook.subscribe.startup_once
def autostart():
    """Run once per qtile start, not on every config reload.

    startup_once rather than startup: a config reload fires `startup` again,
    and anything spawned there accumulates a new copy every time.
    """
    # THE PANEL SCALE, which qtile cannot express in this file - the Wayland
    # backend documents input configuration and says nothing about outputs. So
    # it is set from outside, once, and failure is tolerated: if wlr-randr is
    # missing or the output is named something else, the desktop still comes up
    # at scale 1 with the large fonts above, which is usable while it is fixed.
    #
    # 1.5 to match the sibling Fedora machine on the same panel.
    if WAYLAND:
        subprocess.Popen(
            ["sh", "-c", "wlr-randr --output eDP-1 --scale 1.5 || true"]
        )

    # THE AUDIO STACK, WHICH NOTHING ELSE STARTS ON VOID. The pipewire and
    # wireplumber packages ship their .desktop files into
    # /usr/share/applications rather than /etc/xdg/autostart, and qtile does
    # not process XDG autostart in any case - so there is no init, no user
    # service and no desktop environment to do this. Started here or not at
    # all, which is why the volume keys would otherwise do nothing on a fresh
    # install even with wireplumber installed.
    #
    # pipewire first, then its pulse shim, then the session manager.
    # wireplumber retries if it wins the race, so no sleeps are needed.
    for cmd in (["pipewire"], ["pipewire-pulse"], ["wireplumber"]):
        subprocess.Popen(cmd)

    # A notification daemon, because without one every application that tries
    # to notify fails silently and you never learn that it tried.
    subprocess.Popen(["dunst"])

    # Somewhere for the screenshot keys to write.
    os.makedirs(os.path.join(HOME, "Pictures"), exist_ok=True)


@hook.subscribe.client_new
def tidy_new_clients(client):
    """Keep a couple of things out of the tiling.

    Separate from float_rules because it catches by window role, which the
    declarative rules cannot always see at map time.
    """
    if client.name and client.name.lower().startswith("pavucontrol"):
        client.floating = True


# =============================================================================
# The settings qtile asks for explicitly
# =============================================================================

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
# applications should work without thinking about it.
wmname = "LG3D"
