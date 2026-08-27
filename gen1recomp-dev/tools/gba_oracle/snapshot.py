"""Reads Ruby's state off the cart, and shows what a scene changes.

Two modes, both aimed at the same question -- what is the engine supposed
to do here?

    # what the state is right now
    python tools/gba_oracle/snapshot.py <rom> --state states/newgame.state

    # what changes across N frames of play, named
    python tools/gba_oracle/snapshot.py <rom> --state states/newgame.state \\
        --advance 600 --keys a --delta

The delta is the useful one when implementing a scene: it says exactly
which flags and vars the real game touches, so the Lua side has something
to match instead of a reading of pokeruby.

--json writes the snapshot out for later diffing.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import libretro  # noqa: E402
import names  # noqa: E402
import ruby  # noqa: E402


def report(snap, title):
    loc = snap["location"]
    print("== %s" % title)
    print("   map        group %d, number %d (warp %d)"
          % (loc["mapGroup"], loc["mapNum"], loc["warpId"]))
    print("   position   (%d, %d)" % snap["position"])
    if "playerXY" in snap:
        print("   playerXY   (%d, %d)" % tuple(snap["playerXY"]))
    if "flashLevel" in snap:
        print("   flash      %d" % snap["flashLevel"])
    print("   layout     %d" % snap["mapLayoutId"])
    print("   party      %d" % len(snap["party"]))
    print("   flags set  %d" % len(snap["flags"]))
    print("   vars set   %d" % len(snap["vars"]))


def show_delta(before, after):
    lines = ruby.diff(before, after, flag_name=names.flag,
                      var_name=names.var)
    print("== what the cart changed (%d differences)" % len(lines))
    if not lines:
        print("   nothing")
        return
    for line in lines:
        # diff() words things as left/right; say it in scene terms.
        line = line.replace("set on left only", "CLEARED")
        line = line.replace("set on right only", "SET")
        print("   %s" % line)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom")
    ap.add_argument("--state", help="savestate to load before doing anything")
    ap.add_argument("--advance", type=int, default=0,
                    help="frames to run after loading")
    ap.add_argument("--keys", default="",
                    help="buttons to tap in turn, cycling, e.g. down,left,a")
    ap.add_argument("--delta", action="store_true",
                    help="print what changed rather than the whole state")
    ap.add_argument("--json", help="write the final snapshot here")
    ap.add_argument("--shot", help="write a screenshot here")
    args = ap.parse_args()

    if not names.have_names():
        print("note: no pokeruby headers found, flags will be bare numbers",
              file=sys.stderr)

    with libretro.Core() as core:
        core.load(args.rom)
        if args.state:
            with open(args.state, "rb") as fh:
                core.load_state(fh.read())
        state = ruby.RubyState(core)

        before = state.snapshot()
        if not args.delta:
            report(before, "state on load")

        if args.advance:
            keys = [k.strip() for k in args.keys.split(",") if k.strip()]
            if keys:
                # Tapped in turn rather than held together: a held button
                # reads as one press so textboxes never advance, and a
                # single direction just walks into the nearest wall.
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

            after = state.snapshot()
            if args.delta:
                show_delta(before, after)
            else:
                print("")
                report(after, "state after %d frames" % args.advance)
            final = after
        else:
            final = before

        if args.json:
            with open(args.json, "w", encoding="utf-8") as fh:
                json.dump(final, fh, indent=1, sort_keys=True)
            print("wrote %s" % args.json)
        if args.shot and core.frame:
            buf, pitch = core.frame
            libretro.png(args.shot, buf, pitch, *core.frame_size)
            print("shot  %s" % args.shot)


if __name__ == "__main__":
    main()
