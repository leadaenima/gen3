-- Weather FX 8.1.41 storm-front scale/speed/interception regression.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local save={d={}};function save:set(k,v) self.d[k]=v end;function save:get(k,d) local v=self.d[k];if v==nil then return d end;return v end
local V={mod={save=save}}
local Types=assert(loadfile(ROOT..'lib/Types.lua'))(V)
local wind={peek=function() return {x=1,z=0,strength=.65} end}
local space={epoch=function() return 0 end}
function V.require(n)
  if n=='Types' then return Types elseif n=='WindEngine' then return wind elseif n=='WeatherWorldSpace' then return space end
  error(n,0)
end
local function fresh(seed)
  math.randomseed(seed)
  return assert(loadfile(ROOT..'lib/StormCells.lua'))(V)
end
local function spawnOne(seed)
  local C=fresh(seed)
  for _=1,130 do C.update(.25,'MAP_A','STORM',0,0,1) end
  return C,assert(C.cells()[1],'front')
end
-- Size distribution: all four authored scales are reachable and cross-front
-- width is larger than along-front depth for every class family.
local seen={}
local slow=true
for seed=1,48 do
  local C,c=spawnOne(814100+seed)
  seen[c.sizeClass]=true
  slow=slow and (tonumber(c.speed) or 99)<=4.10
    and (tonumber(c.speed) or 0)>=.70
    and (tonumber(c.rz) or 0)>(tonumber(c.rx) or 0)
end
ck(seen.cell and seen.regional and seen.broad and seen.synoptic,'cell/regional/broad/synoptic storm-front size classes all generate')
ck(slow,'all generated fronts use slow interceptable translation and front-like crosswind width')

-- A stationary player must actually be reached by the first generated front,
-- and contact must happen before the storm is weakening/dissipating.
local stationary=true;local worst=0
for seed=1,12 do
  local C=fresh(814200+seed);local hit,stage=nil,nil
  for step=1,2800 do
    local q=C.update(.25,'MAP_A','STORM',0,0,1)
    if (tonumber(q.precip) or 0)>.03 then hit=step*.25;stage=q.stage;break end
  end
  stationary=stationary and hit~=nil and (stage=='growth' or stage=='mature')
  if hit then worst=math.max(worst,hit) end
end
ck(stationary,'first incoming storm reaches a stationary player while still growth/mature')
ck(worst<700,'stationary leading-edge arrival remains finite even with much slower world motion')

-- A player can deliberately walk toward a front and physically enter it; the
-- system does not recede from the camera or move faster than traversal.
local intercept=true;local interceptWorst=0
for seed=1,12 do
  local C=fresh(814300+seed);local x,z=0,0;local hit=nil
  for step=1,1600 do
    local list=C.cells()
    if #list>0 then
      local c=list[1];local dx,dz=c.x-x,c.z-z;local d=math.sqrt(dx*dx+dz*dz)
      if d>.001 then x=x+dx/d*10*.25;z=z+dz/d*10*.25 end
    end
    local q=C.update(.25,'MAP_A','STORM',x,z,1)
    if (tonumber(q.precip) or 0)>.03 then hit=step*.25;break end
  end
  intercept=intercept and hit~=nil
  if hit then interceptWorst=math.max(interceptWorst,hit) end
end
ck(intercept,'player walking toward the storm can physically reach its precipitation footprint')
ck(interceptWorst<240,'deliberate interception happens substantially sooner than passive arrival')

-- Connected-map movement before arrival must not leave the storm aimed forever
-- at the player's old coordinate. Move sideways for two minutes, then stop.
local reacquire=true
for seed=1,8 do
  local C=fresh(814400+seed);local x,z=0,0;local hit=nil;local stage=nil
  for step=1,3000 do
    if step<=480 then z=z+2.5*.25 end
    local q=C.update(.25,'MAP_A','STORM',x,z,1)
    if (tonumber(q.precip) or 0)>.03 then hit=step*.25;stage=q.stage;break end
  end
  reacquire=reacquire and hit~=nil and stage=='mature'
end
ck(reacquire,'bounded interception corridor follows connected-world player movement and still reaches them as a mature storm')

print(string.format('storm front reachability 8.1.41: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
