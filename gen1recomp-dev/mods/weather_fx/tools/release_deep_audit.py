#!/usr/bin/env python3
"""Weather FX release-candidate deep audit.

Release-only inventory/checker.  The normal run_all suite proves behavioural
contracts; this tool additionally inventories every player setting and shipped
media asset and re-runs the broad presentation/audio/runtime contracts so a
release review cannot accidentally omit an entire surface.
"""
from __future__ import annotations
from pathlib import Path
import json, re, shutil, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
failures=[]
passed=0

def check(ok: bool, msg: str):
    global passed
    if ok:
        passed += 1
        print('PASS', msg)
    else:
        failures.append(msg)
        print('FAIL', msg)

def text(rel):
    return (ROOT/rel).read_text(encoding='utf-8', errors='replace')

def run(label, cmd, expected=None, timeout=120):
    try:
        r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=timeout)
    except Exception as e:
        check(False, f'{label}: could not run ({e})')
        return ''
    out=(r.stdout or '')+(r.stderr or '')
    ok=r.returncode==0 and (expected is None or expected in out)
    check(ok, label)
    if not ok:
        print(out[-1600:])
    return out

print('=== RELEASE IDENTITY ===')
man=json.loads(text('manifest.json'))
base=text('BASELINE').strip()
check(man.get('id')=='weather_fx','manifest id is weather_fx')
check(man.get('version')==base, f'manifest version matches BASELINE ({base})')
check(man.get('games')==['gen1','gen2'], 'manifest supports both gen1 and gen2')

print('\n=== SETTINGS — EVERY PLAYER ROW ===')
settings=text('lib/Settings.lua')
schema=settings[settings.index('Settings.SCHEMA = {'):settings.index('-- Build the ALWAYS row')]
keys=re.findall(r'^\s{4}key\s*=\s*"([^"]+)"',schema,re.M)
check(len(keys)==80 and len(set(keys))==80, f'exactly 80 unique settings ({len(keys)})')
print('INFO settings:', ', '.join(keys))
run('70-setting static/live consumer audit', [sys.executable,'tools/test_settings_runtime.py'], 'settings/runtime audit:')
run('70-setting executable option audit', ['texlua','tests/settings_runtime_test.lua'], 'settings runtime:')
run('advanced setting config/runtime pipeline', ['texlua','tests/settings_advanced_pipeline_test.lua'], 'advanced settings pipeline: 42 passed, 0 failed')
run('grouped in-game settings menu', ['texlua','tests/settings_menu_test.lua'], 'settings menu: 32 passed, 0 failed')
run('release config/schema audit', ['texlua','tests/release_config_test.lua'], 'release config')

print('\n=== WEATHER + ANIMATION/PRESENTATION CATALOGUE ===')
types=text('lib/Types.lua')
weather_ids=re.findall(r'^\s{4}id\s*=\s*"([A-Z0-9_]+)"',types,re.M)
# entries use exactly one top-level id line; filter preserves order/uniqueness
seen=[]
for x in weather_ids:
    if x not in seen: seen.append(x)
weather_ids=seen
check(len(weather_ids)==29, f'29 distinct weather definitions ({len(weather_ids)})')
print('INFO weather ids:', ', '.join(weather_ids))
run('weather catalogue/channel executable audit', ['texlua','tests/weather_catalog_test.lua'], 'weather catalog: 173 passed, 0 failed')
run('2D weather style/animation audit', ['texlua','tests/weather_2d_style_test.lua'], 'weather_2d_style_test: 94 passed, 0 failed')
run('3D/2D render pipeline animation audit', ['texlua','tests/render_pipeline_test.lua'], 'render pipeline audit: 352 passed, 0 failed')
run('3D pipeline static/runtime contract', [sys.executable,'tools/test_3d_pipeline_integrity.py'], '3D pipeline integrity: 117 passed, 0 failed')
run('world precipitation/LuaJIT dialect contract', [sys.executable,'tools/test_world_precip.py'], 'PASS world precip')

print('\n=== SNOWPACK 8.1.28 FLAT-WORLD REDESIGN ===')
sp=text('lib/SnowPack.lua'); wp=text('lib/voxel_atmos/WorldPrecip.lua')
check('SP.ACCUMULATION_ENABLED = true' in sp, 'persistent snow accumulation redesign is enabled')
check('SP and SP.ACCUMULATION_ENABLED and SP.beginFrame' in wp, 'live persistent snow staging is hard-gated')
run('snow accumulation/footprints executable audit', ['texlua','tests/snow_accumulation_footprint_test.lua'], 'snow accumulation/footprints 8.1.28: 14 passed, 0 failed')
run('snow radial surface executable audit', ['texlua','tests/snow_radial_surface_test.lua'], 'snow radial surfaces 8.1.28: 10 passed, 0 failed')
run('snow bank/water executable audit', ['texlua','tests/snow_3d_bank_water_test.lua'], 'snow 3D bank/water 8.1.28: 7 passed, 0 failed')

print('\n=== EVERY SHIPPED SOUND ===')
sound_dir=ROOT/'assets/sounds'
sounds=sorted(p for p in sound_dir.iterdir() if p.is_file())
check(len(sounds)==9, f'9 shipped sound assets ({len(sounds)})')
main=text('main.lua'); audio=text('lib/Audio.lua'); refs=main+'\n'+audio+'\n'+text('lib/Legendary.lua')
ffprobe=shutil.which('ffprobe')
check(bool(ffprobe),'ffprobe available for real media decode/probe')
for p in sounds:
    rel=p.relative_to(ROOT).as_posix()
    check(rel in main, f'{p.name}: registered in runtime asset table')
    check(p.stem in refs, f'{p.name}: referenced by runtime audio logic')
    if ffprobe:
        r=subprocess.run([ffprobe,'-v','error','-select_streams','a:0','-show_entries','stream=codec_name,sample_rate,channels','-show_entries','format=duration','-of','default=nw=1',str(p)],capture_output=True,text=True)
        check(r.returncode==0 and 'codec_name=' in r.stdout and 'duration=' in r.stdout, f'{p.name}: decodes/probes successfully')
        if r.returncode==0:
            meta='; '.join(x.strip() for x in r.stdout.splitlines() if x.strip())
            print('INFO ',p.name,meta)
run('indoor weather audio executable audit', ['texlua','tests/audio_indoor_test.lua'])
run('indoor muffling executable audit', ['texlua','tests/audio_indoor_muffle_test.lua'])
run('thunder voice/overlap audit', ['texlua','tests/audio_thunder_voice_test.lua'])
run('distance thunder executable audit', ['texlua','tests/audio_thunder_distance_test.lua'])
run('Psychic Storm half-cadence/mix audit', ['texlua','tests/audio_psystorm_mix_test.lua'])
run('Psychic Storm distance-weight audit', ['texlua','tests/audio_psystorm_distance_weight_test.lua'])
run('thundersnow/audio static contract', [sys.executable,'tools/test_tsnow_audio.py'])
run('weather thunder authority contract', [sys.executable,'tools/test_weather_thunder_authority.py'], 'weather thunder authority: 110 passed, 0 failed')

print('\n=== EVERY SHIPPED BATTLE BACKGROUND ===')
bg_dir=ROOT/'assets/backgrounds'; bgs=sorted(p for p in bg_dir.iterdir() if p.is_file())
check(len(bgs)==23, f'23 shipped battle background PNGs ({len(bgs)})')
bgsrc=text('lib/Backgrounds.lua')
try:
    from PIL import Image
    pil=True
except Exception:
    pil=False
check(pil,'Pillow available for PNG decode/shape audit')
# Background filenames are generated dynamically from BG.SCENES rather than
# being listed literally. Reconstruct the exact expected asset set from that catalogue.
scene_block=bgsrc[bgsrc.index('BG.SCENES = {'):bgsrc.index('-- Weather first.')]
expected_bg=set()
for m in re.finditer(r'^\s{2}([a-z_]+)\s*=\s*\{([^}]*)\}', scene_block, re.M):
    scene, flags=m.group(1),m.group(2)
    expected_bg.add(scene+'.png')
    if 'alt = true' in flags: expected_bg.add(scene+'_2.png')
    if 'night = true' in flags: expected_bg.add(scene+'_night.png')
check({p.name for p in bgs}==expected_bg, 'background files exactly match BG.SCENES generated variants')
for p in bgs:
    check(p.name in expected_bg, f'{p.name}: generated by background scene catalogue')
    if pil:
        try:
            with Image.open(p) as im:
                im.verify()
            with Image.open(p) as im:
                check(im.size==(240,112) and im.mode=='RGBA', f'{p.name}: valid 240x112 RGBA')
        except Exception as e:
            check(False,f'{p.name}: image decode failed ({e})')
run('battle background/art executable audit', ['texlua','tests/battle_art_test.lua'])
run('battle weather feature executable audit', ['texlua','tests/battle_features_test.lua'])
run('battle visual ownership executable audit', ['texlua','tests/battle_visual_authority_test.lua'])

print('\n=== WORLD EFFECTS / ANIMATIONS ===')
# Module presence is an inventory guard; behavioural tests below exercise them.
modules={
 '2D precipitation':'lib/Particles.lua', 'fog':'lib/Fog.lua', 'draw compositor':'lib/Draw.lua',
 '3D precipitation':'lib/voxel_atmos/WorldPrecip.lua','3D lightning':'lib/voxel_atmos/WorldLightning.lua',
 '3D atmosphere/clouds':'lib/voxel_atmos/CinematicAtmos.lua','wind':'lib/WindEngine.lua',
 'leaf physics':'lib/LeafPhysics.lua','night sky':'lib/NightSky.lua','celestial engine':'lib/CelestialEngine.lua',
 'battle weather':'lib/Battle.lua','battle field art':'lib/BattleField.lua','tornado':'lib/Tornado.lua',
}
for name,rel in modules.items(): check((ROOT/rel).is_file() and (ROOT/rel).stat().st_size>0,f'{name}: runtime module present/nonempty')
run('WindEngine executable audit', ['texlua','tests/wind_engine_test.lua'], 'wind engine: 20 passed, 0 failed')
run('leaf collision/season/ground executable audit', ['texlua','tests/leaf_collision_season_test.lua'])
run('15-day season / 2D+3D leaf sync audit', ['texlua','tests/season_cycle_leaf_sync_test.lua'])
run('leaf DDA executable audit', ['texlua','tests/leaf_dda_test.lua'])
run('world feature executable audit', ['texlua','tests/world_features_test.lua'])
run('gameplay feature executable audit', ['texlua','tests/gameplay_features_test.lua'])
run('celestial engine executable audit', ['texlua','tests/celestial_engine_test.lua'])
run('night-sky static contract', [sys.executable,'tools/test_night_sky.py'])
run('benchmark executable audit', [sys.executable,'tools/test_benchmark.py'], 'benchmark: 26 passed, 0 failed')

print('\n=== QUALITY / INTENSITY / LOW-POWER + EXTREME HARDWARE ===')
run('live 3D quality hard-cap audit', ['texlua','tests/quality_live_3d_test.lua'], 'quality live 3D: 13 passed, 0 failed')
run('live 3D intensity audit', ['texlua','tests/intensity_live_3d_test.lua'])
run('quality governor audit', ['texlua','tests/quality_governor_test.lua'])
run('performance invariant audit', [sys.executable,'tools/test_performance_invariants.py'], 'performance invariants: 66 passed, 0 failed')
run('LuaJIT source-limit/upvalue guard (static; not a target-host compiler run)', [sys.executable,'tools/test_luajit_limits.py'])

print('\n=== WEATHER FX 7 WORLD / ENVIRONMENT / PERFORMANCE ENGINE ===')
for rel in ['lib/PerformanceGovernor.lua','lib/Microclimate.lua','lib/CloudField.lua','lib/MaterialSystem.lua','lib/AcousticModel.lua','lib/EnvironmentalEvents.lua','lib/EnvironmentBehavior.lua','lib/EngineHealth.lua',
            'lib/WorldClimate.lua','lib/WindFlow.lua','lib/Hydrology.lua','lib/AccumulationGeometry.lua','lib/DynamicLighting.lua','lib/VolumetricWeather.lua','lib/EcosystemEngine.lua','lib/ForecastEngine.lua','lib/EnvironmentSDK.lua','lib/PredictiveBudget.lua','lib/SevereWeather.lua','lib/TerrainPhysics.lua','lib/EnvironmentPersistence.lua','lib/WeatherPluginRegistry.lua']:
    check((ROOT/rel).is_file() and (ROOT/rel).stat().st_size>0, f'{rel}: runtime module present/nonempty')
run('environment engine 2 static architecture audit', [sys.executable,'tools/test_environment_engine_2.py'], 'environment engine 2 static gate:')
run('environment engine 2 executable audit', ['texlua','tests/environment_engine_2_test.lua'], 'environment engine 2:')
run('environment engine 3 static architecture audit', [sys.executable,'tools/test_environment_engine_3.py'], 'environment engine 3 static gate:')
run('environment engine 3 executable audit', ['texlua','tests/environment_engine_3_test.lua'], 'environment engine 3:')

print('\n=== WEATHER FX 8.0.1 WHOLE-MOD ZERO-QUALITY-LOSS OPTIMIZATION ===')
for rel in ['lib/GPUWeatherEngine.lua','lib/VolumetricRenderer.lua','lib/UnifiedLighting.lua','lib/LightProbeGrid.lua','lib/SurfaceVisualState.lua','lib/SurfaceVisuals.lua','lib/SystemProfiler.lua','lib/WorkloadRouter.lua','lib/WorldStreamer.lua']:
    check((ROOT/rel).is_file() and (ROOT/rel).stat().st_size>0, f'{rel}: 8.x runtime module present/nonempty')
run('8.0.1 performance/regression static gate', [sys.executable,'tools/test_801_performance_and_regressions.py'], '42/42 passed, 0 failed')
run('celestial zenith projection regression', ['texlua','tests/celestial_zenith_quality_test.lua'], '40 passed, 0 failed')
run('realtime weather-audio authority regression', ['texlua','tests/audio_realtime_authority_test.lua'], '8 passed, 0 failed')
run('MAX no-quality-loss performance contract', ['texlua','tests/max_performance_contract_test.lua'], '5 passed, 0 failed')

print('\n=== WEATHER FX 8.0.2 PROCEDURAL FAR-FIELD / LOW-END MAX ENGINE ===')
for rel in ['lib/InstanceSeedBuffer.lua','lib/ProceduralSnowField.lua','lib/ProceduralPrecipField.lua','lib/CelestialStarField.lua']:
    check((ROOT/rel).is_file() and (ROOT/rel).stat().st_size>0, f'{rel}: 8.0.2 procedural module present/nonempty')
run('8.0.2 performance/regression static gate', [sys.executable,'tools/test_802_performance_and_regressions.py'], '31/31 passed, 0 failed')
run('procedural far snow GPU submission', ['texlua','tests/procedural_far_snow_test.lua'], '14 passed, 0 failed')
run('procedural rain/hail/sand/ash GPU submission', ['texlua','tests/procedural_precip_field_test.lua'], '10 passed, 0 failed')
run('snow near-physical/far-procedural virtualization', ['texlua','tests/snow_virtualization_test.lua'], '10 passed, 0 failed')
run('rain/hail/sand/ash virtualization', ['texlua','tests/precip_virtualization_test.lua'], '18 passed, 0 failed')
run('5,120-star static instance catalogue', ['texlua','tests/celestial_star_field_test.lua'], '7 passed, 0 failed')

print('\n=== WEATHER FX 8.0.3 LIVE REGRESSION REPAIR ===')
run('8.0.3 live-regression static gate', [sys.executable,'tools/test_803_regressions.py'], '27/27 passed, 0 failed')
run('NPC lightning face/smoke/configured chance-duration executable', ['texlua','tests/npc_lightning_test.lua'], '42 passed, 0 failed')
run('heavy/storm rain overlay and presentation matrix', ['texlua','tests/render_pipeline_test.lua'], '352 passed, 0 failed')

print('\n=== WEATHER FX 8.1.1 TRUTH-AUDITED FLAT-WORLD + 3D GALE TORNADO ===')
for rel in ['lib/FlatWorldInteraction.lua','lib/voxel_atmos/Tornado3D.lua']:
    check((ROOT/rel).is_file() and (ROOT/rel).stat().st_size>0, f'{rel}: 8.1.x runtime module present/nonempty')
run('8.1.1 truth/flat-world static contract', [sys.executable,'tools/test_811_truth_contract.py'], '8.1.1 truth contract:')
run('presentation ownership executable audit', ['texlua','tests/present_3d_test.lua'], '35 passed, 0 failed')
run('3D Gale tornado / safe-carry executable audit', ['texlua','tests/tornado_3d_test.lua'], '3d Gale tornado: 38 passed, 0 failed')

print('\n=== WEATHER FX 8.1.2 SAFE LANDINGS / RAINBOW / WIND WALKING ===')
for rel in ['lib/Rainbow.lua','lib/WindPlayer.lua','lib/voxel_atmos/Rainbow3D.lua']:
    check((ROOT/rel).is_file() and (ROOT/rel).stat().st_size>0, f'{rel}: 8.1.2 runtime module present/nonempty')
run('8.1.2 safety/static truth contract', [sys.executable,'tools/test_812_safety_contract.py'], '8.1.2 safety contract: 40 passed, 0 failed')
run('tornado destination/Surf softlock audit', ['texlua','tests/tornado_safe_destination_test.lua'], 'tornado safe destinations: 23 passed, 0 failed')
run('post-rain rainbow state/3D submission audit', ['texlua','tests/rainbow_test.lua'], 'rainbow: 11 passed, 0 failed')
run('grid + FPV wind movement audit', ['texlua','tests/wind_player_test.lua'], 'wind player: 15 passed, 0 failed')

print('\n=== WEATHER FX 8.1.11 PLAYER-RUNTIME / STATE CONTINUITY ===')
run('8.1.11 player-runtime static contract', [sys.executable,'tools/test_8111_player_runtime_contract.py'], '8.1.11 player-runtime contract: 23 passed, 0 failed')
run('8.1.11 player-runtime executable regressions', ['texlua','tests/player_runtime_regression_test.lua'], 'player runtime regressions: 40 passed, 0 failed')

print('\n=== WEATHER FX 8.1.10 SNOW / FOG / GAME-SPEED AUTHORITY ===')
run('8.1.10 retained static contract', [sys.executable,'tools/test_8110_contract.py'], '8.1.10 retained contract: 16 passed, 0 failed')
run('Snow Intensity live 2D/3D authority', ['texlua','tests/snow_intensity_pipeline_test.lua'], 'snow intensity pipeline: 13 passed, 0 failed')
run('explicit fog ownership / no snow-ground-mist leak', ['texlua','tests/fog_ownership_matrix_test.lua'], 'fog ownership matrix: 19 passed, 0 failed')

print('\n=== WEATHER FX 8.1.8+ SETTINGS / HOST NIGHT / CONSTELLATION ROLLBACK ===')
run('8.1.8+ settings/time/constellation static contract', [sys.executable,'tools/test_818_settings_time_contract.py'], '8.1.8+ settings/time/constellation contract: 33 passed, 0 failed')
run('complete 68-setting submenu/description audit', ['texlua','tests/settings_description_complete_test.lua'], 'complete settings descriptions:')
run('custom menu -> live setting authority', ['texlua','tests/settings_live_chain_test.lua'], 'settings live chain: 17 passed, 0 failed')
run('next-update 3D quality/cap response', ['texlua','tests/quality_immediate_3d_test.lua'], 'quality immediate 3D: 5 passed, 0 failed')
run('rapid manual intensity response', ['texlua','tests/intensity_control_response_test.lua'], 'intensity control response: 4 passed, 0 failed')
run('host NIGHT -> ordinary stars + constellation submission', ['texlua','tests/host_night_star_spawn_test.lua'], 'host night star spawn: 12 passed, 0 failed')
check('POKEMON_CONSTELLATION_ATLAS_EXACT_TRACE_2026_09_03' in text('lib/Constellations.lua'), 'approved high-detail constellation atlas source is active')
check('USER_KANTO_JOHTO_SPRITE_TRACE_2026_09_02' not in text('lib/Constellations.lua'), 'disliked 8.1.7 full-dex compact batch is absent')
run('25-subject static/runtime constellation catalogue', [sys.executable,'tools/test_constellations.py'], 'RESULT OK 0')
run('retained constellation uniqueness/world-submission audit', ['texlua','tests/constellations_expanded_test.lua'], 'expanded constellations: 65 passed, 0 failed')

print('\n=== WEATHER FX 8.1.5 IMMEDIATE 3D RAIN VISIBILITY ===')
check('local primeRain = wantRain > 0 and (rain.active or 0) <= 0' in text('lib/voxel_atmos/WorldPrecip.lua'), 'rain detects the exact inactive-to-raining activation edge')
check('function WP.rainColumnRange()' in text('lib/voxel_atmos/WorldPrecip.lua'), 'rain exposes an on-demand physical vertical-column diagnostic')
run('first-frame/re-activation cloud-to-ground rain visibility proof', ['texlua','tests/rain_cloudbank_visibility_test.lua'], 'rain cloudbank visibility: 9 passed, 0 failed')

print('\n=== WEATHER FX 8.1.4 LIVE 3D RAIN REPAIR ===')
check('lookFlat' in text('lib/voxel_atmos/WorldPrecip.lua'), 'rain camera cull consumes real host lookFlat')
check('horiz2 < fl2 * 0.0625' in text('lib/voxel_atmos/WorldPrecip.lua'), 'mostly-vertical player-anchor focus is rejected as a camera ray')
run('id-only cloud-bank rain spawn/submission proof', ['texlua','tests/world_precip_spawn_proof.lua'], 'world_precip_spawn_proof: 8 cases, 0 failures')

print('\n=== WEATHER FX 8.1.3 ROBUSTNESS / SILENT-FAILURE HARDENING ===')
check((ROOT/'lib/SafeCall.lua').is_file() and (ROOT/'lib/SafeCall.lua').stat().st_size>0, 'lib/SafeCall.lua: 8.1.3 runtime health authority present/nonempty')
run('SafeCall static/executable contract', [sys.executable,'tools/test_813_safecall.py'], 'SafeCall hardening: 19/19 passed')

print('\n=== COMPLETE MAINTAINED RUNTIME / COMPATIBILITY ===')
run('all maintained Lua runtime regressions', [sys.executable,'tools/test_mod.py','--lua'], '0 failed, 0 skipped', timeout=180)
run('aggressive compatibility audit', [sys.executable,'tools/compat_aggressive.py'], 'HIGH 0')
run('strict architecture audit', [sys.executable,'tools/audit_full.py'], 'HIGH=0')
run('compatibility architecture audit', [sys.executable,'tools/audit_compat.py'])
run('Love sandbox audit', [sys.executable,'tools/test_love_sandbox.py'], 'PASS love sandbox')
run('scope hygiene audit', [sys.executable,'tools/test_scope_hygiene.py'])

print('\n=== DEEP RELEASE AUDIT SUMMARY ===')
print(f'checks passed: {passed}')
print(f'checks failed: {len(failures)}')
if failures:
    for x in failures: print('  -',x)
    sys.exit(1)
print('DEEP RELEASE AUDIT PASS')
