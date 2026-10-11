"""
groups - the nine workspaces and the keys that reach them.

Kept with the groups rather than in keys.py because the bindings are GENERATED
from the group list: splitting them would mean two places to edit to add a
tenth workspace, which is how the two drift apart.
"""

from libqtile.config import Group, Key
from libqtile.lazy import lazy

from env import MOD

groups = [Group(str(i)) for i in range(1, 10)]

group_keys = []
for _g in groups:
    group_keys.extend([
        Key([MOD], _g.name, lazy.group[_g.name].toscreen(),
            desc=f"Go to group {_g.name}"),
        # switch_group=False: sending a window elsewhere should not drag the
        # focus after it. The common case is tidying up, not following.
        Key([MOD, "shift"], _g.name,
            lazy.window.togroup(_g.name, switch_group=False),
            desc=f"Move window to group {_g.name}"),
    ])
