#!/usr/bin/env python3
"""
Weather FX revision gate — run before shipping any new build.

Checks: structure, night sky, battle options, indoor pause, compat hooks,
labels, clear fog, optimization markers. Exit 0 = pass.
"""
from __future__ import annotations
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
failed = []
passed = []

def ok(name, cond, detail=""):
    if cond:
        passed.append(name)
        print(f"  PASS  {name}" + (f" — {detail}" if detail else ""))
    else:
        failed.append(name)
        print(f"  FAIL  {name}" + (f" — {detail}" if detail else ""))

def read(rel):
    p = ROOT / rel
    if not p.exists():
        return None
    return p.read_text(encoding="utf-8", errors="replace")

def main():
    print("=== Weather FX revision gate ===")
    print(f"root: {ROOT}")

    # --- Manifest ---
    print("\n[manifest]")
    man_path = ROOT / "manifest.json"
    ok("manifest exists", man_path.exists())
    man = {}
    if man_path.exists():
        man = json.loads(man_path.read_text())
        ok("manifest id weather_fx", man.get("id") == "weather_fx", str(man.get("id", "")))
        ok("manifest version set", bool(man.get("version")), str(man.get("version")))
        ok("manifest entry", bool(man.get("entry")))

    # --- Core files ---
    print("\n[core files]")
    core = [
        "main.lua", "config.lua", "lib/NightSky.lua", "lib/WeatherState.lua",
        "lib/Settings.lua", "lib/Battle.lua", "lib/BattleDraw.lua", "lib/Scene.lua",
        "lib/DramalessAtmos.lua", "lib/VoxelAtmosBridge.lua",
        "lib/voxel_atmos/CinematicAtmos.lua", "lib/TimeOfDay.lua", "lib/Types.lua",
    ]
    for rel in core:
        ok(f"exists {rel}", (ROOT / rel).exists())

    # --- Settings labels (4.18.6) ---
    print("\n[settings labels]")
    st = read("lib/Settings.lua") or ""
    ok("label RARE WEATHER", 'label = "RARE WEATHER"' in st)
    ok("label WEATHER DURATION", 'label = "WEATHER DURATION"' in st)
    ok("label BATTLE WEATHER", 'label = "BATTLE WEATHER"' in st)
    ok("label WEATHER RULES", 'label = "WEATHER RULES"' in st)
    ok("duplicate battleAnim row removed", 'key = "battleAnim"' not in st)
    ok("battleDamage key", 'key = "battleDamage"' in st)
    ok("battleAnimOn helper", "function Settings.battleAnimOn" in st)
    ok("battleDamageOn helper", "function Settings.battleDamageOn" in st)
    ok("QUALITY exposes POTATO", '{ "POTATO", "potato" }' in st)
    ok("QUALITY exposes MAX", '{ "MAX", "max" }' in st)

    # --- Battle toggles function ---
    print("\n[battle toggles]")
    bt = read("lib/Battle.lua") or ""
    ok("animEnabled", "function Battle.animEnabled" in bt)
    ok("effectsEnabled", "function Battle.effectsEnabled" in bt)
    ok("animEnabled uses damage path separate", "animEnabled" in bt and "effectsEnabled" in bt)
    ok("hostCrystal compat", "function Battle.hostCrystal" in bt or "CRYSTAL_251" in bt)
    ok("battle.overlay wrap", 'battle.overlay' in bt)
    ok("indoor battle no seed", "_startedIndoors" in bt or "indoors" in bt)
    bdraw = read("lib/BattleDraw.lua") or ""
    ok("BattleDraw gates anim", "animEnabled" in bdraw)

    # --- Indoor weather pause ---
    print("\n[indoor weather]")
    ws = read("lib/WeatherState.lua") or ""
    ok("indoor dwell tracking", "_indoorAccum" in ws or "_wasIndoors" in ws)
    ok("5 min threshold", "5 * 60" in ws or "300" in ws)
    sc = read("lib/Scene.lua") or ""
    ok("indoors suppress draw", "now.indoors" in sc)
    ok("Scene exports cross-gen overworld", "function Scene.overworld()" in sc)
    ok("Scene has no boot-time engine capture", re.search(r'^local\s+\w+\s*=\s*tryRequire\("src\.', sc, re.M) is None)
    ok("Gen2 environment reads map.def", "map.def and map.def.environment" in sc)

    # --- Night sky ---
    print("\n[night sky]")
    ns = read("lib/NightSky.lua") or ""
    ok("drawWorld", "function NightSky.drawWorld" in ns)
    ok("draw fallback", "function NightSky.draw" in ns)
    ok("isNight", "function NightSky.isNight" in ns)
    ok("computeNightVisibility", "function NightSky.computeNightVisibility" in ns)
    ok("star catalog", "STARS" in ns and "PLANETS" in ns)
    # 4.35.31: planets are 20% smaller than 4.35.30; Saturn is 35% smaller total.
    ok("planet/saturn reduced scales",
       "PLANET_SIZE_SCALE = 0.56" in ns and
       "SATURN_SIZE_SCALE = 0.455" in ns and
       'p.feature == "rings"' in ns)
    ok("celestial directions", "dx =" in ns and "dz =" in ns)
    ok("NITE support", "NITE" in ns)
    ok("twinkle", "twinkle" in ns.lower() or "twDepth" in ns)
    da = read("lib/DramalessAtmos.lua") or ""
    ok("Atmos draws unified celestial renderer", "CelestialRenderer2" in da and "CR2.drawProjected" in da)
    ok("NightSky returns module", ns.rstrip().endswith("return NightSky") or "return NightSky" in ns[-80:])

    # --- Clear fog ---
    print("\n[clear weather fog]")
    cin = read("lib/voxel_atmos/CinematicAtmos.lua") or ""
    ok("clear fog zero", "clear =" in cin and ("fog=0.00" in cin or "fog=0," in cin or "fog=0.0" in cin))
    ok("CLEAR settle zeros", "CLEAR" in ws and "State.settle" in ws)

    # --- Compatibility markers ---
    print("\n[compatibility]")
    ok("gen3 BattleField standdown", "gen3_battle_ui" in (read("lib/BattleField.lua") or ""))
    ok("gen3 Scene double-draw guard", "gen3_battle_ui" in sc)
    ok("Crystal host detection", "CRYSTAL_251" in bt or "hostCrystal" in bt)
    ok("Dramaless host ids", "DRAMALESS_SHAPE" in da)
    ok("ui.options fail-open", "ui.options.rows" in (read("main.lua") or "") and ("_wxOptionsRowsWrapped" in (read("main.lua") or "") or "pipeline:weather" in (read("main.lua") or "")))
    ok("TIME pipeline removed from OPTIONS", 'register("daynight"' not in (read("main.lua") or ""))

    # --- Fluidity / transitions ---
    print("\n[fluidity]")
    ok("channel ease", "function ease" in ws or "ease(" in ws)
    ok("soft weather handoff", "softTo" in ws or "softDur" in ws)
    ok("TAU fog", "TAU" in ws)

    # --- Optimization / safety ---
    print("\n[safety]")
    ok("NightSky single drawWorld", (ns or "").count("function NightSky.drawWorld") == 1)
    ok("main has celestial disc", "wxPaintCelestialDisc" in (read("main.lua") or ""))
    ok("Celestial.bodies API", "function Celestial.bodies" in (read("lib/CelestialBodies.lua") or ""))
    ok("moon opposite sun", "math.pi" in (read("lib/CelestialSim.lua") or ""))
    ok("no daynight OPTIONS ladder", 'register("daynight"' not in (read("main.lua") or ""))
    cfgsrc = read("lib/Config.lua") or ""
    ok("config supports legendary.rateBoost", 'legendary.rateBoost' in cfgsrc and 'rateBoost = 1.05' in cfgsrc)
    ok("config supports encounter bans", 'encounterBansById' in cfgsrc and 'encounterBans' in cfgsrc)
    ok("config QUALITY supports POTATO", 'potato = true' in cfgsrc)
    ok("config QUALITY supports MAX", 'max = true' in cfgsrc)

    # --- Tools present ---
    print("\n[tools suite]")
    for name in ("run_all.py", "test_mod.py", "test_night_sky.py", "test_celestial_supersample.py", "test_settings_runtime.py",
                 "feature_audit.py", "edit_guard.py", "revision_gate.py", "ai_debug.py"):
        ok(f"tool {name}", (ROOT / "tools" / name).exists())

    print("\n=== SUMMARY ===")
    print(f"passed: {len(passed)}")
    print(f"failed: {len(failed)}")
    if failed:
        print("failures:")
        for f in failed:
            print(f"  - {f}")
        return 1
    print("ALL GATES PASSED")
    return 0

if __name__ == "__main__":
    sys.exit(main())
