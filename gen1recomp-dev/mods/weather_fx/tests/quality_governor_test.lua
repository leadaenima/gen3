local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end
local selected='auto'
local cfg={quality='auto',maxParticles=10000}
local Settings={get=function(k) if k=='quality' then return selected end end}
local Config={get=function() return cfg end}
local V={require=function(name) return ({Settings=Settings,Config=Config})[name] end}
local Q=assert(loadfile('lib/Quality.lua'))(V)

Q.reset()
check(Q.tier()=='high','AUTO starts at high')
for _=1,260 do Q.update(0.04) end
check(Q.tier()~='high','sustained slow frames demote AUTO quality')
local lowTier=Q.tier()
Q.update(1.0)
check(Q.tier()==lowTier,'one-second load hitch is ignored by governor')
for _=1,1500 do Q.update(0.010) end
check(Q.tier()=='high','sustained headroom promotes AUTO back to high')

cfg.quality='medium'
check(Q.tier()=='medium','config quality applies while menu remains AUTO')
selected='potato'
check(Q.tier()=='potato','explicit UI quality overrides a fixed config-file tier')
selected='auto'
check(Q.describe()=='MEDIUM','fixed config tier is not mislabeled as adaptive AUTO')
local held=Q.budget(1)
local heldRain=held.rain
local b=Q.budget(0.5)
check(held~=b and held.rain==heldRain,'budget calls return independent tables and do not mutate held budgets')
check(b.rain==190 and b.snow==820,'quality density scales particle caps')
cfg.maxParticles=100
b=Q.budget(3)
check(b.rain==100 and b.snow==100 and b.grain==100,'maxParticles hard-caps scaled budgets')
local c=Q.celestial()
check(c.starStep==1 and c.maxPlanets==9 and c.twinkle and c.meteors and c.sunLayers==3,'celestial identity remains complete while only sun-layer cost follows quality')

cfg.maxParticles=nil
cfg.quality='auto'; selected='potato'
check(Q.tier()=='potato','mod-manager quality row controls tier when config is auto')
local pb=Q.budget(1)
check(pb.worldPrecip==0.28,'potato world-precip budget is live')
check(pb.worldSnowCap==1600 and pb.worldRainCap==550 and pb.worldRadiusCap==180,
  'potato imposes hard 3D snow/rain/radius ceilings')
check(pb.snowPackDrawCap==600 and pb.footDrawCap==40,
  'potato bounds accumulated snow and footprint rendering')

selected='auto'; cfg.quality='max'; cfg.maxParticles=10000
local mb=Q.budget(1)
check(Q.tier()=='max' and mb.worldSnowCap==10000,
  'MAX is accepted and maxParticles still hard-caps live 3D ceilings')
cfg.maxParticles=nil
mb=Q.budget(1)
check(mb.worldSnowCap==100000 and mb.worldRainCap==12000 and mb.worldRadiusCap==750,
  'MAX unlocks full authored 3D weather ceilings')

cfg.quality='auto'; selected='auto'; Q.reset()
for _=1,1500 do Q.update(0.010) end
check(Q.tier()=='high','AUTO never promotes into manual-only MAX')

print(('quality governor: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
