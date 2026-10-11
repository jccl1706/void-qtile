"""
autostart - the hooks.

Importing this module registers them; config.py imports it for that side effect
alone, which is why it exports nothing.
"""

import os
import subprocess

from libqtile import hook

from env import PICTURES, WAYLAND
from theme import CURSOR_SIZE, CURSOR_THEME, GTK_THEME


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

    # THE SETTINGS A GTK APP ACTUALLY READS, which are not the ones in
    # ~/.config/gtk-3.0/settings.ini.
    #
    # A GTK app on Wayland asks xdg-desktop-portal whether to be light or dark.
    # The portal answers from gsettings org.gnome.desktop.interface. So a
    # desktop can have a correct settings.ini, a correct GTK theme installed,
    # and still open Firefox white - which is exactly what happened here.
    #
    # Set from THIS process because it has the session bus: dconf cannot commit
    # without one, and a shell that is not part of the graphical session does
    # not have it ("Cannot autolaunch D-Bus without X11 $DISPLAY"). Running it
    # here is the one place the bus is guaranteed.
    #
    # Values come from the palette so there is still one source of truth.
    for key, value in (
        ("color-scheme", "prefer-dark"),
        ("gtk-theme", GTK_THEME),
        ("cursor-theme", CURSOR_THEME),
        ("cursor-size", str(CURSOR_SIZE)),
    ):
        subprocess.Popen(
            ["gsettings", "set", "org.gnome.desktop.interface", key, value],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
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
