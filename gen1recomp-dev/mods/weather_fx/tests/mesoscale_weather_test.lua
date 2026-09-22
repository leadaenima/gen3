local passed,failed=0,0
local function check(v,n) if v then passed=passed+1 else failed=failed+1; print('FAIL '..n) end end
local cache={}
local V={}
cache.WindEngine={peek=function() return {x=.92,z=.38,strength=.62} end}
local mesoCfg={enabled=true,strength=1.0}
cache.Config={get=function() return {mesoscale=mesoCfg} end}
function V.require(name)
  if cache[name] then return cache[name] end
  local f=assert(loadfile('lib/'..name..'.lua')); local m=f(V); cache[name]=m; return m
end

local MF=V.require('MesoscaleField')
local weak={pressure=1007,temperature=12,humidity=.76,cloud=.62,storm=.12,wind=.55,precip=.48,visibility=.9,aerosol=.06}
MF.update(1,weak,weak,0,0)
local lo,hi=2,-1
for z=-2600,2600,260 do for x=-2600,2600,260 do
  local s=MF.sampleAt(x,z); lo=math.min(lo,s.precipScale); hi=math.max(hi,s.precipScale)
end end
check(hi-lo>.25,'weak precipitation contains broad wet/dry mesoscale bands')
check(lo<.55 and hi>.75,'passing shower field exposes meaningful local contrast')
local stats=MF.stats()
check(stats.memory=='O(1)' and stats.cellSize==520,'mesoscale field is bounded constant-memory procedural state')

mesoCfg.enabled=false
MF.update(1,weak,weak,0,0)
local offLo,offHi=2,-1
for z=-1600,1600,320 do for x=-1600,1600,320 do local q=MF.sampleAt(x,z); offLo=math.min(offLo,q.precip or 0); offHi=math.max(offHi,q.precip or 0) end end
check(offHi-offLo<.0001 and math.abs(offLo-weak.precip)<.0001,'LOCAL WEATHER FIELDS OFF returns uniform regional precipitation')
mesoCfg.enabled=true; mesoCfg.strength=.60
MF.update(1,weak,weak,0,0)
local subLo,subHi=2,-1
for z=-1600,1600,320 do for x=-1600,1600,320 do local q=MF.sampleAt(x,z); subLo=math.min(subLo,q.precip or 0); subHi=math.max(subHi,q.precip or 0) end end
mesoCfg.strength=1.35
MF.update(1,weak,weak,0,0)
local strongLo,strongHi=2,-1
for z=-1600,1600,320 do for x=-1600,1600,320 do local q=MF.sampleAt(x,z); strongLo=math.min(strongLo,q.precip or 0); strongHi=math.max(strongHi,q.precip or 0) end end
check((strongHi-strongLo)>(subHi-subLo),'LOCAL VARIATION changes spatial contrast without changing particle count')
mesoCfg.strength=1.0

local before=MF.sampleAt(320,-180).band
for i=1,90 do MF.update(1,weak,weak,0,0) end
local after=MF.sampleAt(320,-180).band
check(math.abs(after-before)>.001,'mesoscale structures advect through fixed world positions')


local forecastNow=MF.forecastAt(640,120,0)
local forecastLater=MF.forecastAt(640,120,420)
check(math.abs((forecastLater.band or 0)-(forecastNow.band or 0))>.001,'short forecast projects mesoscale band advection')

local foggy={pressure=1015,temperature=7,humidity=.96,cloud=.55,storm=0,wind=.18,precip=0,visibility=.34,aerosol=.12}
MF.update(1,foggy,foggy,0,0)
local fLo,fHi=2,-1
for z=-1800,1800,300 do for x=-1800,1800,300 do local q=MF.sampleAt(x,z); fLo=math.min(fLo,q.fogScale or 1); fHi=math.max(fHi,q.fogScale or 1) end end
check(fHi-fLo>.12,'fog weather contains spatial pools and thinning gaps without a second fog grid')
check((MF.sampleAt(0,0).precip or 0)==0,'fog field does not invent precipitation')

local severe={pressure=992,temperature=16,humidity=.94,cloud=1,storm=1,wind=1,precip=1,visibility=.55,aerosol=.08}
MF.update(1,severe,severe,0,0)
lo,hi=2,-1
for z=-1800,1800,300 do for x=-1800,1800,300 do
  local s=MF.sampleAt(x,z); lo=math.min(lo,s.precipScale); hi=math.max(hi,s.precipScale)
end end
check(lo>=.80,'mature severe storm stays broadly continuous instead of growing arbitrary dry holes')

-- Downstream cloud and volumetric fields consume the same spatial state.
MF.update(1,weak,weak,0,0)
local CF=V.require('CloudField')
for i=1,18 do CF.update(.25,weak,0,0) end
local cLo,cHi=2,-1
for z=-768,768,256 do for x=-768,768,256 do
  local c=CF.sampleAt(x,z); cLo=math.min(cLo,c.density or 0); cHi=math.max(cHi,c.density or 0)
end end
check(CF.stats().cells==49 and cHi-cLo>.02,'bounded cloud lattice inherits mesoscale cloud openings')

local VW=V.require('VolumetricWeather')
VW.update(.2,0,0,weak,CF.peek(),weak)
local pLo,pHi=2,-1
for _,q in ipairs(VW.cells()) do pLo=math.min(pLo,q.precip or 0); pHi=math.max(pHi,q.precip or 0) end
check(VW.stats().cells==75 and pHi-pLo>.02,'3D weather volume contains spatially distinct precipitation bands')

print(('mesoscale weather: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
