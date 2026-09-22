local passed,failed=0,0
local function ck(v,m) if v then passed=passed+1 else failed=failed+1;print('FAIL '..m) end end
local TOD={hour=12,dayIndex=1}
local V={require=function(n)
  if n=='TimeOfDay' then return TOD end
  if n=='Settings' then return {get=function() return 'north' end} end
  if n=='Config' then return {get=function() return {} end} end
  error(n)
end}
local Sim=assert(loadfile('lib/CelestialSim.lua'))(V)
local dawn=Sim.sample(7);local dusk=Sim.sample(17);local noon=Sim.sample(12)
ck(math.abs(dawn.sun.altitudeDeg)<4 and math.abs(dusk.sun.altitudeDeg)<4,'sampled dawn/dusk are low-sun states')
local function warmSky(s)
  local top,h=s.sky.top,s.sky.haze
  return (h[1]-h[3]),(top[3]-top[1]),h[1]
end
local dr,db,dh=warmSky(dawn);local sr,sb,sh=warmSky(dusk)
ck(dr>.55 and sr>.55,'dawn/dusk horizon is strongly warm rather than a slight tint')
ck(db>.12 and sb>.12,'dawn/dusk zenith remains cooler/bluer than the horizon')
ck(dh>.75 and sh>.75,'low-sun horizon reaches strong visible orange/red luminance')
ck(noon.sky.top[3]>noon.sky.top[1] and noon.sky.haze[3]>noon.sky.haze[1],'midday returns to blue sky authority')

local A=assert(loadfile('lib/AtmosphereModel.lua'))({})
A.update(0,{cloud=0,aerosol=.04,visibility=1},{sun={altitudeDeg=0}}, {density=0,transmission=1})
local bands=A.applyBands({{.20,.40,.80},{.30,.50,.80},{.40,.60,.80}})
ck(bands[3][1]>bands[1][1]+.20,'physical atmosphere warms the horizon more than the zenith')
ck(bands[3][3]<bands[1][3],'physical atmosphere reduces horizon blue relative to zenith')
local desc=A.describe();ck(desc:find('warm=1.00',1,true)~=nil,'golden-hour atmospheric warmth peaks around horizon contact')
A.update(0,{cloud=0,aerosol=.04,visibility=1},{sun={altitudeDeg=45}}, {density=0,transmission=1})
ck(A.describe():find('warm=0.00',1,true)~=nil,'golden-hour warmth clears at high sun')
print(('8.1.26 sunrise sky: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
