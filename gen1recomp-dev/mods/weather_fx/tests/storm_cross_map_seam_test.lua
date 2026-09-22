local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1 else fail=fail+1;print('FAIL '..n) end end
local save={d={}};function save:set(k,v) self.d[k]=v end;function save:get(k,d) local v=self.d[k];if v==nil then return d end;return v end
local V={mod={save=save}}
local Types=assert(loadfile(ROOT..'lib/Types.lua'))(V)
local wind={peek=function() return {x=1,z=0,strength=.65} end}
local WS
function V.require(n)
  if n=='Types' then return Types elseif n=='WindEngine' then return wind elseif n=='WeatherWorldSpace' then return WS end
  error(n,0)
end
WS=assert(loadfile(ROOT..'lib/WeatherWorldSpace.lua'))(V)
WS.observeVoxelState({map={id='MAP_A'},neighbors={{map={id='MAP_B'},ox=512,oy=0}}})
math.randomseed(8122)
local C=assert(loadfile(ROOT..'lib/StormCells.lua'))(V)
for _=1,120 do C.update(.25,'MAP_A','STORM',0,0,1) end
local c=assert(C.cells()[1],'cell')
-- Force one mature storm centered directly across the A/B seam. A local x=500
-- and B local x=4 are only 16 world units apart and must sample the SAME cell.
c.x,c.z,c.vx,c.vz=512,128,1,0;c.rx,c.rz=360,280;c.age=c.life*.5
local ax,az=WS.toWorld(500,128,'MAP_A')
local bx,bz=WS.toWorld(4,128,'MAP_B')
ck(ax==500 and bx==516,'connected maps resolve into one canonical weather-world frame')
local a=C.sampleAt(ax,az,'STORM');local b=C.sampleAt(bx,bz,'STORM')
ck(a.cellId==c.id and b.cellId==c.id,'same physical storm simultaneously occupies both maps')
ck(a.precip>.9 and b.precip>.9,'storm core can rain on portions of both maps at once')
local dryAx,dryAz=WS.toWorld(80,128,'MAP_A')
local dry=C.sampleAt(dryAx,dryAz,'STORM')
ck(dry.precip==0,'same map can remain dry outside finite storm footprint')
local fringeX,fringeZ=WS.toWorld(260,128,'MAP_A')
local fringe=C.sampleAt(fringeX,fringeZ,'STORM')
ck(fringe.precip>0 and fringe.precip<a.precip,'localized edge is weaker than storm center')
-- Rebase rendering to B. Local coordinates change, canonical storm does not.
WS.observeVoxelState({map={id='MAP_B'},neighbors={{map={id='MAP_A'},ox=-512,oy=0}}})
local rebx,rebz=WS.toWorld(4,128,'MAP_B')
local reb=C.sampleAt(rebx,rebz,'STORM')
ck(rebx==bx and reb.cellId==c.id and math.abs(reb.precip-b.precip)<1e-9,'map-root transition does not move/reseed storm')
-- A door/warp into an unproved map space changes only the observer. The storm
-- continues aging/moving in its original world and is still there on return.
local idBefore,ageBefore,xBefore=c.id,c.age,c.x
WS.observeVoxelState({map={id='HOUSE'},neighbors={}})
local hx,hz=WS.toWorld(0,0,'HOUSE')
C.update(.25,'HOUSE','CLEAR',hx,hz,1)
ck(#C.cells()>=1 and C.cells()[1].id==idBefore,'disconnected map transition does not delete live storm entity')
ck(C.cells()[1].age>ageBefore and C.cells()[1].x>xBefore,'storm keeps moving while player is on another map')
WS.observeVoxelState({map={id='MAP_A'},neighbors={{map={id='MAP_B'},ox=512,oy=0}}})
local returnX,returnZ=WS.toWorld(500,128,'MAP_A')
local returned=C.sampleAt(returnX,returnZ,'STORM')
ck(returned.cellId==idBefore,'returning to overworld resumes same storm rather than respawning it')
-- Walking through the same stationary footprint: dry -> fringe -> core -> dry -> core.
local samples={80,260,500,80,500};local seq={}
for i,x in ipairs(samples) do local wx,wz=WS.toWorld(x,128,'MAP_A');seq[i]=C.sampleAt(wx,wz,'STORM').precip end
ck(seq[1]==0 and seq[2]>0 and seq[3]>.9 and seq[4]==0 and seq[5]>.9,'player can walk into, out of, and back into same storm')
print(string.format('storm cross-map seam: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
