#!/usr/bin/env python3
"""Weather FX 8.0.3 live regression contracts reported from in-game testing."""
from pathlib import Path
import json,sys,re
R=Path(__file__).resolve().parents[1]
def text(rel): return (R/rel).read_text(encoding='utf-8',errors='replace')
checks=[]
def ck(v,n): checks.append((bool(v),n)); print(('PASS ' if v else 'FAIL ')+n)
audio=text('lib/Audio.lua'); ns=text('lib/NightSky.lua'); cs=text('lib/CelestialStarField.lua'); ca=text('lib/voxel_atmos/CinematicAtmos.lua'); wp=text('lib/voxel_atmos/WorldPrecip.lua'); ps=text('lib/ProceduralSnowField.lua'); npc=text('lib/voxel_atmos/NpcLightning.lua'); cfg=text('lib/Config.lua'); man=json.loads(text('manifest.json'))
# Home/title audio must be a non-owner.
ck('local worldAudio = inOverworldAudio()' in audio and 'if not worldAudio then' in audio,'audio explicitly gates title/home screen before weather work')
ck('if Audio._worldAudioWasActive then\n      Audio.stopAllBeds()' in audio,'world->title cleanup occurs only after Weather FX owned a world')
ck('Audio._worldAudioWasActive = false' in audio and 'Audio._frameAudioCfg = nil' in audio,'title branch drops Weather FX audio state without claiming engine audio')
ck(audio.count('Audio.stopAllBeds()')>=1 and 'A cold boot on the title screen' in audio,'cold title boot non-interference is documented in runtime path')
# Projected sky uses stable zenith projection plus far scene depth on both GPU and CPU paths.
ck('clip.z = clip.w;' in ns and 'setDepthMode,"lequal",false' in ns,'CPU projected celestial mesh writes far read-only depth')
ck('clip.z=clip.w;' in cs and "setDepthMode,'lequal',false" in cs,'instanced projected stars write far read-only depth')
ck('drawScreenMesh("_projectedMesh",verts,n,"add",true)' in ns and 'drawScreenMesh("_projectedPlanetMesh",pverts,pn,"alpha",true)' in ns,'stars/constellations and planets use depth-aware projected submission')
ck('_drawProjectedBody("_projectedSunMesh",sunVerts,sn' in ns and '_drawProjectedBody("_projectedMoonMesh",moonVerts,mn' in ns and 'clip.z = clip.w;' in ns,'analytic sun/moon retain far-depth world occlusion contract')
ck('lod.starStep,lod.maxPlanets,lod.twinkle,lod.meteors=1,#PLANETS,true,true' in ns,'all quality tiers retain complete star/planet catalogue')
ck('math.max(.72,(s.size or 1)*.52)' in ns and 'math.max(.72,(cs.size or .86)*.48)' in ns,'CPU projected stars/constellations keep quality-independent visible footprint')
ck('float halfSize=max(.72,StarData.x*.52);' in cs,'GPU projected stars keep quality-independent visible footprint')
# Heavy/storm overlay repair.
ck('function CinematicAtmos._mistPolicy' in ca and 'if f<=0.02 then return 0,false end' in ca,'ground mist is identified generically from authored fog authority')
ck('weather.fog,weather._mistVisual=CinematicAtmos._mistPolicy(authoredFog,fogScale)' in ca,'weather without authored fog cannot inherit mist or cinematic fog extinction')
ck(ca.count('frame.weather._mistVisual == false')>=2,'both mist and rolling-fog presentation honor rain-only suppression')
ck('closeLen = max(0.20, min(1.0, tl / 14.0))' in wp and 'closeWidth = max(0.35, min(1.0, tl / 9.0))' in wp,'near rain streak geometry is perspective bounded without count reduction')
# World-spanning snow and fail-safe GPU virtualization.
ck('local SNOW_FAR_FRACTION = 1.15' in wp,'snow field overlaps rendered far plane')
ck('SNOW_STREAM_RADIUS = min(SNOW_RADIUS_MAX, max(SNOW_RADIUS_MIN, desiredSnowR))' in wp and 'SNOW_DRAW_RADIUS = SNOW_STREAM_RADIUS' in wp,'snow coverage radius is independent from quality radius cap')
ck('PS.canVirtualize' in wp and 'PS.probe' in wp,'snow only splits after real GPU backend proof')
ck('function P.canVirtualize() return ensure() and state.proven==true end' in ps,'procedural snow exposes driver-proven virtualization gate')
ck('function P.probe(Voxel3D,opts)' in ps and 'opts.alpha=0' in ps,'snow backend is proven with invisible real draw')
ver_now=tuple(int(x) for x in str(man.get('version','0.0.0')).split('.')[:3])
if ver_now >= (8,1,55):
    ck('local ANCHOR_CELL=256' in ps and 'state.anchorNextX' in ps and 'submitFixed' in ps and 'state.anchorFromX' not in ps,'procedural snow streams between fixed world anchors without dragging field toward player')
else:
    ck('local targetX=math.floor(((tonumber(focus[1]) or 0)/CELL)+0.5)*CELL' in ps and 'local CELL=64' in ps and 'state.anchorFromX' in ps and 'u=u*u*(3-2*u)' in ps,'procedural snow uses stable world-cell anchor with seamless cell handoff')
# NPC reaction contract.
ck('chance = 0.10' in cfg and 'duration = 3.0' in cfg,'NPC lightning config is 10 percent / 3 seconds')
ck('CHANCE = 0.10' in npc and 'DURATION = 3.0' in npc,'NPC lightning runtime fallback is 10 percent / 3 seconds')
ck('local function reactionMetrics(d)' in npc and 'wxEyeAnchor' in npc and 'wxHeadY' in npc,'NPC face/head anchors are sprite-card relative with exact metadata override')
ck('rm.mode=="front"' in npc and 'rm.mode=="side"' in npc and 'rm.mode=="back"' not in npc[npc.find('local function drawEyes'):npc.find('local function pushSmokeQuad')],'eye overlay follows facing and does not paint eyes on back frames')
ck('local function drawSmoke(Voxel3D,list)' in npc and (('rm.headY+.45+localAge*3.4' in npc) or ('rm.headY+1.05+localAge*4.6' in npc and 'local rm=reactionMetrics(d)' in npc)),'visible smoke plume originates from resolved Pokémon head anchor')
ver=tuple(int(x) for x in str(man.get('version','0.0.0')).split('.')[:3]); ck(ver >= (8,0,3),'manifest preserves 8.0.3+ regression lineage')
failed=sum(not ok for ok,_ in checks)
print(f'8.0.3 live regression static gate: {len(checks)-failed}/{len(checks)} passed, {failed} failed')
sys.exit(1 if failed else 0)
