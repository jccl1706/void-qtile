"""
keys - the keybindings, except the per-group ones, which live in groups.py
because they are generated from the group list.

MOD+W CLOSES A WINDOW. Not Mod+Q, which is qtile's own default. Both the other
machines in this family bind Mod+W - Hyprland in hypr/binds.lua, and niri moved
off Mod+Q deliberately to match it - and one pair of hands closing windows with
a different key depending on which machine it is sitting at is a bad trade for
agreeing with somebody else's default.
"""

from libqtile.config import Key
from libqtile.lazy import lazy

from env import BROWSER, HOME, MOD, TERMINAL

keys = [
    # --- windows -------------------------------------------------------------
    Key([MOD], "w", lazy.window.kill(), desc="Close the focused window"),
    Key([MOD], "f", lazy.window.toggle_fullscreen(), desc="Fullscreen"),
    Key([MOD], "v", lazy.window.toggle_floating(), desc="Float"),

    # --- focus, move and resize, ALL ON THE ARROW KEYS -----------------------
    #
    # qtile's own default is h/j/k/l, and so was this config until it was
    # actually used. The arrows say which direction they mean without being
    # learned, and nothing else here needs them.
    #
    # One scheme, three modifiers, so the shape is worth stating once:
    #
    #     Mod              move the FOCUS
    #     Mod + Shift      move the WINDOW
    #     Mod + Control    GROW the window
    #
    # h/j/k/l are now unbound and free for anything else.
    Key([MOD], "Left", lazy.layout.left(), desc="Focus left"),
    Key([MOD], "Right", lazy.layout.right(), desc="Focus right"),
    Key([MOD], "Down", lazy.layout.down(), desc="Focus down"),
    Key([MOD], "Up", lazy.layout.up(), desc="Focus up"),
    Key([MOD], "Tab", lazy.layout.next(), desc="Focus next"),

    # --- move ----------------------------------------------------------------
    Key([MOD, "shift"], "Left", lazy.layout.shuffle_left(), desc="Move left"),
    Key([MOD, "shift"], "Right", lazy.layout.shuffle_right(), desc="Move right"),
    Key([MOD, "shift"], "Down", lazy.layout.shuffle_down(), desc="Move down"),
    Key([MOD, "shift"], "Up", lazy.layout.shuffle_up(), desc="Move up"),

    # --- resize --------------------------------------------------------------
    #
    # WHICH OF THESE FOUR DO ANYTHING DEPENDS ON THE LAYOUT. Columns treats
    # left/right as column width and up/down as height within a column;
    # MonadTall really only has a main pane to grow, so two of the four appear
    # dead there. That is the layout, not a missing binding.
    Key([MOD, "control"], "Left", lazy.layout.grow_left(), desc="Grow left"),
    Key([MOD, "control"], "Right", lazy.layout.grow_right(), desc="Grow right"),
    Key([MOD, "control"], "Down", lazy.layout.grow_down(), desc="Grow down"),
    Key([MOD, "control"], "Up", lazy.layout.grow_up(), desc="Grow up"),
    Key([MOD], "n", lazy.layout.normalize(), desc="Reset all sizes"),

    # --- layouts -------------------------------------------------------------
    Key([MOD], "space", lazy.next_layout(), desc="Next layout"),
    Key([MOD, "shift"], "Return", lazy.layout.toggle_split(),
        desc="Split or unsplit the stack"),

    # --- launching -----------------------------------------------------------
    Key([MOD], "Return", lazy.spawn(TERMINAL), desc=f"Terminal ({TERMINAL})"),
    Key([MOD], "b", lazy.spawn(BROWSER), desc=f"Browser ({BROWSER})"),
    # qtile's own prompt rather than a separate launcher: one less package
    # needed before the desktop can start anything, and replaceable later
    # without touching anything else.
    Key([MOD], "d", lazy.spawncmd(), desc="Run a command"),

    # --- session -------------------------------------------------------------
    Key([MOD, "control"], "r", lazy.reload_config(), desc="Reload the config"),
    Key([MOD, "control"], "q", lazy.shutdown(), desc="Quit qtile"),

    # --- hardware keys -------------------------------------------------------
    #
    # wpctl comes from wireplumber, brightnessctl from its own package, and both
    # are in the installer's list precisely so these are not dead keys on a
    # fresh install. @DEFAULT_AUDIO_SINK@ rather than a numbered sink, so that
    # plugging in headphones does not silently change which device these
    # address.
    Key([], "XF86AudioRaiseVolume",
        lazy.spawn("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+")),
    Key([], "XF86AudioLowerVolume",
        lazy.spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")),
    Key([], "XF86AudioMute",
        lazy.spawn("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")),
    Key([], "XF86AudioMicMute",
        lazy.spawn("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")),

    # A floor of 5% rather than steps down to nothing: this panel is still
    # readable at 5% and pitch black at 0, and a key that can turn the screen
    # off entirely is a key that will.
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
