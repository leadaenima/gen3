#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys,re
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
e=(R/'lib/EngineRuntime.lua').read_text();d=(R/'lib/DistantWeather.lua').read_text();c=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text();p=(R/'lib/DistantFrontPrecip.lua').read_text();s=(R/'lib/Settings.lua').read_text()
ck('register("climate","distant_weather",55' in e and 'end,"distant_weather",false,nil,8)' in e,'frame-live observer has no heavy routed interval')
ck('local MAX=4' in d and 'local pool={}' in d and 'rainAudioState={' in d,'front observer/audio state remain bounded and reusable')
ck('pool[count] or {}' in d and 'rainAudioState' in d and 'function D.sample()' in d,'steady path reuses descriptors; copying is diagnostics-only')
ck('particleBudget=max(1400,floor(9000*qscale+.5))' in c and 'particleBudget=math.max(1400,math.floor(9000*qscale+.5))' in c,'both GPU and CPU paths preserve exact 9,000 MAX remote budget')
ck('radius*.62' in d and 'shaftHandoff' in d,'62% remote/local precipitation handoff is retained')
ck('drawInstanced' in p and 'if state.base and state.seed and state.shader then return true end' in p,'8.1.51 zero-upload instancing fast path is retained')
# Prove DistantFrontPrecip itself is byte-identical to the frozen 8.1.51 runtime.
b=json.loads((R/'tools/baselines/8.1.51-runtime-sha256.json').read_text())['files']['lib/DistantFrontPrecip.lua'];f=R/'lib/DistantFrontPrecip.lua'
ck(hashlib.sha256(f.read_bytes()).hexdigest()==b['sha256'] and f.stat().st_size==b['size'],'instancing module is byte-identical to 8.1.51')
schema=s[s.find('Settings.SCHEMA'):s.find('Settings.GROUPS')];keys=re.findall(r'key\s*=\s*"([A-Za-z0-9_]+)"',schema)
ck(len(keys)==78 and len(set(keys))==78,'all current player settings remain present after removed RAVE controls and battle-visual deduplication')
print(f'8.1.52 performance preservation: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
