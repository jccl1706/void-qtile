"""
theme - colours and sizes, in one place so that changing them is one edit.

FONT SIZES ARE FOR AN UNSCALED HiDPI PANEL. This screen is 2256x1504 at 13
inches, about 200 DPI, so a 12pt font that is comfortable at 96 DPI is roughly
half the apparent size here. autostart.py asks wlr-randr for scale 1.5 and
tolerates failure, which means these numbers have to be legible WITHOUT it:
too large is a nuisance, too small is unusable.
"""

# Tokyo Night, as a placeholder that is at least coherent. The real palette
# comes when the desktop proper gets built.
BG = "#1a1b26"
FG = "#c0caf5"
ACCENT = "#7aa2f7"
MUTED = "#565f89"
WARN = "#ff9e64"
URGENT = "#f7768e"

FONT = "DejaVu Sans"
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
