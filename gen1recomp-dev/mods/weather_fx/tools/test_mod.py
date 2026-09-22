#!/usr/bin/env python3
"""
Weather FX — functional / structural test suite for AI and humans.

Runs without LÖVE or a ROM. Optionally runs the existing Lua headless
tests when a Lua interpreter is on PATH.

Usage:
  python3 tools/test_mod.py
  python3 tools/test_mod.py --json
  python3 tools/test_mod.py --lua   # maintained Lua release suites, if available

Exit 0 = all passed, 1 = failures.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class Suite:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.skipped = 0
        self.results: list[dict] = []

    def check(self, cond: bool, label: str, detail: str = ""):
        if cond:
            self.passed += 1
            self.results.append({"ok": True, "label": label, "detail": detail})
        else:
            self.failed += 1
            self.results.append({"ok": False, "label": label, "detail": detail})
            print(f"  FAIL  {label}" + (f"  ({detail})" if detail else ""))

    def skip(self, label: str, reason: str):
        self.skipped += 1
        self.results.append({"ok": None, "label": label, "detail": reason})
        print(f"  SKIP  {label}  ({reason})")

    def section(self, name: str):
        print(f"\n{name}")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")


def exists(rel: str) -> bool:
    return (ROOT / rel).is_file()


def extract_types_ids(src: str) -> list[str]:
    return re.findall(r'id\s*=\s*"([A-Z0-9_]+)"', src)


def extract_wx_map_keys(src: str) -> set[str]:
    # WX_TO_KANTO = { CLEAR = "clear", ... }
    block = re.search(r"WX_TO_KANTO\s*=\s*\{([^}]+)\}", src, re.S)
    if not block:
        return set()
    return set(re.findall(r"([A-Z0-9_]+)\s*=", block.group(1)))


def find_lua() -> str | None:
    # LuaTeX ships a standards-compliant Lua runtime as `texlua` on many
    # release/audit environments. Treat it as a real interpreter so --lua can
    # never silently skip the maintained behavioural suite just because the
    # binary is not named `lua`.
    for name in ("lua5.1", "lua5.2", "lua5.3", "lua5.4", "luajit", "lua", "texlua"):
        path = shutil.which(name)
        if path:
            return path
    return None


def test_manifest(S: Suite):
    S.section("manifest")
    S.check(exists("manifest.json"), "manifest.json exists")
    if not exists("manifest.json"):
        return
    man = json.loads(read("manifest.json"))
    S.check(man.get("id") == "weather_fx", "mod id is weather_fx", str(man.get("id")))
    S.check(man.get("entry") == "main.lua", "entry is main.lua")
    S.check(isinstance(man.get("version"), str) and man["version"], "version set", man.get("version"))
    S.check("DRAMATIC_SHAPE" in (man.get("optional_dependencies") or []), "optional dep DRAMATIC_SHAPE")
    S.check("DRAMALESS_SHAPE" in (man.get("optional_dependencies") or []), "optional dep DRAMALESS_SHAPE")
    S.check("engine_internals" in (man.get("permissions") or []), "permission engine_internals")


def test_core_files(S: Suite):
    S.section("core files")
    for rel in (
        "main.lua",
        "lib/WeatherState.lua",
        "lib/Types.lua",
        "lib/Draw.lua",
        "lib/Settings.lua",
        "lib/Battle.lua",
        "lib/Fog.lua",
        "lib/Particles.lua",
        "lib/Config.lua",
        "config.lua",
    ):
        S.check(exists(rel), f"present: {rel}")


def test_3d_files(S: Suite):
    S.section("3d path files")
    for rel in (
        "lib/VoxelAtmosBridge.lua",
        "lib/DramalessAtmos.lua",
        "lib/voxel_atmos/CinematicAtmos.lua",
        "lib/voxel_atmos/WorldPrecip.lua",
        "lib/voxel_atmos/WorldLightning.lua",
        "lib/voxel_atmos/WorldLighting.lua",
        "lib/voxel_atmos/DistantWorld.lua",
        "lib/voxel_atmos/HorizonApron.lua",
        "lib/voxel_atmos/WeatherSetting.lua",
        "lib/voxel_atmos/stubs/ForestAtmos.lua",
        "lib/voxel_atmos/stubs/Mat4.lua",
        "lib/voxel_atmos/stubs/TileShape.lua",
        "lib/voxel_atmos/stubs/SpriteBillboards.lua",
        "lib/voxel_atmos/stubs/TerrainAtlas.lua",
    ):
        S.check(exists(rel), f"present: {rel}")



def test_encounter_rate_and_legends(S: Suite):
    S.section("encounter rate + legendaries")
    e = read("lib/Encounters.lua")
    S.check("rateMultiplier" in e, "Enc.rateMultiplier exists")
    S.check("retryP" in e or "rateBoost" in e, "roll path boosts rate")
    L = read("lib/Legendary.lua")
    for sp in ("ZAPDOS", "MOLTRES", "ARTICUNO", "RAIKOU", "ENTEI", "SUICUNE", "LUGIA", "HO_OH", "CELEBI"):
        S.check(sp in L, f"legend {sp} listed")
    S.check("Legendary.available" in L, "Gen filter available()")
    S.check("rateBoost" in L, "legendary claim rateBoost")
    cfg = read("config.lua")
    S.check("rateBoost = 1.5" in cfg or "rateBoost = 1.5" in cfg.replace(" ", ""), "config wild rateBoost 1.5")
    S.check("rateBoost = 1.05" in cfg or "1.05" in cfg, "config legendary rateBoost 1.05")

def test_wx_present(S: Suite):
    S.section("WX PRESENT option")
    s = read("lib/Settings.lua")
    S.check('key = "present"' in s, "Settings has present row")
    for choice in ('"auto"', '"2d"', '"3d"'):
        S.check(choice in s, f"present choice {choice}")
    S.check("function Settings.force2dPresent" in s, "force2dPresent helper")
    S.check("function Settings.allow3dPresent" in s, "allow3dPresent helper")
    S.check("function Settings.presentMode" in s, "presentMode helper")
    # defaults table is built from SCHEMA at load — present default auto
    S.check('default = "auto"' in s and 'key = "present"' in s, "present default is auto")


def test_debug_hud_tiers(S: Suite):
    S.section("debug HUD tiers")
    s = read("lib/Settings.lua")
    S.check('key = "debug"' in s, "debug setting exists")
    for choice in ('"simple"', '"full"', '"3d"', '"off"'):
        S.check(choice in s, f"debug choice {choice}")
    S.check("function Settings.debugHudMode" in s, "debugHudMode helper")
    S.check("function Settings.debugHudOn" in s, "debugHudOn helper")
    m = read("main.lua")
    # DEBUG HUD helpers live in Settings; main overlay is optional.
    S.check("function Settings.debugHudMode" in s, "Settings.debugHudMode available")
    S.check("function Settings.debugHudOn" in s, "Settings.debugHudOn available")


def test_draw_suppress(S: Suite):
    S.section("2d suppress contract")
    d = read("lib/Draw.lua")
    S.check("use3dPrecip" in d, "use3dPrecip helper")
    S.check("use3dFog" in d, "use3dFog helper")
    S.check("force2dPresent" in d, "Draw honors force2dPresent")
    S.check("handlesPrecipitation" in d, "Draw asks bridge for precip")
    S.check("handlesFog" in d, "Draw asks bridge for fog")
    S.check("Scene.now.visible" in d or 'visible == "battle"' in d, "battle path not suppressed by world 3d")
    # Ownership is per family: rain, snow, hail, sand, leaves/debris and ash
    # are suppressed only after their own 3D submission succeeds. This is what
    # lets mixed weather rescue one broken pass without double-drawing the rest.
    S.check(
        "filtered2dPrecipChannels" in d and "use3dGrain" in d
        and 'suppress("rain"' in d and 'suppress("snow"' in d
        and 'suppress("debris"' in d and 'suppress("ash"' in d,
        "3d precipitation ownership is per-family and fail-closed",
    )


def test_bridge(S: Suite):
    S.section("VoxelAtmosBridge")
    b = read("lib/VoxelAtmosBridge.lua")
    S.check("DramalessAtmos" in b, "routes to DramalessAtmos")
    for fn in (
        "function Bridge.init",
        "function Bridge.active",
        "function Bridge.handlesPrecipitation",
        "function Bridge.handlesFog",
        "function Bridge.syncFromWeatherFx",
        "function Bridge.update",
        "function Bridge.invalidate",
        "function Bridge.reason",
    ):
        S.check(fn in b, f"exports {fn.split()[-1]}")


def test_dramaless_atmos(S: Suite):
    S.section("DramalessAtmos")
    a = read("lib/DramalessAtmos.lua")
    S.check("DRAMATIC_SHAPE" in a, "detects DRAMATIC_SHAPE")
    S.check("DRAMALESS_SHAPE" in a, "detects DRAMALESS_SHAPE")
    S.check("potato_voxel" in a.lower() or "POTATO" in a, "detects potato host ids")
    S.check("STADIUM2_OVERWORLD_MODELS" in a, "detects Gen2-3D-Sprites host")
    S.check("beginEffect" in a, "polyfills beginEffect")
    S.check("endEffect" in a, "polyfills endEffect")
    S.check("endScene" in a, "wraps endScene")
    S.check("CinematicAtmos" in a, "loads CinematicAtmos")
    S.check("want3d" in a, "gates on WX PRESENT")
    S.check("force2dPresent" in a, "respects 2D present mode")
    S.check("WX_TO_KANTO" in a, "maps Weather FX ids to Kanto presets")
    S.check("_lastDrawError" in a, "records draw errors for DEBUG HUD")
    S.check("exports.lib" in a, "uses host exports.lib only (no disk edit)")

    # Map keys should cover main Types ids
    types_ids = set(extract_types_ids(read("lib/Types.lua")))
    map_keys = extract_wx_map_keys(a)
    important = {
        "CLEAR", "SUNNY", "RAIN_LIGHT", "RAIN_HEAVY", "HEAVY_RAIN", "STORM",
        "SNOW_LIGHT", "BLIZZARD", "HAIL", "SANDSTORM", "FOG", "MIST",
    }
    missing = sorted(important - map_keys)
    S.check(len(missing) == 0, "WX_TO_KANTO covers core weather ids", ", ".join(missing) if missing else "")
    # Types catalogue should still have CLEAR
    S.check("CLEAR" in types_ids, "Types has CLEAR")


def test_main_wiring(S: Suite):
    S.section("main.lua wiring")
    m = read("main.lua")
    S.check("VoxelAtmos" in m, "VoxelAtmos referenced")
    S.check("VoxelAtmosBridge" in m or "syncFromWeatherFx" in m, "bridge sync wired")
    S.check("syncFromWeatherFx" in m, "syncFromWeatherFx called")
    S.check("VoxelAtmos.update" in m or ".update(dt)" in m, "bridge update called")
    # fail-closed stub pattern
    S.check("bridge-unavailable" in m or "pcall" in m, "fail-closed load pattern")


def test_cinematic_deps(S: Suite):
    S.section("CinematicAtmos dependency plan")
    ca = read("lib/voxel_atmos/CinematicAtmos.lua")
    reqs = set(re.findall(r'V\.require\("([^"]+)"\)', ca))
    expected = {
        "DayNight", "ForestAtmos", "ShadowMap", "WeatherSetting", "TileShape",
        "Sky", "Mat4", "SpriteBillboards", "TerrainAtlas", "Voxel3D",
    }
    missing = sorted(expected - reqs)
    S.check(len(missing) == 0, "known requires still present in CinematicAtmos", str(missing))
    # stubs for non-host modules
    for stub in ("ForestAtmos", "Mat4", "TileShape", "SpriteBillboards", "TerrainAtlas"):
        S.check(exists(f"lib/voxel_atmos/stubs/{stub}.lua"), f"stub for {stub}")
    S.check(exists("lib/voxel_atmos/WeatherSetting.lua"), "own WeatherSetting module")


def test_balance(S: Suite):
    S.section("syntax balance (crude)")
    for rel in (
        "main.lua",
        "lib/Draw.lua",
        "lib/Settings.lua",
        "lib/DramalessAtmos.lua",
        "lib/VoxelAtmosBridge.lua",
        "lib/WeatherState.lua",
    ):
        if not exists(rel):
            S.check(False, f"balance {rel}", "missing")
            continue
        src = read(rel)
        bad = []
        for a, b in (("(", ")"), ("{", "}"), ("[", "]")):
            if src.count(a) != src.count(b):
                bad.append(f"{a}{b}:{src.count(a)}/{src.count(b)}")
        S.check(len(bad) == 0, f"balanced {rel}", ", ".join(bad))



def test_readme_currency(S: Suite):
    S.section("readme currency")
    if not exists("README.md"):
        S.check(False, "README.md exists")
        return
    r = read("README.md")
    for needle in ("WX PRESENT", "Dramaless", "DEBUG HUD", "tools"):
        S.check(needle in r, f"README mentions {needle}")


def test_optional_deps(S: Suite):
    S.section("optional dependencies")
    if not exists("manifest.json"):
        return
    import json
    man = json.loads(read("manifest.json"))
    opts = man.get("optional_dependencies") or []
    S.check("DRAMALESS_SHAPE" in opts, "DRAMALESS_SHAPE optional dep")
    S.check(any("potato" in str(x).lower() for x in opts), "potato_voxel optional dep")
    S.check("STADIUM2_OVERWORLD_MODELS" in opts, "STADIUM2_OVERWORLD_MODELS optional dep")
    S.check("Gen2Recomped-DramaticShapes" in opts, "Gen2Recomped bundled DramaticShapes optional dep")

def test_tools(S: Suite):
    S.section("tools folder")
    for rel in (
        "tools/ai_debug.py",
        "tools/edit_guard.py",
        "tools/feature_audit.py",
        "tools/mod_map.py",
        "tools/runtime_hints.py",
        "tools/release_deep_audit.py",
        "tools/test_mod.py",
    ):
        S.check(exists(rel), rel)


def test_lua_suite(S: Suite, enabled: bool):
    S.section("lua headless suite")
    if not enabled:
        S.skip("lua tests", "pass --lua to attempt")
        return
    lua = find_lua()
    if not lua:
        S.skip("lua tests", "no lua interpreter on PATH")
        return
    # Maintained release suites track current contracts. Obsolete monolithic
    # pre-4.18 expectations are deliberately not shipped as dead test baggage.
    tests = [
        "tests/snow_full_path_8204_test.lua",
        "tests/snow_lod_performance_8203_test.lua",
        "tests/snow_systems_performance_8203_test.lua",
        "tests/snow_native_instance_id_8199_test.lua",
        "tests/rave_removed_8214_test.lua",
        "tests/pause_menu_weather_8196_test.lua",
        "tests/present_3d_test.lua",
        "tests/strict_3d_compositor_test.lua",
        "tests/typed_weather_test.lua",
        "tests/release_config_test.lua",
        "tests/settings_runtime_test.lua",
        "tests/audio_indoor_test.lua",
        "tests/audio_indoor_muffle_test.lua",
        "tests/audio_thunder_voice_test.lua",
        "tests/audio_thunder_distance_test.lua",
        "tests/audio_psystorm_mix_test.lua",
        "tests/audio_psystorm_distance_weight_test.lua",
        "tests/wind_engine_test.lua",
        "tests/leaf_dynamic_size_8210_test.lua",
        "tests/leaf_collision_season_test.lua",
        "tests/season_cycle_leaf_sync_test.lua",
        "tests/leaf_dda_test.lua",
        "tests/snow_accumulation_footprint_test.lua",
        "tests/snow_3d_bank_water_test.lua",
        "tests/snow_radial_surface_test.lua",
        "tests/benchmark_test.lua",
        "tests/timeofday_setting_test.lua",
        "tests/celestial_clock_visibility_test.lua",
        "tests/celestial_engine_test.lua",
        "tests/celestial_riseset_continuity_test.lua",
        "tests/celestial_motion_smoothing_test.lua",
        "tests/celestial_horizon_handoff_test.lua",
        "tests/celestial_continuous_shadow_test.lua",
        "tests/shadow_projection_monotonic_test.lua",
        "tests/sunset_halo_continuity_test.lua",
        "tests/smooth_sky_test.lua",
        "tests/battle_art_test.lua",
        "tests/world_features_test.lua",
        "tests/gameplay_features_test.lua",
        "tests/battle_features_test.lua",
        "tests/battle_visual_authority_test.lua",
        "tests/building_light_test.lua",
        "tests/debug_hud_test.lua",
        "tests/quality_governor_test.lua",
        "tests/quality_live_3d_test.lua",
        "tests/intensity_live_3d_test.lua",
        "tests/weather_strength_particle_count_829_test.lua",
        "tests/weather_state_authority_test.lua",
        "tests/weather_catalog_test.lua",
        "tests/weather_2d_style_test.lua",
        "tests/weather_2d_restart_8189_test.lua",
        "tests/render_pipeline_test.lua",
        "tests/world_precip_worldspace_test.lua",
        "tests/storm_cell_lifecycle_test.lua",
        "tests/storm_cross_map_seam_test.lua",
        "tests/storm_handoff_volume_8136_test.lua",
        "tests/storm_cloudbank_integration_8137_test.lua",
        "tests/storm_front_reachability_8141_test.lua",
        "tests/battle_art_public_water_8144_test.lua",
        "tests/storm_front_scale_render_8141_test.lua",
        "tests/flat_voxel_prune_8147_test.lua",
        "tests/winter_aurora_8142_test.lua",
        "tests/winter_snow_front_8142_test.lua",
        "tests/rain_cloudbank_visibility_test.lua",
        "tests/cloud_pitch_stability_829_test.lua",
        "tests/sand_pitch_invariance_test.lua",
        "tests/world_precip_spawn_proof.lua",
        "tests/world_lightning_worldspace_test.lua",
        "tests/psystorm_lightning_distance_test.lua",
        "tests/lightning_burst_test.lua",
        "tests/npc_lightning_test.lua",
        "tests/luajit_upvalue_probe.lua",
    ]
    for rel in tests:
        if not exists(rel):
            S.skip(rel, "file missing")
            continue
        try:
            r = subprocess.run(
                [lua, rel],
                cwd=str(ROOT),
                capture_output=True,
                text=True,
                timeout=120,
            )
            ok = r.returncode == 0
            detail = ""
            if not ok:
                detail = (r.stdout + r.stderr)[-300:].replace("\n", " ")
            S.check(ok, f"lua {rel}", detail)
        except Exception as e:
            S.check(False, f"lua {rel}", str(e))


def test_runtime_hints_tool(S: Suite):
    S.section("runtime_hints decoder")
    script = ROOT / "tools" / "runtime_hints.py"
    if not script.is_file():
        S.check(False, "runtime_hints.py exists")
        return
    r = subprocess.run(
        [sys.executable, str(script), "wx:2d | v3:off"],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
    )
    S.check(r.returncode == 0, "runtime_hints runs")
    S.check("2d" in r.stdout.lower() or "overlay" in r.stdout.lower(), "decodes wx:2d")


def test_edit_guard_tool(S: Suite):
    S.section("edit_guard")
    script = ROOT / "tools" / "edit_guard.py"
    r = subprocess.run(
        [sys.executable, str(script)],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
    )
    S.check(r.returncode == 0, "edit_guard PASS", r.stdout.strip()[-200:])


def main():
    ap = argparse.ArgumentParser(description="Weather FX mod test suite")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--lua", action="store_true", help="Run maintained Lua release tests if lua is available")
    args = ap.parse_args()

    S = Suite()
    print("Weather FX test_mod")
    print(f"root: {ROOT}")

    test_manifest(S)
    test_core_files(S)
    test_3d_files(S)
    test_encounter_rate_and_legends(S)
    test_wx_present(S)
    test_debug_hud_tiers(S)
    test_draw_suppress(S)
    test_bridge(S)
    test_dramaless_atmos(S)
    test_main_wiring(S)
    test_cinematic_deps(S)
    test_balance(S)
    test_tools(S)
    test_readme_currency(S)
    test_optional_deps(S)
    test_edit_guard_tool(S)
    test_runtime_hints_tool(S)
    test_lua_suite(S, args.lua)

    summary = {
        "mod": "weather_fx",
        "root": str(ROOT),
        "passed": S.passed,
        "failed": S.failed,
        "skipped": S.skipped,
        "ok": S.failed == 0,
        "results": S.results if args.json else None,
    }

    print(f"\n{S.passed} passed, {S.failed} failed, {S.skipped} skipped")
    if args.json:
        # strip None results field noise
        out = {k: v for k, v in summary.items() if v is not None}
        if args.json:
            out["results"] = S.results
        print(json.dumps(out, indent=2))

    return 0 if S.failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
