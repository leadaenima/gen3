#!/usr/bin/env python3
"""Capture stock Pokemon Ruby (GBA) reference PNGs via mGBA libretro.

Uses tools/gba_oracle (ctypes + vendor/mgba_libretro.dll). No GUI.
Released mGBA 0.10.5 has Tools>Scripting Lua (emu:screenshot) but no
reliable --script CLI for unattended runs; this is the automated path.

Examples (from PORT root):

  python tools/visual_validate/capture_stock.py --scene boot \
      --out tmp/visual_validate/stock_boot.png

  python tools/visual_validate/capture_stock.py --scene title \
      --out tmp/visual_validate/stock_title.png

  python tools/visual_validate/capture_stock.py --scene naming-path \
      --out-dir tmp/visual_validate --prefix stock_naming

  python tools/visual_validate/capture_stock.py --advance 600 --keys start \
      --out tmp/visual_validate/stock_custom.png
"""

from __future__ import annotations

import argparse
import os
import sys

PORT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ORACLE = os.path.join(PORT, "tools", "gba_oracle")
sys.path.insert(0, ORACLE)

import libretro  # noqa: E402


DEFAULT_ROMS = [
    os.path.join(PORT, "misc", "Pokemon - Ruby Version (USA).gba"),
    os.path.join(os.path.expanduser("~"), "Desktop",
                 "Pokemon - Ruby Version (USA).gba"),
]


def find_rom(explicit: str | None) -> str:
    if explicit:
        if not os.path.isfile(explicit):
            sys.exit("ROM not found: %s" % explicit)
        return explicit
    for path in DEFAULT_ROMS:
        if os.path.isfile(path):
            return path
    sys.exit("no Ruby ROM found; pass --rom PATH")


def shot(core: libretro.Core, path: str) -> None:
    if not core.frame:
        sys.exit("no video frame yet; advance more frames before --out")
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    buf, pitch = core.frame
    libretro.png(path, buf, pitch, *core.frame_size)
    w, h = core.frame_size
    print("wrote %s (%dx%d)" % (path, w, h))


def mash(core: libretro.Core, presses: int, every: int, out_dir: str | None,
         prefix: str) -> None:
    """A + periodic START, same idea as gba_oracle/newgame.py intro drive."""
    for n in range(1, presses + 1):
        core.press("a", hold=6, release=6)
        if n % 6 == 0:
            core.press("start", hold=6, release=6)
        if out_dir and every and n % every == 0:
            shot(core, os.path.join(out_dir, "%s_p%03d.png" % (prefix, n)))


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--rom", help="path to Pokemon Ruby (USA).gba")
    ap.add_argument(
        "--scene",
        choices=("boot", "title", "naming-path", "raw"),
        default="raw",
        help="boot: after reset; title: idle+START; naming-path: mash sequence; "
             "raw: --advance/--keys only",
    )
    ap.add_argument("--advance", type=int, default=0,
                    help="extra frames to run (raw/title)")
    ap.add_argument("--keys", default="",
                    help="comma buttons for raw mode, e.g. start,a")
    ap.add_argument("--out", help="single PNG path")
    ap.add_argument("--out-dir", help="directory for multi-shot scenes")
    ap.add_argument("--prefix", default="stock",
                    help="filename prefix for naming-path shots")
    ap.add_argument("--presses", type=int, default=240,
                    help="naming-path mash count (default 240)")
    ap.add_argument("--every", type=int, default=40,
                    help="naming-path save every N presses (default 40)")
    ap.add_argument("--title-idle", type=int, default=900,
                    help="frames to idle before START on title scene")
    args = ap.parse_args()

    rom = find_rom(args.rom)
    print("rom  %s" % rom)
    print("core %s" % libretro.DLL)

    out_dir = args.out_dir
    if args.scene == "naming-path":
        out_dir = out_dir or os.path.join(PORT, "tmp", "visual_validate")
        os.makedirs(out_dir, exist_ok=True)

    with libretro.Core() as core:
        core.load(rom)
        print("loaded %s" % core.library)

        if args.scene == "boot":
            core.run(2)
            path = args.out or os.path.join(
                PORT, "tmp", "visual_validate", "stock_boot.png")
            shot(core, path)
            return

        if args.scene == "title":
            idle = args.title_idle if args.advance <= 0 else args.advance
            print("idle %d frames" % idle)
            core.run(idle)
            core.press("start", hold=8, release=20)
            core.run(90)
            path = args.out or os.path.join(
                PORT, "tmp", "visual_validate", "stock_title.png")
            shot(core, path)
            return

        if args.scene == "naming-path":
            print("mashing %d presses; shot every %d -> %s"
                  % (args.presses, args.every, out_dir))
            mash(core, args.presses, args.every, out_dir, args.prefix)
            final = os.path.join(out_dir, "%s_final.png" % args.prefix)
            shot(core, final)
            print("note: naming appears somewhere in the sequence; "
                  "inspect PNGs -- this tool does not assert which frame")
            return

        if args.advance:
            keys = [k.strip() for k in args.keys.split(",") if k.strip()]
            if keys:
                step, spent, i = 30, 0, 0
                while spent < args.advance:
                    core.set_keys(keys[i % len(keys)])
                    core.run(step - 6)
                    core.set_keys()
                    core.run(6)
                    spent += step
                    i += 1
            else:
                core.run(args.advance)
        else:
            core.run(2)
        if not args.out:
            sys.exit("raw scene needs --out PATH")
        shot(core, args.out)


if __name__ == "__main__":
    main()
