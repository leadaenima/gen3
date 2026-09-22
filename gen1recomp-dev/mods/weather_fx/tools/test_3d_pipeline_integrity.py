#!/usr/bin/env python3
from pathlib import Path
import re, sys

ROOT = Path(__file__).resolve().parents[1]
checks = fails = 0

def ck(ok, msg):
    global checks, fails
    checks += 1
    if ok:
        print('PASS', msg)
    else:
        fails += 1
        print('FAIL', msg)

def txt(rel):
    return (ROOT / rel).read_text(errors='replace')

main = txt('main.lua')
bridge = txt('lib/DramalessAtmos.lua')
cin = txt('lib/voxel_atmos/CinematicAtmos.lua')
wp = txt('lib/voxel_atmos/WorldPrecip.lua')
wl = txt('lib/voxel_atmos/WorldLightning.lua')
types = txt('lib/Types.lua')
rt = txt('tests/render_pipeline_test.lua')
wt = txt('tests/world_precip_worldspace_test.lua')

# State -> bridge -> namespace authority.
runtime=txt('lib/EngineRuntime.lua')
ck('syncFromWeatherFx(modules.State,modules.Settings)' in runtime,
   'staged runtime publishes WeatherState into 3D bridge')
ck(runtime.find('syncFromWeatherFx(modules.State,modules.Settings)') < runtime.find('modules.VoxelAtmos.update(c.animDt)'),
   '3D weather sync happens before 3D update')
ck('cin.notifyWxWeather' in bridge and ('pcall(cin.notifyWxWeather, weatherId)' in bridge or 'safe(cin.notifyWxWeather, weatherId)' in bridge),
   'bridge forwards authoritative weather id')
ck('Atmos._ns.weatherFxId = weatherId' in bridge,
   'bridge publishes authoritative weather id into shared 3D namespace')
ck('local ROOT_OWN = {' in bridge and all(f'{n} = true' in bridge for n in ('Types','Config','Settings','Quality','Scene','TimeOfDay')),
   'voxel namespace prevents host collisions for Weather FX authority modules')
ck('if ROOT_OWN[name] then' in bridge and ('pcall(V.require, name)' in bridge or 'safe(V.require, name)' in bridge),
   'Weather FX authority modules resolve from root before host modules')
ck('resolving[name] = nil' in bridge and 'own[name] = false' not in bridge,
   'failed namespace resolves remain retryable instead of poisoning cache')
ck('WorldPrecip-load-failed:' in bridge and 'Atmos._worldPrecip = wpOrErr' in bridge,
   '3D bridge validates WorldPrecip at install instead of hiding a rain-only fallback')
ck('local UPDATE_CONST = {' in wp,
   'WorldPrecip groups immutable update dependencies for LuaJIT upvalue safety')
ck((ROOT / 'tools/test_luajit_limits.py').is_file(),
   'release ships LuaJIT upvalue-limit gate')
ck((ROOT / 'tests/luajit_upvalue_probe.lua').is_file(),
   'release ships executable LuaJIT closure probe')
ck((ROOT / 'tests/world_precip_spawn_proof.lua').is_file() and 'W.drawStatus()' in txt('tests/world_precip_spawn_proof.lua'),
   'release ships live allocation + submitted-vertex spawn proof')
ck('function WP.drawStatus()' in wp and 'function Atmos.precipProof()' in bridge,
   'runtime exposes actual particle allocation and draw submission proof')

# Six-family channel authority in CinematicAtmos. 8.0.7 deliberately makes
# WeatherState.ch the live authority during staged synoptic handoffs; the exact
# Types definition remains only the compatibility fallback. Requiring direct
# Types.channel(def, ...) assignments here would re-introduce precipitation
# popping at the weather-id commit.
fams = ('rain','snow','hail','sand','ash','debris')
ck('local authoritativeId = tostring((V and V.weatherFxId) or snowState.wxId or ""):upper()' in cin,
   'CinematicAtmos consumes shared Weather FX id directly')
ck('local channelSnapshot = V and V.weatherFxChannels or nil' in cin and
   'local function resolvedChannel(key)' in cin,
   'CinematicAtmos consumes the live eased WeatherState channel snapshot')
ck('Types.channel(def,key)' in cin or 'Types.channel(def, key)' in cin,
   'CinematicAtmos retains exact Types fallback for older hosts')
for fam in fams:
    ck(f'resolvedChannel("{fam}")' in cin or f"resolvedChannel('{fam}')" in cin,
       f'live WeatherState channel reader is wired for {fam}')
    ck(re.search(rf'weather\.{fam}Intensity\s*=\s*', cin) is not None,
       f'CinematicAtmos writes {fam}Intensity')
ck('weather._wxChannelsResolved = liveChannels == true' in cin,
   'CinematicAtmos tags exact live-channel ownership for WorldPrecip')

ck('weather.wxId = wxId' in cin, 'WorldPrecip receives Weather FX id')
ck('precipitationDeckBand' in cin and
   (('deckY = deckY' in cin and 'deckSpan = deckSpan' in cin) or
    'meta.anchorKind,meta.deckY,meta.deckSpan=focKind,deckY,deckSpan' in cin),
   'cloud deck metadata is passed into WorldPrecip')
ck(('WorldPrecip.update(dt, foc, frame.weather' in cin or
    '_safePass("world-precip-update", WorldPrecip.update, dt, foc, frame.weather, meta)' in cin),
   '3D particle simulation update is called')
ck(('WorldPrecip.draw(Voxel3D, frame)' in cin or
    '_safePass("world-precip-draw", WorldPrecip.draw, Voxel3D, frame)' in cin),
   '3D particle draw is called')
ck('allowsLightning' in cin and 'T.hasLightning' in cin and 'WL.clear' in cin,
   '3D lightning is hard-gated by current authored weather and clears on rain-only handoff')
ck('function WL.clear()' in wl and 'WL.clear()' in wl[wl.find('function WL.invalidate()'):],
   'WorldLightning exposes cheap live-bolt clear without discarding shader/mesh cache')
npc = txt('lib/voxel_atmos/NpcLightning.lua')
config = txt('lib/Config.lua')
ck('NpcLightning = "lib/voxel_atmos/NpcLightning.lua"' in bridge and
   (('NL.observe(state)' in bridge and 'NL.update(step)' in bridge and 'NL.draw(Voxel3D)' in bridge) or
    ('_npcLightningForRuntime()' in bridge and ('pcall(NL.observe,state)' in bridge or 'safe(NL.observe,state)' in bridge) and
     ('pcall(NL.update,step)' in bridge or 'safe(NL.update,step)' in bridge) and ('pcall(NL.draw,Voxel3D)' in bridge or 'safe(NL.draw,Voxel3D)' in bridge))),
   'NPC lightning target/reaction module is connected to live 3D scene lifecycle')
ck('forcedImpactForBolt' in cin and 'rollImpact' in cin and 'NL.hit' in cin,
   'each 3D lightning bolt can independently redirect to a visible NPC and trigger reaction')
ck('context.forcedImpact' in wl and 'context.forcedImpactForBolt' in wl and 'npcTarget' in wl,
   'WorldLightning supports per-bolt forced NPC impacts without replacing normal terrain targeting')
ck('PSY_MIN_RADIUS = 160' in wl and 'PSY_NEAR_WEIGHT = 0.04' in wl and 'PSY_MID_WEIGHT = 0.32' in wl,
   'Psychic Storm ordinary terrain placement has explicit distant-biased profile')
ck(('weatherId = lightningWeatherId' in cin or 'weatherId = frame.weather and frame.weather.wxId' in cin) and 'local bands = { "far", "mid", "far", "far" }' in wl,
   'Psychic Storm identity reaches WorldLightning and severe bursts are spread across distance bands')
ck(re.search(r'npcLightning\s*=\s*\{\s*enabled\s*=\s*true,\s*chance\s*=\s*0\.10,\s*duration\s*=\s*3\.0', config) is not None,
   'NPC lightning house-rule defaults are ON / 10 percent / 3 seconds')
ck('VS.drawEntity' in npc and 'Voxel3D.flatten' in npc and 'DURATION = 3.0' in npc and 'CHANCE = 0.10' in npc,
   'NPC reaction is a temporary in-memory black silhouette with requested 10% / 3-second contract')
ck('reactionMetrics' in npc and 'wxEyeAnchor' in npc and 'mode=="side"' in npc and 'mode="back"' in npc,
   'NPC lightning eyes are sprite-card/facing-relative with exact metadata override seam')
ck('drawSmoke' in npc and 'smokeVerts' in npc and 'rm.headY' in npc,
   'NPC lightning emits a small depth-tested head smoke puff after impact')
ck('state.entities' in npc and 'entity.px or entity.x' in npc and 'entity.py or entity.y' in npc and
   'DOES NOT call pose()' in npc and 'visualDescriptor' in npc,
   'live NPC strike admission uses raw overworld coordinates and does not depend on a second pose call')
ck('candidateCount' in npc and 'noCandidateRolls' in npc and 'visibleCandidates' in npc,
   'NPC lightning exposes live candidate/roll diagnostics for in-engine verification')

# WorldPrecip independently reconstructs missing channels before allocation.
ck('local function authoritativeWeatherId(weather)' in wp and 'V.weatherFxId' in wp,
   'WorldPrecip can recover authoritative shared Weather FX id')
ck('local function resolveFamilyIntensities(weather, wxId)' in wp,
   'WorldPrecip has independent family-channel resolver')
for fam in fams:
    ck(re.search(rf'local {fam}I\s*=\s*tonumber\(weather\.{fam}Intensity\)\s*or\s*0', wp) is not None,
       f'WorldPrecip consumes {fam}Intensity')
    ck(re.search(rf'{fam}I\s*=\s*fill\({fam}I,\s*"{fam}"\)', wp) is not None,
       f'WorldPrecip reconstructs missing {fam} from Types')

# Hard floors keep named core weather alive even if a compatibility lookup fails.
for needle, label in (
    ('if (not weather._snowExplicitOff) and isSnowyWx(wxId) and wxId ~= "HAIL" then', 'snow hard floor'),
    ('if wxId == "HAIL" then', 'hail hard floor'),
    ('if wxId == "SANDSTORM" then sandI = max(sandI, 2.35)', 'sandstorm hard floor'),
    ('elseif wxId == "DUSTSTORM" then sandI = max(sandI, 1.20)', 'duststorm hard floor'),
    ('if wxId == "ASHFALL" then ashI = max(ashI, 1.45)', 'ashfall hard floor'),
    ('wxId == "FLOCKSTORM" then', 'wind/debris hard floor'),
):
    ck(needle in wp, label)
ck('weather._sandExplicitOff' in wp, 'explicit sand-off remains authoritative')

# Allocation and draw submission for every family.
ck('ensureRain(rain.simActive)' in wp and 'rain.active,rain.simActive,rain.gpuActive' in wp, 'rain allocation path preserves logical count with physical/procedural split')
ck('ProceduralPrecipField' in wp and 'InstanceSeed' in (ROOT / 'lib/ProceduralPrecipField.lua').read_text(encoding='utf-8', errors='replace') and 'perinstance' in (ROOT / 'lib/ProceduralPrecipField.lua').read_text(encoding='utf-8', errors='replace'), 'far rain/hail/sand/ash use zero-frame-upload GPU per-instance field')
ck((('rain.gpuActive=wantRain-rain.simActive' in wp) or ('rain.gpuActive=wantRain' in wp and 'rain.simActive=min(wantRain,96)' in wp)) and 'for i = 1, rain.simActive do' in wp, 'rain virtualization removes non-interaction visual population from CPU integration without reducing logical target')
ck('ensureSnow(wantSnowSim)' in wp and 'snow.active,snow.simActive,snow.gpuActive' in wp, 'snow allocation path preserves logical count with physical/procedural split')
ck('ProceduralSnowField' in wp and 'InstanceSeed' in (ROOT / 'lib/ProceduralSnowField.lua').read_text(encoding='utf-8', errors='replace') and 'perinstance' in (ROOT / 'lib/ProceduralSnowField.lua').read_text(encoding='utf-8', errors='replace'), 'far snow uses zero-frame-upload GPU per-instance field')
ck((('wantSnow-wantSnowSim' in wp) or ('gpuSnow=wantSnow' in wp and 'qb.snowProbeCap' in wp)) and 'for i = 1, wantSnowSim do' in wp, 'snow virtualization removes non-interaction visual population from CPU integration without reducing logical target')
ck('grainWant[1]' in wp and 'grainWant[2]' in wp and 'grainWant[3]' in wp and 'grainWant[4]' in wp,
   'hail/sand/debris/ash allocation partitions are live')
ck((('grain.gpuTarget[kind]=logical-grain.simTarget[kind]' in wp) or ('grain.gpuTarget[kind]=logical' in wp and 'grain.simTarget[kind]=0' in wp)) and 'kind~=3' in wp, 'hail/sand/ash virtualize visual field while leaves remain physical')
ck('drawRainStreaks(Voxel3D)' in wp, 'rain reaches draw submission')
ck('drawSnowFlakes(Voxel3D)' in wp, 'snow reaches draw submission')
ck('drawGrains(Voxel3D)' in wp, 'hail/sand/ash/leaves reach draw submission')

# Host-path regression: rain worked while all other families shared a different card path.
ck('local SNOW_FMT = RAIN_FMT' in wp, 'all 3D particle cards use rain-proven vertex layout')
ck('SnowTint' not in wp, 'no split SnowTint host path remains')
ck(wp.count('attribute vec4 RainTint;') >= 6, 'all precipitation shaders bind shared RainTint attribute')
ck('getCardFallbackShader' in wp, 'universal visible card shader fallback exists')
for name in (
    'getHailShader() or getCardFallbackShader() or getRainShader()',
    'getSandShader() or getCardFallbackShader() or getRainShader()',
    'getLeafShader() or getSandShader() or getCardFallbackShader() or getRainShader()',
    'getAshShader() or getSandShader() or getCardFallbackShader() or getRainShader()',
):
    ck(name in wp, f'specialized grain shader has compatible fallback: {name.split("(")[0]}')
ck('local snowSh = getSnowShader() or getCardFallbackShader() or getRainShader()' in wp,
   'snow has compatible shader fallback')

# 4.33.1 regression: host focus is not a trustworthy view ray on every voxel host.
cam_calls = len(re.findall(r'cameraForward\(Voxel3D', wp))
ck(cam_calls == 1, 'cameraForward is definition-only; CPU rain uses GPU frustum clipping without view-direction gating')
ck('proven distance-only' in wp, 'snow uses distance-only CPU culling')
ck('never use focus-as-forward for grains' in wp, 'grain families do not use host focus as camera direction')

# Fresh storm activation is immediately populated through the physical fall column.
ck('local primeRain = wantRain > 0 and (rain.active or 0) <= 0' in wp,
   'fresh physical rain shell detects one-shot activation edge')
ck('spawnRainAt(i, rainSpawnX, py, rainSpawnZ, rainI, windX, windZ, rain.simRadius, true)' in wp,
   'fresh physical rain shell warm-starts through cloud-to-ground column at stable world anchor')
ck('spawnRainAt(i, rainSpawnX, py, rainSpawnZ, rainI, windX, windZ, rain.simRadius, false)' in wp,
   'normal physical rain recycle restarts at cloud bank from stable world anchor')
ck('function WP.rainColumnRange()' in wp,
   'rain exposes on-demand vertical-column diagnostic without frame-path scan')
ck('spawnSnowAt(i, px, py, pz, snowI, windX, windZ, true, simRadius)' in wp,
   'fresh physical snow shell warm-starts through cloud-to-ground column')
ck('if recycle then\n      spawnSnowAt(i, px, py, pz, snowI, windX, windZ, false, simRadius)' in wp,
   'normal physical snow recycle restarts at cloud bank')
ck('spawnGrainAt(i, px, py, pz, grainKind, windX, windZ, true, grain.simRadius[grainKind])' in wp,
   'fresh physical grain shell uses activation priming and family radius')
ck('if primeColumn and (kind == 1 or kind == 4)' in wp,
   'grain warm-start is limited to cloud-origin hail/ash')
ck('spawnGrainAt(i, px, py, pz, grainKind, windX, windZ, false, grain.simRadius[grainKind])' in wp,
   'normal physical grain recycle restarts at authored spawn origin/radius')

# Catalogue and executable test coverage inventory.
for fam in fams:
    ck(re.search(rf'\b{fam}\s*=\s*[0-9]', types) is not None,
       f'catalogue contains live {fam} channel')
for label in ('rain','snow','hail','sand','debris','ash'):
    ck(re.search(rf'name="{label}"', wt) is not None,
       f'world-space executable test covers {label}')
    ck(f'3D {label}' in rt or f'exercise3D("{label}"' in rt or (label == 'debris' and 'exercise3D("leaves"' in rt),
       f'render pipeline test covers {label}')

print(f'3D pipeline integrity: {checks-fails} passed, {fails} failed')
sys.exit(1 if fails else 0)
