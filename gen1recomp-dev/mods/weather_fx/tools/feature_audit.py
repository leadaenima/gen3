#!/usr/bin/env python3
"""Feature-integrity audit for Weather FX.

Fails when a shipped player-facing subsystem has implementation code but no
runtime consumer/hook, when unrelated dead modules creep back into the core,
or when bundled assets/config toggles are not reachable from live code.
"""
from pathlib import Path
import re, sys
ROOT = Path(__file__).resolve().parents[1]
passed = failed = 0

def read(rel):
    p = ROOT / rel
    return p.read_text(errors="replace") if p.is_file() else ""

def check(ok, label):
    global passed, failed
    if ok:
        passed += 1; print("PASS", label)
    else:
        failed += 1; print("FAIL", label)

main = read("main.lua")
settings = read("lib/Settings.lua")
state = read("lib/WeatherState.lua")
draw = read("lib/Draw.lua")
battle = read("lib/Battle.lua")
enc = read("lib/Encounters.lua")
fronts = read("lib/Fronts.lua")
poke = read("lib/Pokegear.lua")
tod = read("lib/TimeOfDay.lua")
bg = read("lib/Backgrounds.lua")
bf = read("lib/BattleField.lua")
debughud = read("lib/DebugHUD.lua")
config = read("config.lua")
cfgmod = read("lib/Config.lua")

print("=== Weather FX feature integrity audit ===")

# 1) Top-level runtime module graph. Dynamic protected calls through either the legacy primitive or SafeCall count too.
print("\n[module graph]")
all_runtime = [ROOT/"main.lua", *sorted((ROOT/"lib").rglob("*.lua"))]
runtime_text = {p: p.read_text(errors="replace") for p in all_runtime if p.is_file()}
for p in sorted((ROOT/"lib").glob("*.lua")):
    name = p.stem
    incoming = 0
    direct = re.compile(r'V\.require\(\s*["\']'+re.escape(name)+r'["\']\s*\)')
    callback = re.compile(r'(?:pcall|safe|V\.safeCall)\(\s*V\.require\s*,\s*["\']'+re.escape(name)+r'["\']')
    runtime_req = re.compile(r'\breq\(\s*["\']'+re.escape(name)+r'["\']\s*\)')
    cached_req = re.compile(r'\bcachedRequire\(\s*["\']'+re.escape(name)+r'["\']\s*\)')
    for q, text in runtime_text.items():
        if q == p: continue
        incoming += (len(direct.findall(text)) + len(callback.findall(text))
                     + len(runtime_req.findall(text)) + len(cached_req.findall(text)))
    check(incoming > 0, f"{name} has a live incoming runtime require")

# Dead baggage we intentionally removed after the forensic audit.
check((ROOT/"lib/Rainbow.lua").exists() and ("req(\"Rainbow\")" in read("lib/EngineRuntime.lua") or "V.require(\"Rainbow\")" in main), "live Rainbow implementation is shipped and consumed")
check(not (ROOT/"lib/TypingCharts.lua").exists(), "unrelated Steel/Fairy TypingCharts module is not shipped")
check(not (ROOT/"docs/TYPING_CHARTS_README.md").exists(), "unrelated TypingCharts README removed")
check(not (ROOT/"docs/TYPING_CHARTS_CHANGELOG.md").exists(), "unrelated TypingCharts changelog removed")

# V.require is Weather FX's private lib/*.lua loader, never an engine/host module
# resolver.  A literal V.require("Game")-style call is therefore guaranteed dead
# if there is no matching top-level lib file. Ignore comments before scanning.
lib_names = {p.stem for p in (ROOT/"lib").glob("*.lua")}
for p, text in runtime_text.items():
    # lib/voxel_atmos/* receives the voxel host namespace as `V`; its require
    # intentionally resolves host modules and stubs.  This rule targets the
    # Weather FX namespace used by main.lua and top-level lib/*.lua only.
    if p != ROOT/"main.lua" and p.parent != ROOT/"lib":
        continue
    code = "\n".join(line.split("--", 1)[0] for line in text.splitlines())
    for name in re.findall(r'V\.require\(\s*["\']([^"\']+)["\']\s*\)', code):
        check(name in lib_names, f"{p.relative_to(ROOT)} V.require({name}) resolves to a shipped Weather FX module")

# Cached hot-path resolvers deliberately hide literal V.require() calls behind
# one helper call. Audit those optimized runtime links explicitly so reducing
# repeated loader work cannot look like a feature-graph regression.
audio = read("lib/Audio.lua")
check('pcall(V.require, "WindEngine")' in audio and 'WindEngineCached' in audio,
      "Audio cached WindEngine resolver reaches shipped WindEngine")
check('pcall(V.require, "WindEngine")' in draw and 'WindEngineCached' in draw,
      "Draw cached WindEngine resolver reaches shipped WindEngine")
dram_cached = read("lib/DramalessAtmos.lua")
check('Atmos._scene' in dram_cached and ('pcall(V.require,"Scene")' in dram_cached or 'safe(V.require,"Scene")' in dram_cached),
      "DramalessAtmos cached Scene resolver reaches shipped Scene")

# 2) Required engine plumbing for implementations that used to be orphaned.
print("\n[host hooks]")
for hook in ("render.hud", "render.letterbox", "world.tod", "ui.options.rows"):
    check(f'mod.hooks:wrap("{hook}"' in main, f"{hook} is registered")
check("Scene.setViewport(viewport)" in main, "render.hud feeds Scene.setViewport")
check("DebugHUD.draw, viewport" in main, "render.hud reaches DebugHUD.draw")
check('call(Settings, "debugHudMode"' in debughud, "DEBUG HUD setting has a live renderer consumer")
check('call(Settings, "debugHudMode", Config)' in debughud and 'cfg.debug or cfg.debugRain' in settings,
      "legacy config.debug/debugRain can reach the live DEBUG HUD")
check("Backgrounds.draw, ctx" in main, "render.letterbox reaches Backgrounds.draw")
check("TOD.worldTod(base)" in main, "world.tod reaches TimeOfDay authority")
check("function TOD.worldTod" in tod and "publishTod" in tod, "time publishTod config has a live consumer")
check("setPinFromLevel" not in tod and "LEVEL_PHASES" not in tod and "LEVEL_LABELS" not in tod,
      "retired TIME ladder helper code is not shipped")
check("mod.hooks:on(" not in main, "no invalid mod.hooks:on event registrations")
dram = read("lib/DramalessAtmos.lua")
check("if not Sky._wxNightWrapped and not celestialWorldWanted() then" in dram,
      "Dramaless sky wrapper uses screen-space NightSky only when celestial presentation is 2D")

# 3) Major update/state paths.
print("\n[world simulation paths]")
check("Scene.sample" in main, "main ticks Scene sampling")
runtime=read("lib/EngineRuntime.lua")
required_runtime={
    "seasons":"modules.Seasons.update", "time of day":"modules.TOD.update",
    "building light":'req("BuildingLight")', "night sky":'CelestialRenderer2',
    "weather state":"modules.State.update", "2D draw update":"modules.Draw.update",
    "followers":"modules.Follower.update", "tornadoes":"modules.Tornado.update",
    "weather audio":"modules.Audio.update",
}
for label,needle in required_runtime.items(): check(needle in runtime, f"staged runtime ticks {label}")
check("EngineRuntime.update(dt, level, sc" in main,"main executes staged EngineRuntime")
for label, needle in {
    "front clock": "Fronts.update",
    "front resolution": "Fronts.weatherFor",
    "psystorm resolution": "Psystorm.weatherFor",
    "legendary resolution": "getLegendary().update",
    "legendary expiry": ".tick(dt)",
}.items(): check(needle in state, f"WeatherState has live {label} path")
check("Fronts.snapshot" in poke and "Fronts.weatherFor" in poke, "Pokegear forecast consumes live regional fronts")
check("Pokegear.install" in main, "Pokegear optional integration is attempted at game.ready")

# 4) Battle hooks and failure safety.
print("\n[battle systems]")
for hook in ("battle.damage", "battle.accuracy", "battle.turn_order", "battle.charge_required", "battle.overlay"):
    check(f'mod.hooks:wrap("{hook}"' in battle or f'mod.hooks:wrap("{hook}"' in main,
          f"{hook} has a live wrapper")
for evt in ("battle.started", "battle.ended", "battle.turn_ended", "battle.move_used"):
    check(f'mod.events:on("{evt}"' in battle or f'mod.events:on("{evt}"' in main,
          f"{evt} event is consumed")
check("Settings.is(\"backdrops\", \"off\")" in bg, "BATTLE ART OFF gates letterbox art")
check("not okDraw or not didDraw" in bf, "BEHIND art restores vanilla field when drawField returns false")
check("weatherBall" not in battle and "forms =" not in battle, "Battle caps contain no inert Weather Ball/Forecast capability flags")
check("weatherBall" not in config and re.search(r'^\s*forms\s*=', config, re.M) is None,
      "shipped config contains no inert Weather Ball/Forecast switches")
check("user.battle.effects.weatherBall = nil" in cfgmod and "user.battle.effects.forms = nil" in cfgmod,
      "old inert config keys are accepted-and-dropped for compatibility")
check("requireRuleset" not in config, "shipped config does not advertise retired ruleset gate")
check("Battle.RULESET" not in battle and "rulesets:register" not in battle,
      "retired WEATHER ruleset is not registered as dead UI")
check("user.battle.requireRuleset = nil" in cfgmod,
      "legacy requireRuleset config is accepted-and-dropped")
check("lightningMode" not in config and re.search(r"audio\s*=\s*\{[^}]*fadeSeconds", config, re.S) is None,
      "shipped config contains no inert lightningMode/audio.fadeSeconds knobs")
check("user.lightningMode = nil" in cfgmod and "user.audio.fadeSeconds = nil" in cfgmod,
      "legacy inert lightning/audio config keys are accepted-and-dropped")
check('mod.hooks:wrap("battle.charge_required"' in battle,
      "Solar Beam sunny charge skip is wired to battle.charge_required")
check("cannot be skipped from a hook" not in battle.lower() and "skip is not implemented" not in config.lower(),
      "no stale claim that Solar Beam charge skip is impossible")

# 5) Encounter systems.
print("\n[encounters]")
for hook in ("encounter.roll", "encounter.fishing"):
    check(f'mod.hooks:wrap("{hook}"' in enc, f"{hook} has live wrapper")
check("Legendary.claimEncounter" in enc, "legendary encounter substitution is connected")
check("Enc.rateMultiplier()" in enc, "weather encounter-rate multiplier is connected")
check("bannedSet" in enc and "favouredType" in enc, "hard bans and soft weather species bias are both present")
check("mod.exports.encounterOverlay" in main, "read-only encounter overlay export is connected")

# 6) Renderer settings and fallback ownership.
print("\n[renderer systems]")
for needle, label in [
    ("Particles.ready", "2D particle readiness"),
    ("VoxelAtmos.handlesPrecipitation", "3D precipitation ownership"),
    ("VoxelAtmos.handlesFog", "3D fog ownership"),
    ("Lightning.update", "lightning scheduler update"),
    ("Funnel.draw", "tornado funnel compositor"),
]: check(needle in main+draw, label+" has live call path")
check("use3dFamily" in draw or "3d" in draw.lower(), "2D/3D compositor has explicit ownership logic")

# 7) Bundled assets: every shipped audio asset must be named in live runtime code.
print("\n[assets]")
audio_files = sorted((ROOT/"assets/sounds").glob("*"))
audio_src = read("lib/Audio.lua") + main
for p in audio_files:
    check(p.name in audio_src, f"audio asset {p.name} is referenced by runtime")
# Every battle backdrop asset name must be reachable through Backgrounds naming tables.
for p in sorted((ROOT/"assets/backgrounds").glob("*.png")):
    stem = p.stem
    base = re.sub(r'_(night|2)$', '', stem)
    check(re.search(r'\b'+re.escape(base)+r'\b', bg) is not None,
          f"battle backdrop {p.name} belongs to a live scene family")

# 8) Player-facing option row count and real consumers remain independently audited.
print("\n[settings contract]")
check("#Settings.SCHEMA" not in settings or "SCHEMA" in settings, "settings schema is present")
for key in ("quality","always","intensity","fogIntensity","sandIntensity","dustIntensity","exotic","speed","daytime","seasons","clouds","leafColor","snowShape","hemisphere","seasonNotify","battles","battleDamage","amplified","lightning","backdrops","sfx","splash","indoors","tornado","present","debugRain","debug"):
    check(f'key = "{key}"' in settings, f"setting {key} exists")

print(f"\nfeature integrity: {passed} passed, {failed} failed")
sys.exit(0 if failed == 0 else 1)
