#!/usr/bin/env python3
"""
check.py - load the split config without qtile installed.

WHY THIS EXISTS. `qtile check` only copies config.py into its temporary
directory (qtile issue #2223), so it cannot see env.py, keys.py or any of the
rest - which makes it useless for exactly the layout this config uses. And on
the machine where the config is WRITTEN, qtile is generally not installed at
all, so there is nothing to check with.

So this stubs out libqtile with mocks and imports config.py for real. That
proves the things a split config actually gets wrong:

  - a circular import between modules
  - a name imported from the wrong module, or misspelled
  - a module that fails at import time rather than at use time
  - the module-level names qtile requires being absent from config.py

It CANNOT prove that a widget takes the arguments given to it, that a layout
option exists, or that a keybinding names a real lazy command - every one of
those is a mock here and will accept anything. Those need real qtile.

    usage:  python3 qtile/check.py [--backend wayland|x11]
"""

import argparse
import importlib
import sys
import types
from pathlib import Path
from unittest.mock import MagicMock

HERE = Path(__file__).resolve().parent

REQUIRED = [
    "keys", "groups", "layouts", "floating_layout", "screens", "mouse",
    "widget_defaults", "extension_defaults",
]


def install_stubs(backend: str) -> None:
    """Put a fake libqtile into sys.modules before the config imports it."""
    libqtile = types.ModuleType("libqtile")

    # The one value the config branches on, so it is real rather than a mock.
    core = types.SimpleNamespace(name=backend)
    libqtile.qtile = types.SimpleNamespace(core=core)

    for name in ("bar", "widget", "layout", "hook", "extension"):
        setattr(libqtile, name, MagicMock(name=f"libqtile.{name}"))

    # hook.subscribe.<event> is used as a decorator, so it must return the
    # function it is handed rather than a mock - otherwise the module-level
    # decorated functions become mocks and any later reference to them breaks.
    def _subscribe(fn):
        return fn

    libqtile.hook.subscribe = MagicMock()
    for event in ("startup_once", "startup", "client_new", "startup_complete"):
        setattr(libqtile.hook.subscribe, event, _subscribe)

    sys.modules["libqtile"] = libqtile
    for name in ("bar", "widget", "layout", "hook", "extension"):
        sys.modules[f"libqtile.{name}"] = getattr(libqtile, name)

    config_mod = types.ModuleType("libqtile.config")
    for cls in ("Key", "KeyChord", "Group", "Screen", "Click", "Drag",
                "Match", "ScratchPad", "DropDown", "Rule"):
        setattr(config_mod, cls, MagicMock(name=f"config.{cls}"))
    sys.modules["libqtile.config"] = config_mod

    lazy_mod = types.ModuleType("libqtile.lazy")
    lazy_mod.lazy = MagicMock(name="lazy")
    sys.modules["libqtile.lazy"] = lazy_mod

    backend_pkg = types.ModuleType("libqtile.backend")
    wayland_mod = types.ModuleType("libqtile.backend.wayland")
    wayland_mod.InputConfig = MagicMock(name="InputConfig")
    sys.modules["libqtile.backend"] = backend_pkg
    sys.modules["libqtile.backend.wayland"] = wayland_mod


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", default="wayland",
                    choices=["wayland", "x11"],
                    help="which backend to pretend to be running under")
    args = ap.parse_args()

    install_stubs(args.backend)

    # The config imports its siblings by bare name, which is how qtile loads it
    # too - the config's own directory is what they are relative to.
    sys.path.insert(0, str(HERE))

    try:
        cfg = importlib.import_module("config")
    except Exception as exc:  # noqa: BLE001 - the whole point is to report it
        print(f"  FAIL    importing config.py under --backend {args.backend}")
        print(f"          {type(exc).__name__}: {exc}")
        return 1

    print(f"  ok      config.py imports under --backend {args.backend}")

    missing = [n for n in REQUIRED if not hasattr(cfg, n)]
    if missing:
        print(f"  FAIL    config.py is missing: {', '.join(missing)}")
        return 1
    print(f"  ok      all {len(REQUIRED)} names qtile requires are present")

    # The two things most likely to be quietly wrong in a split config.
    nkeys = len(cfg.keys)
    ngroups = len(cfg.groups)
    print(f"  ok      {nkeys} keybindings, {ngroups} groups")
    if nkeys < 20:
        print("  FAIL    suspiciously few keybindings - did group_keys load?")
        return 1

    # wl_input_rules must exist on Wayland and be None on X11, which is the
    # branch most likely to rot.
    rules = getattr(cfg, "wl_input_rules", "absent")
    if args.backend == "wayland":
        if not isinstance(rules, dict) or not rules:
            print("  FAIL    wl_input_rules should be a non-empty dict on wayland")
            return 1
        print(f"  ok      wl_input_rules has {len(rules)} entries")
    else:
        if rules not in (None, "absent"):
            print("  FAIL    wl_input_rules should be None on x11")
            return 1
        print("  ok      wl_input_rules is None on x11")

    return 0


if __name__ == "__main__":
    sys.exit(main())
