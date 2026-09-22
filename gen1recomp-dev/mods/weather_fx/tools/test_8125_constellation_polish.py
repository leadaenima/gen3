#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys,tempfile,json
R=Path(__file__).resolve().parents[1]
con=(R/'lib/Constellations.lua').read_text()
ns=(R/'lib/NightSky.lua').read_text()
man=json.loads((R/'manifest.json').read_text())
version=tuple(map(int,man.get('version','0.0.0').split('.')))
checks=[]
def ck(v,msg):
    checks.append((bool(v),msg)); print(('PASS ' if v else 'FAIL ')+msg)
ck(version >= (8,1,25),'manifest is 8.1.25 or newer')
ck('constGain=1' in con and 'C.BRIGHTNESS_GAINS={}' in con,'constellation brightness authority is present')
ck('return starScaleNow()' in ns,'constellation building dimming uses the same starScale as ordinary stars')
ck('spreadAnchors' in con and 'local SPREAD_ANCHORS = spreadAnchors(ANCHORS)' in con,'anchor spreading pass is present')
if version >= (8,1,43):
    lua=r"""
local C=assert(loadfile('lib/Constellations.lua'))({})
local function clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function ang(a,b)
  local sa,ca=math.sin(a.az),math.cos(a.az); local se,ce=math.sin(a.el),math.cos(a.el)
  local sb,cb=math.sin(b.az),math.cos(b.az); local sf,cf=math.sin(b.el),math.cos(b.el)
  local dot=(sa*ce)*(sb*cf)+se*sf+(ca*ce)*(cb*cf)
  dot=clamp(dot,-1,1)
  return math.deg(math.acos(dot))
end
local minClear=1e9
for i=1,#C.NAMES-1 do
  local ai=C.ANCHORS[C.NAMES[i]]
  for j=i+1,#C.NAMES do
    local aj=C.ANCHORS[C.NAMES[j]]
    local c=ang(ai,aj)-math.deg((ai.scale or 0)+(aj.scale or 0))
    if c<minClear then minClear=c end
  end
end
assert(minClear>=16.5, 'minimum anchor clearance '..tostring(minClear)..' < 16.5 deg')
for _,n in ipairs(C.NAMES) do
  assert(C.BRIGHTNESS_GAINS[n]==1,'8.1.43 gain must be exact 1.0 for '..n)
end
assert(math.abs((C.PEAK_LUMA_TARGET or 0)-.82)<1e-12,'8.1.43 common peak-luma target missing')
print(string.format('constellation polish runtime: minClear=%.3f equalGain=1.000 count=%d',minClear,C.count()))
"""
else:
    lua=r"""
local C=assert(loadfile('lib/Constellations.lua'))({})
local function clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function ang(a,b)
  local sa,ca=math.sin(a.az),math.cos(a.az); local se,ce=math.sin(a.el),math.cos(a.el)
  local sb,cb=math.sin(b.az),math.cos(b.az); local sf,cf=math.sin(b.el),math.cos(b.el)
  local dot=(sa*ce)*(sb*cf)+se*sf+(ca*ce)*(cb*cf)
  dot=clamp(dot,-1,1)
  return math.deg(math.acos(dot))
end
local minClear=1e9
for i=1,#C.NAMES-1 do
  local ai=C.ANCHORS[C.NAMES[i]]
  for j=i+1,#C.NAMES do
    local aj=C.ANCHORS[C.NAMES[j]]
    local c=ang(ai,aj)-math.deg((ai.scale or 0)+(aj.scale or 0))
    if c<minClear then minClear=c end
  end
end
assert(minClear>=16.5, 'minimum anchor clearance '..tostring(minClear)..' < 16.5 deg')
local minGain,maxGain=1e9,0
for _,n in ipairs(C.NAMES) do
  local g=C.BRIGHTNESS_GAINS[n]
  assert(type(g)=='number' and g>=0.70 and g<=1.35, 'gain out of bounds for '..n)
  if g<minGain then minGain=g end
  if g>maxGain then maxGain=g end
end
assert((maxGain-minGain)>=0.3, 'gains should materially rebalance dense vs sparse traces')
print(string.format('constellation polish runtime: minClear=%.3f minGain=%.3f maxGain=%.3f count=%d',minClear,minGain,maxGain,C.count()))
"""
with tempfile.NamedTemporaryFile('w',suffix='.lua',delete=False) as f:
    f.write(lua); path=f.name
r=subprocess.run(['texlua',path],cwd=R,text=True,capture_output=True)
ck(r.returncode==0 and 'constellation polish runtime:' in r.stdout,'runtime proves anchor spacing and version-correct brightness contract')
failed=sum(not v for v,_ in checks)
print(f'8.1.25 constellation polish: {len(checks)-failed}/{len(checks)} passed, {failed} failed')
if failed:
    if r.stdout: print(r.stdout)
    if r.stderr: print(r.stderr)
sys.exit(1 if failed else 0)
