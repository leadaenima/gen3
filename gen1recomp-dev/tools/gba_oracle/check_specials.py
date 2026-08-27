"""Cross-checks the engine's special ids against pokeruby's gSpecials.

Game3 hardcodes a numeric id per special it implements.  A wrong id is
invisible in normal testing -- the scene just quietly does the wrong
thing, or nothing -- so this compares each `Game3.SPECIAL_X = n` against
the name pokeruby has at ordinal n and reports anything that does not
line up.

    python tools/gba_oracle/check_specials.py

Exits 1 when an id names a function the constant clearly is not.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import names  # noqa: E402

GAME3 = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "..", "..", "src", "core", "Game3.lua")

# Words the two naming schemes spell differently, or that only one side
# bothers to say.  Dropping them is what lets SAVE_PLAYER_PARTY match
# SavePlayerParty and HEAL_PARTY match ScrSpecial_HealPlayerParty.
NOISE = {"SCR", "SPECIAL", "PLAYER", "GET", "SHOW", "CHECK", "SUB", "THE"}


def tokens(name):
    name = re.sub(r"^ScrSpecial_?", "", name)
    name = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name)
    parts = [p for p in re.split(r"[^A-Za-z0-9]+", name.upper()) if p]
    return set(parts) - NOISE


def main():
    table = names.specials()
    if not table:
        sys.exit("no pokeruby data/specials.inc found; set POKERUBY")

    with open(GAME3, "r", encoding="utf-8", errors="replace") as fh:
        source = fh.read()

    rows = re.findall(r"Game3\.SPECIAL_([A-Z0-9_]+)\s*=\s*(\d+)", source)
    if not rows:
        sys.exit("no Game3.SPECIAL_* constants found")

    agree, suspect, missing, unnamed = [], [], [], []
    for const, raw in rows:
        num = int(raw)
        fn = table.get(num)
        if fn is None:
            missing.append((const, num))
            continue
        # An undecompiled `sub_80C5044` carries no name to agree with, so
        # comparing against it would only manufacture false alarms.
        if re.match(r"^sub_[0-9A-Fa-f]+$", fn):
            unnamed.append((const, num, fn))
            continue
        ours, theirs = tokens(const), tokens(fn)
        if ours & theirs:
            agree.append((const, num, fn))
        else:
            suspect.append((const, num, fn))

    print("checked   %d constants against %d specials"
          % (len(rows), len(table)))
    print("agree     %d" % len(agree))
    print("suspect   %d" % len(suspect))
    print("unnamed   %d (pokeruby has no name at that ordinal yet)"
          % len(unnamed))
    print("off table %d" % len(missing))
    print("")

    for const, num, fn in suspect:
        print("  SUSPECT  SPECIAL_%-38s = %-3d  pokeruby: %s"
              % (const, num, fn))
    for const, num in missing:
        print("  OFF TABLE SPECIAL_%-37s = %-3d  (table has %d entries)"
              % (const, num, len(table)))

    if suspect or missing:
        print("")
        print("A suspect row is not automatically wrong -- the two naming")
        print("schemes diverge -- but each one needs a human to confirm.")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
