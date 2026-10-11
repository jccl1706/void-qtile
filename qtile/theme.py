"""
theme - reads the palette from themes/<name>.conf.

THE PALETTE IS NOT IN THIS FILE. It lives in themes/nord.conf, which is also
what bin/theme.sh reads to generate the foot, dunst and GTK configs - those
three cannot parse anything but their own syntax, so they are generated. qtile
can read the file itself, so it does, and there is one fewer generated file to
keep honest.

Which theme is current is a single word in
~/.local/state/void-qtile/theme, written by `bin/theme.sh set`. If that file
is absent the default below is used, so a fresh checkout works before
theme.sh has ever run.

IT PARSES RATHER THAN EXECUTES. The .conf is key=value and nothing else: a
palette that can run code is a palette that has to be trusted, and this one is
read by both bash and Python.

FONT SIZES ARE FOR AN UNSCALED HiDPI PANEL. This screen is 2256x1504 at 13
inches, about 200 DPI. autostart.py asks wlr-randr for scale 1.5 and tolerates
failure, so these have to stay legible WITHOUT it.
"""

import os
import re
from pathlib import Path

DEFAULT_THEME = "nord"

_REPO = Path(__file__).resolve().parent.parent
_STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "void-qtile"

_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _current_name() -> str:
    try:
        name = (_STATE / "theme").read_text().strip()
        return name or DEFAULT_THEME
    except OSError:
        return DEFAULT_THEME


def _load(name: str) -> dict:
    """Read themes/<name>.conf into a dict. Comments and blanks are skipped."""
    path = _REPO / "themes" / f"{name}.conf"
    if not path.is_file() and name != DEFAULT_THEME:
        path = _REPO / "themes" / f"{DEFAULT_THEME}.conf"
    out = {}
    try:
        text = path.read_text()
    except OSError:
        return out
    for line in text.splitlines():
        # ONLY WHOLE-LINE COMMENTS. Stripping from the first '#' anywhere
        # would eat every colour in the file - `bg=#2e3440` becomes `bg=`,
        # and the result is a palette of empty strings that themes everything
        # black without erroring. The .conf format has no inline comments
        # precisely so this stays simple.
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        if _KEY.match(key):
            out[key] = value.strip()
    return out


_P = _load(_current_name())


def _c(key: str, fallback: str) -> str:
    """A colour, with a fallback so a missing key cannot stop qtile starting.

    A config that raises on a typo in a palette file takes the whole session
    down into a login loop; one that falls back renders slightly wrong and
    stays usable, which is the better failure for a colour.
    """
    return _P.get(key, fallback)


# --- what this config refers to ----------------------------------------------

BG = _c("bg", "#2e3440")
SURFACE = _c("surface", "#3b4252")
SURFACE_HIGH = _c("surfaceHigh", "#434c5e")
MUTED = _c("dim", "#4c566a")
FG = _c("fg", "#d8dee9")
FG_BRIGHT = _c("fgBright", "#eceff4")

ACCENT = _c("accent", "#88c0d0")
ACCENT_DIM = _c("accentDim", "#5e81ac")
ACCENT_FG = _c("accentFg", "#2e3440")

OK = _c("ok", "#a3be8c")
WARN = _c("warn", "#ebcb8b")
URGENT = _c("danger", "#bf616a")

THEME_NAME = _P.get("name", DEFAULT_THEME)

# Read by autostart.py, which pushes them into gsettings - see the note there
# for why settings.ini alone is not enough.
GTK_THEME = _P.get("gtk_theme", "Adwaita-dark")
CURSOR_THEME = _P.get("cursor_theme", "Adwaita")
CURSOR_SIZE = int(_P.get("cursor_size", "24") or 24)

# --- sizes -------------------------------------------------------------------

FONT = _P.get("font", "DejaVu Sans")
FONTSIZE = 18
PADDING = 6

BAR_HEIGHT = 34
BORDER_WIDTH = 2
MARGIN = 6

WIDGET_DEFAULTS = dict(font=FONT, fontsize=FONTSIZE, padding=PADDING)

LAYOUT_DEFAULTS = dict(
    border_focus=ACCENT,
    border_normal=BG,
    border_width=BORDER_WIDTH,
    margin=MARGIN,
)
