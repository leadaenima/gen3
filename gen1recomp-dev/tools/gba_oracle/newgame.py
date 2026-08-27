"""Boots Ruby, starts a new game, and checkpoints the first playable moment.

Getting into the world is the slow part of every oracle run, so it is done
once here and written out as a savestate.  Later comparisons load that
state instead of replaying the intro, which keeps them fast and keeps them
from depending on menu timing.

    python tools/gba_oracle/newgame.py <rom.gba> [--shots DIR]

Progress is judged from RAM rather than from a frame count: the driver
mashes through the intro and naming screens and stops as soon as
SaveBlock1 holds a real location, so it cannot silently "succeed" while
still sitting on the title screen.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import libretro  # noqa: E402
import ruby  # noqa: E402

STATE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "states")


def shot(core, path):
    if not core.frame:
        return
    buf, pitch = core.frame
    libretro.png(path, buf, pitch, *core.frame_size)


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: python newgame.py <rom.gba> [--shots DIR]")
    rom = sys.argv[1]
    shots = None
    if "--shots" in sys.argv:
        shots = sys.argv[sys.argv.index("--shots") + 1]
        os.makedirs(shots, exist_ok=True)

    with libretro.Core() as core:
        core.load(rom)
        state = ruby.RubyState(core)
        print("core %s" % core.library)

        # The intro, the title screen, NEW GAME, Birch's speech, the
        # gender pick and the naming screen are all advanced with A, with
        # START mixed in because the title and the naming screen want it.
        presses = 0
        while presses < 400:
            core.press("a", hold=6, release=6)
            presses += 1
            if presses % 6 == 0:
                core.press("start", hold=6, release=6)
            if shots and presses % 40 == 0:
                shot(core, os.path.join(shots, "p%03d.png" % presses))
            if presses % 10 == 0 and state.looks_initialised():
                break

        loc = state.location()
        print("presses    %d" % presses)
        print("location   group %d map %d warp %d at (%d,%d)"
              % (loc["mapGroup"], loc["mapNum"], loc["warpId"],
                 loc["x"], loc["y"]))
        print("position   %r" % (state.position(),))
        print("flags set  %d" % len(state.flags()))
        print("vars nonzero %d" % len(state.vars()))
        print("party      %d" % len(state.party()))
        print("playtime   %dh%02dm" % (state.player()["playTimeHours"],
                                       state.player()["playTimeMinutes"]))

        if not state.looks_initialised():
            if shots:
                shot(core, os.path.join(shots, "stuck.png"))
            sys.exit("did not reach the world; see the shots to find where")

        os.makedirs(STATE_DIR, exist_ok=True)
        path = os.path.join(STATE_DIR, "newgame.state")
        with open(path, "wb") as fh:
            fh.write(core.save_state())
        print("state      %s (%d bytes)" % (path, os.path.getsize(path)))
        if shots:
            shot(core, os.path.join(shots, "final.png"))


if __name__ == "__main__":
    main()
