-- Weather FX 8.1.52: storm fronts are independent world entities.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function near(a,b,e) return math.abs((a or 0)-(b or 0)) <= (e or 1e-6) end

-- Camera rotation must never become the weather/player world position.
local scene={now={playerPosKnown=true,playerWorldX=123.5,playerWorldY=-77.25}}
local voxel={focus={900,0,800},player={123.5,0,-77.25}}
local host={require=function(n) if n=='Voxel3D' then return voxel end end}
local interop={hostLib=function() return host end}
local VH={require=function(n)
  if n=='Scene' then return scene elseif n=='Interop' then return interop end
  error(n,0)
end}
local H=assert(loadfile(ROOT..'lib/HostAdapter.lua'))(VH)
local x1,z1=H.worldPosition()
voxel.focus={-5000,0,4200}
local x2,z2=H.worldPosition()
ck(near(x1,123.5) and near(z1,-77.25) and near(x2,x1) and near(z2,z1),'camera focus rotation cannot move authoritative weather position')

-- Spawn a real StormCell, then move the player arbitrarily. The entity's target,
-- heading and speed must remain the spawn-owned values and translation must stay
-- exactly linear along that locked heading.
local save={d={}};function save:set(k,v) self.d[k]=v end;function save:get(k,d) local v=self.d[k];if v==nil then return d end;return v end
local V={mod={save=save}}
local Types=assert(loadfile(ROOT..'lib/Types.lua'))(V)
local wind={peek=function() return {x=1,z=.17,strength=.62} end}
local epoch=0
local space={epoch=function() return epoch end}
function V.require(n)
  if n=='Types' then return Types elseif n=='WindEngine' then return wind elseif n=='WeatherWorldSpace' then return space end
  error(n,0)
end
math.randomseed(8152001)
local C=assert(loadfile(ROOT..'lib/StormCells.lua'))(V)
for _=1,130 do C.update(.25,'MAP_A','STORM',0,0,1) end
local c=assert(C.cells()[1],'front did not spawn')
local tx,tz,vx,vz,speed=c.targetX,c.targetZ,c.vx,c.vz,c.speed
local sx,sz=c.x,c.z
local steps,dt=80,.25
for i=1,steps do
  -- Deliberately flee sideways and backwards; a homing implementation changes
  -- target/heading under this input.
  C.update(dt,'MAP_A','STORM',1500+i*9,-2200+i*13,1)
end
c=assert(C.cells()[1],'front expired unexpectedly')
ck(c.trajectoryLocked==true,'front explicitly owns a locked trajectory')
ck(near(c.targetX,tx) and near(c.targetZ,tz),'player position is sampled once and never retargeted')
ck(near(c.vx,vx,1e-10) and near(c.vz,vz,1e-10),'later player movement cannot steer front heading')
ck(near(c.speed,speed,1e-10),'front translation speed is entity state, not live player/wind pursuit speed')
ck(near(c.x,sx+vx*speed*steps*dt,1e-7) and near(c.z,sz+vz*speed*steps*dt,1e-7),'front translates smoothly on one constant world-space vector')
local sameId=c.id
epoch=epoch+1
C.update(.25,'MAP_B','STORM',3200,-4100,1)
c=assert(C.cells()[1],'front vanished on map-space epoch change')
ck(c.id==sameId and c.trajectoryLocked==true,'map transition changes observer epoch without deleting persistent storm entity')

-- Persist/reload must preserve the same entity heading rather than rebuilding a
-- route toward the current player.
C.persist()
local saved=save.d['stormCellsV1']
ck(type(saved)=='string' and #saved>0,'front persistence record written')
local C2=assert(loadfile(ROOT..'lib/StormCells.lua'))(V)
C2.restore()
local r=C2.cells()[1]
ck(r and r.trajectoryLocked==true and near(r.vx,c.vx,1e-10) and near(r.vz,c.vz,1e-10),'persisted front reloads with locked heading intact')

print(string.format('front entity realism 8.1.52: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
