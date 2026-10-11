"""
autostart - the hooks.

Importing this module registers them; config.py imports it for that side effect
alone, which is why it exports nothing.
"""

import os
import subprocess

from libqtile import hook

from env import PICTURES, WAYLAND


@hook.subscribe.startup_once
def _autostart():
    """Once per qtile start, not once per config reload.

    startup_once rather than startup: a reload fires `startup` again, and
    anything spawned there gains another copy every time - three notification
    daemons after three reloads.
    """
    # THE AUDIO STACK, WHICH NOTHING ELSE ON VOID STARTS. The pipewire and
    # wireplumber packages install their .desktop files into
    # /usr/share/applications rather than /etc/xdg/autostart, and qtile does
    # not process XDG autostart in any case - there is no init, no user service
    # and no desktop environment here to do it. Without these lines the volume
    # keys do nothing on a fresh install even with wireplumber installed.
    #
    # pipewire, then its pulse shim, then the session manager. wireplumber
    # retries if it wins the race, so no sleeps are needed.
    for cmd in (["pipewire"], ["pipewire-pulse"], ["wireplumber"]):
        subprocess.Popen(cmd)

    # Without a notification daemon every application that tries to notify
    # fails silently, and you never find out that it tried.
    subprocess.Popen(["dunst"])

    # THE PANEL SCALE, WHICH QTILE CANNOT EXPRESS IN ITS CONFIG AT ALL. The
    # Wayland backend documents input configuration and says nothing about
    # outputs, so this is set from outside, once. Failure is tolerated on
    # purpose: if wlr-randr is missing or the output is named something other
    # than eDP-1, the desktop still comes up at scale 1, which theme.py's font
    # sizes are chosen to survive.
    #
    # 1.5 to match the sibling Fedora machine on the same panel.
    if WAYLAND:
        subprocess.Popen(
            ["sh", "-c", "wlr-randr --output eDP-1 --scale 1.5 || true"]
        )

    # Somewhere for the screenshot keys to write.
    os.makedirs(PICTURES, exist_ok=True)


@hook.subscribe.client_new
def _tidy_new_clients(client):
    """Keep a couple of things out of the tiling.

    Separate from layouts.py's float_rules because this matches on a name that
    is not always set at the moment the declarative rules are evaluated.
    """
    if client.name and client.name.lower().startswith("pavucontrol"):
        client.floating = True
