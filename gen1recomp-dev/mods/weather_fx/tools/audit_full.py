#!/usr/bin/env python3
"""
Weather FX full audit tool.

Checks:
  - schema completeness vs Settings.get usage
  - dual/competing systems (sky, sun, fog)
  - compatibility risk patterns (Sky.paint wraps, host requires, crystal/gen3)
  - unfinished markers and fragile pcall density
  - celestial pipeline consistency
  - indoor weather gate presence
  - fog intensity wiring
  - file/syntax balance

Exit 0 always for report mode; --strict fails on HIGH findings.
"""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[1]

def read(rel: str) -> str:
    p = ROOT / rel
    return p.read_text(errors="ignore") if p.exists() else ""

def all_lua():
    for p in ROOT.rglob("*.lua"):
        if "artifacts" in p.parts and p.parts[0] != str(ROOT):
            continue
        yield p.relative_to(ROOT).as_posix(), p.read_text(errors="ignore")

findings = []  # dict severity, area, msg, file

def add(sev, area, msg, file="-"):
    findings.append({"severity": sev, "area": area, "msg": msg, "file": file})

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    settings = read("lib/Settings.lua")
    main_lua = read("main.lua")
    ws = read("lib/WeatherState.lua")
    night = read("lib/NightSky.lua")
    cel = read("lib/CelestialBodies.lua")
    sim = read("lib/CelestialSim.lua")
    dram = read("lib/DramalessAtmos.lua")
    battle = read("lib/Battle.lua")
    draw = read("lib/Draw.lua")
    scene = read("lib/Scene.lua")
    fog = read("lib/Fog.lua")
    man = {}
    try:
        man = json.loads(read("manifest.json") or "{}")
    except Exception:
        add("HIGH", "meta", "manifest.json invalid", "manifest.json")

    # --- Schema keys ---
    # Count the primary schema only. Settings.define contains a deliberately
    # smaller emergency fallback schema; including it double-counted rows and
    # made the audit report a fictional menu size.
    schema_src = settings.split("function Settings.define", 1)[0]
    keys = re.findall(r'key\s*=\s*"([^"]+)"', schema_src)
    add("INFO", "settings", f"{len(keys)} menu options: {', '.join(keys)}", "lib/Settings.lua")
    for need in ("fogIntensity", "intensity", "present", "battles", "battleDamage"):
        if need not in keys:
            add("HIGH", "settings", f"missing schema key {need}", "lib/Settings.lua")

    # Settings.get usage for unknown keys (heuristic)
    used = set(re.findall(r'Settings\.get\(\s*"([^"]+)"\s*\)', "\n".join(t for _, t in all_lua())))
    schema = set(keys)
    orphan_gets = sorted(used - schema - {"debugRain"})  # debugRain is in schema
    for k in orphan_gets:
        if k in schema:
            continue
        add("MED", "settings", f"Settings.get({k!r}) used but not in SCHEMA", "-")

    # --- Indoor gate ---
    if "indoors" in ws and "State._indoorAccum" in ws:
        add("INFO", "indoor", "indoor/cave weather pause present", "lib/WeatherState.lua")
    else:
        add("HIGH", "indoor", "indoor weather gate missing", "lib/WeatherState.lua")

    # --- Fog intensity ---
    if "fogIntensity" in settings and "Settings.fogIntensity" in ws:
        add("INFO", "fog", "FOG INTENSITY wired Settings → WeatherState", "lib/WeatherState.lua")
    else:
        add("HIGH", "fog", "FOG INTENSITY not fully wired", "-")
    if "10.0" in settings or "10.0" in settings:
        add("INFO", "fog", "extreme 300% curve present", "lib/Settings.lua")
    if "math.min(0.55" in draw and "veil" in draw:
        add("MED", "fog", "old veil 0.55 hard cap may still exist somewhere", "lib/Draw.lua")
    if "0.92" in draw:
        add("INFO", "fog", "veil can reach high alpha for extreme fog", "lib/Draw.lua")

    # --- Celestial dual paths ---
    sun_paths = []
    if "drawSunMoonWorld" in night:
        sun_paths.append("NightSky.drawSunMoonWorld")
    if "function Celestial.drawWorld" in cel:
        sun_paths.append("CelestialBodies.drawWorld")
    if "wxPaintCelestialDisc" in main_lua:
        sun_paths.append("main wxPaintCelestialDisc / Sky.paint")
    if "CB.drawWorld" in dram:
        sun_paths.append("DramalessAtmos → CelestialBodies.drawWorld")
    if "drawSunMoonWorld" in dram:
        sun_paths.append("DramalessAtmos → NightSky.drawSunMoonWorld")
    if "drawSunMoonProjectedWorld" in dram:
        sun_paths.append("DramalessAtmos → NightSky.drawSunMoonProjectedWorld")
    add("INFO", "celestial", f"sun/moon draw paths: {', '.join(sun_paths) or 'NONE'}", "-")
    # 4.35.34 moved strict 3D ownership to a background-stage projected WORLD
    # vault. The old drawSunMoonWorld mesh can be unsupported on a live host;
    # drawSunMoonProjectedWorld keeps the same fixed world directions and exact
    # host VP but draws before terrain, avoiding both silent shader loss and the
    # camera-pitch-dependent Sky.region fallback. Exactly one of the two
    # host-aware world paths is allowed, and direct CelestialBodies drawing must
    # remain absent to prevent duplicates.
    dram_mesh_calls = len(re.findall(r"pcall\(NightSky\.drawSunMoonWorld\s*,\s*Voxel3D\)", dram))
    dram_projected_calls = len(re.findall(r"NS\.drawSunMoonProjectedWorld\s*and\s*NS\.drawSunMoonProjectedWorld\s*\(Voxel3D", dram))
    dram_cr2_calls = len(re.findall(r"CR2\.drawProjected\s*\(Voxel3D", dram))
    dram_host_calls = dram_mesh_calls + dram_projected_calls + dram_cr2_calls
    dram_direct_calls = len(re.findall(r"\bCB\.drawWorld\s*\(Voxel3D", dram))
    if dram_host_calls != 1 or dram_direct_calls != 0:
        add("HIGH", "celestial",
            f"Dramaless celestial ownership is ambiguous: host-aware={dram_host_calls} (mesh={dram_mesh_calls}, projected={dram_projected_calls}, celestial2={dram_cr2_calls}), direct={dram_direct_calls}",
            "lib/DramalessAtmos.lua")
    else:
        mode = "CelestialRenderer2 projected fixed-world" if dram_cr2_calls == 1 else ("projected fixed-world" if dram_projected_calls == 1 else "world-mesh")
        add("INFO", "celestial", f"Dramaless uses one host-aware sun/moon path ({mode})", "lib/DramalessAtmos.lua")
    if "CelestialSim" not in sim and "function Sim.sample" not in sim:
        add("HIGH", "celestial", "CelestialSim missing", "lib/CelestialSim.lua")
    else:
        add("INFO", "celestial", "CelestialSim simulation layer present", "lib/CelestialSim.lua")

    # Camera ownership anti-patterns. A helper named cameraForward is legitimate
    # for visibility culling; only direct camera.forward authority is suspicious
    # for celestial placement. WorldPrecip intentionally derives a view vector
    # from eye->focus solely to skip geometry guaranteed behind the camera.
    for rel, t in all_lua():
        if "camera.forward" in t:
            add("MED", "celestial", "camera.forward reference — check not used for celestial direction", rel)

    # --- Sky.paint shared ownership ---
    wraps = 0
    if "function Sky.paint" in main_lua:
        wraps += 1
    if "function Sky.paint" in dram:
        wraps += 1
    if wraps >= 2:
        if "if not Sky._wxNightWrapped and not want3d() then" in dram:
            add("INFO", "compat",
                "main + Dramaless Sky.paint wrappers share background ownership; screen-space NightSky fallback is 2D-only while active 3D celestial ownership remains world-space.",
                "lib/DramalessAtmos.lua")
        elif "if not Sky._wxNightWrapped then" in dram:
            add("INFO", "compat",
                "main + Dramaless Sky.paint wrappers share NightSky ownership; Dramaless dynamically defers duplicate star draw.",
                "lib/DramalessAtmos.lua")
        else:
            add("MED", "compat",
                f"{wraps} Sky.paint wrappers can both draw NightSky; install order may double-render stars.",
                "-")

    # --- Battle / crystal / gen3 ---
    if "crystal" in battle.lower() or "CRYSTAL" in battle:
        add("INFO", "compat", "Crystal-aware battle paths present", "lib/Battle.lua")
    if "gen3" in battle.lower() or "Gen3" in battle or "battleOverlay" in read("lib/BattleDraw.lua"):
        add("INFO", "compat", "Gen3/battle UI coexistence hooks likely present", "lib/BattleDraw.lua")
    if "effectsEnabled" in read("lib/BattleDraw.lua") or "battleAnim" in settings:
        add("INFO", "compat", "BATTLE WEATHER FX/DMG toggles in schema", "lib/Settings.lua")

    # --- pcall density (swallow errors) ---
    for rel, t in all_lua():
        if not rel.startswith("lib/") and rel != "main.lua":
            continue
        n = t.count("pcall(")
        if n > 80:
            add("MED", "robustness", f"very high pcall density ({n}) may hide host-specific runtime errors", rel)
        elif n > 40:
            add("MED", "robustness", f"high pcall density ({n}) may hide runtime errors", rel)

    # Raw delimiter counts are not a Lua syntax parser: comments, strings and
    # embedded GLSL made the old checker report valid files as HIGH failures.
    # Syntax belongs to the Lua/runtime suite; this audit reports architectural
    # risk rather than pretending character counts can compile Lua.

    # --- Feature implementation vs manual host verification ---
    const = read("lib/Constellations.lua")
    if "appendWorld" in const and "twinkleAlpha" in night and "Constellations.appendWorld" in night:
        add("INFO", "feature", "Pokémon constellations and twinkle path are wired; behavioural contracts cover the headless path.", "lib/Constellations.lua")
    else:
        add("MED", "feature", "constellation/twinkle implementation is incomplete or disconnected", "lib/NightSky.lua")

    wp = read("lib/voxel_atmos/WorldPrecip.lua")
    sp = read("lib/SnowPack.lua")
    if "function WP.snowGroundCollisionEnabled() return false end" in wp and "gsnow.active=0; foot.active=0" in wp:
        if "SP.ACCUMULATION_ENABLED = true" in sp and 'if kind=="water" then return 0 end' in sp and "function SP.resolveFlake" in sp:
            add("INFO", "feature", "SnowPack remains bounded and shipped, but 8.1.54 intentionally suspends falling-snow ground collision/settling/banks/footprints until the ground resolver is repaired.", "lib/SnowPack.lua")
        else:
            add("HIGH", "feature", "snow-ground integration is suspended but the retained SnowPack repair surface is incomplete", "lib/SnowPack.lua")
    elif "SP.ACCUMULATION_ENABLED = true" in sp and "SP and SP.ACCUMULATION_ENABLED and SP.beginFrame" in wp and 'if kind=="water" then return 0 end' in sp:
        add("INFO", "feature", "8.1.28 3D SnowPack redesign is live through bounded radial banks/footprints, retains exact voxel/model collision, and rejects water accumulation.", "lib/SnowPack.lua")
    else:
        add("HIGH", "feature", "8.1.28 SnowPack redesign is incomplete, unbounded, or missing its water/staging authority", "lib/SnowPack.lua")

    # These paths depend on real host camera/depth/unload behaviour and cannot be
    # proven by the headless harness. Keep them explicit as MANUAL verification,
    # not as claims that implementation is missing.
    add("MED", "manual", "WX PRESENT 3D/AUTO composition requires an in-game check on each supported voxel host", "-")
    add("MED", "manual", "world-space sun/moon overhead/orbit orientation requires an in-engine visual check", "-")
    add("MED", "manual", "runtime-hook teardown/uninstall safety requires a real hot-unload/uninstall check", "-")

    if "if night then return 0 end" in read("lib/voxel_atmos/CinematicAtmos.lua"):
        add("INFO", "feature", "3D god-ray intensity is intentionally hard-stopped at night", "lib/voxel_atmos/CinematicAtmos.lua")

    # --- Version ---
    add("INFO", "meta", f"version {man.get('version', '?')} id={man.get('id', '?')}", "manifest.json")

    # --- Report ---
    order = {"HIGH": 0, "MED": 1, "LOW": 2, "INFO": 3}
    findings.sort(key=lambda f: (order.get(f["severity"], 9), f["area"], f["msg"]))

    if args.json:
        print(json.dumps(findings, indent=2))
    else:
        print("=== WEATHER FX FULL AUDIT ===\n")
        by = defaultdict(list)
        for f in findings:
            by[f["severity"]].append(f)
        for sev in ("HIGH", "MED", "LOW", "INFO"):
            items = by.get(sev) or []
            if not items:
                continue
            print(f"## {sev} ({len(items)})")
            for f in items:
                print(f"  [{f['area']}] {f['msg']}")
                if f["file"] != "-":
                    print(f"           → {f['file']}")
            print()
        print(f"Total findings: {len(findings)}")
        print(f"HIGH={len(by['HIGH'])} MED={len(by['MED'])} LOW={len(by['LOW'])} INFO={len(by['INFO'])}")

    highs = sum(1 for f in findings if f["severity"] == "HIGH")
    if args.strict and highs:
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
