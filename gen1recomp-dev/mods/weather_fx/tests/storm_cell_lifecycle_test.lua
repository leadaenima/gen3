local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1 else fail=fail+1;print('FAIL '..n) end end
local save={d={}};function save:set(k,v) self.d[k]=v end;function save:get(k,d) local v=self.d[k];if v==nil then return d end;return v end
local mod={save=save}
local V={mod=mod}
local Types=assert(loadfile(ROOT..'lib/Types.lua'))(V)
local wind={peek=function() return {x=1,z=0,strength=.7} end}
local space={epoch=function() return 0 end}
function V.require(n) if n=='Types' then return Types elseif n=='WindEngine' then return wind elseif n=='WeatherWorldSpace' then return space end error(n,0) end
math.randomseed(8122)
local C=assert(loadfile(ROOT..'lib/StormCells.lua'))(V)
for _=1,120 do C.update(.25,'MAP_A','STORM',0,0,1) end
local list=C.cells();ck(#list>=1,'storm synoptic source spawns finite physical cell')
local c=list[1];ck(c.rx>=280 and c.rx<=1810 and c.rz>=420 and c.rz<=4400,'cell size can represent local through synoptic multi-map systems')
ck(c.sizeClass~=nil and c.speed<=4.10,'spawned storm publishes a size class and uses the slower front-speed envelope')
-- mature cell at known coordinates
c.x,c.z,c.vx,c.vz=0,0,1,0;c.age=c.life*.50
local core=C.sampleAt(0,0,'STORM');local mid=C.sampleAt(c.rx*.68,0,'STORM');local edge=C.sampleAt(c.rx*.94,0,'STORM');local dry=C.sampleAt(c.rx*1.12,0,'STORM')
ck(core.stage=='mature' and core.precip>.95,'mature storm has full-strength center core')
ck(mid.precip<core.precip and mid.precip>edge.precip,'intensity decreases continuously away from center')
ck(edge.precip>0 and dry.precip==0,'pronounced localized precipitation edge reaches dry air')
local pre=C.sampleAt(c.rx*1.28,0,'STORM');ck(pre.cloud>0 and pre.precip==0 and pre.cloudWeather=='STORM','cloud precursor extends beyond rain edge')
-- lifecycle phases
for _,row in ipairs({{.05,'formation'},{.20,'growth'},{.50,'mature'},{.80,'weakening'},{.95,'dissipation'}}) do c.age=c.life*row[1];local q=C.sampleAt(0,0,'STORM');ck(q.stage==row[2],'lifecycle '..row[2]) end
-- world motion independent of player
c.age=c.life*.5;c.x=0;local before=c.x;C.update(.25,'MAP_A','STORM',5000,5000,1);ck(c.x>before,'storm cell moves through world with wind rather than following player')
-- duration setting rescales remaining life only
local age,life=c.age,c.life;C.rescaleRemaining(1,.25);ck(math.abs((c.life-c.age)-(life-age)*.25)<1e-6,'weather duration rescales remaining cell lifetime')
C.persist();C.reset();C.restore();ck(#C.cells()>=1,'storm cell lifecycle persists across save/load')
print(string.format('storm cell lifecycle: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
