#!/usr/bin/env python3
from pathlib import Path
import json,sys,re
R=Path(__file__).resolve().parents[1]
P=F=0
def ck(v,m):
 global P,F
 if v: P+=1; print('PASS '+m)
 else: F+=1; print('FAIL '+m)
def txt(x): return (R/x).read_text(errors='replace')
M=json.loads(txt('manifest.json')); NS=txt('lib/NightSky.lua'); T=txt('lib/Tornado.lua'); C=txt('lib/Config.lua')
ck(tuple(int(x) for x in str(M.get('version','0.0.0')).split('.')[:3]) >= (8,1,14),'manifest preserves 8.1.14+ lineage')
ck(tuple(int(x) for x in (R/'BASELINE').read_text().strip().split('.')[:3]) >= (8,1,14),'baseline preserves 8.1.14+ lineage')
ck('local SINGLE_PER_NIGHT = 4' in NS,'four shooting-star events per night')
ck('spawnOne(dx, dy, dz, 0, false, "single")' in NS,'each normal event spawns exactly one single shooting star')
ck('local SHOWER_CHANCE = 0.10' in NS,'meteor shower chance is 10 percent')
ck('METEOR.showerEligible = math.random() < SHOWER_CHANCE' in NS,'shower rolls once when night plan is created')
ck('METEOR.showerDone = true' in NS and 'if not METEOR.showerDone' in NS,'shower is capped at once per night')
ck('one-per-game-minute barrage' in NS and 'SINGLE_EVERY' not in NS,'old minute cadence removed')
ck('tryTouchCarry' in T and 'touchRadius' in T,'active tornado contact detector exists')
ck('r.stage~="roam" and not (r.stage=="forming" and r.age>=r.formation*.85)' in T,'only sufficiently formed active funnels can contact-pickup')
ck('local choices=T.destinations(mapId or r.mapId)' in T,'contact relocation uses safe visited destination set')
ck('return beginCarry(r,px,pz,"touch")' in T,'contact starts real carry/relocation pipeline')
ck('if tryTouchCarry(r,px,pz,mapId) then return end' in T and 'tryTouchCarry(r,px,pz,mapId)' in T.split('refreshTornadoMap',1)[-1],'contact checked across movement frame')
ck('local rad=9-7*u' in T,'pickup presentation spirals inward')
ck('touchRadius = 14' in C and '["tornado.touchRadius"] = { 6, 32 }' in C,'touch radius configured and validated')
print(f'8.1.14 night/tornado contract: {P} passed, {F} failed')
sys.exit(1 if F else 0)
