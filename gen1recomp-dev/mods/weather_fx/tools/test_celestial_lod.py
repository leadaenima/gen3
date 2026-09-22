#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
failed = 0
def ok(c,m):
    global failed
    print(("PASS" if c else "FAIL"), m)
    if not c: failed += 1
q = (ROOT/"lib/Quality.lua").read_text()
ns = (ROOT/"lib/NightSky.lua").read_text()
ok("function Quality.celestial" in q, "Quality.celestial")
ok("starStep" in q and "maxPlanets" in q, "LOD fields in tiers")
ok("celestialLod" in ns, "NightSky lod helper")
ok("for i = 1, #STARS, step" in ns or "for i = 1, #STARS, step" in ns.replace(" ",""), "star step loop")
ok("lod.maxPlanets" in ns, "planet cap")
ok("lod.meteors" in ns, "meteor lod")
print("RESULT", "OK" if not failed else "FAIL", failed)
sys.exit(1 if failed else 0)
