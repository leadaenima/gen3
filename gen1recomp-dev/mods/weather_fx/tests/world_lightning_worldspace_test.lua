-- Weather FX 3D world-lightning proof.
-- Requires actual world placement, terrain impact, cloud-bank origin, 360-degree
-- near/mid/far distribution, and world-space localized lighting geometry.

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local checks, failures = 0, 0
local function check(ok, msg)
  checks = checks + 1
  if not ok then failures = failures + 1; io.write("FAIL: ", msg, "\n") end
end

math.randomseed(4338)

local current = { id="current", def={width=40,height=30} }
local east = { id="east", def={width=24,height=24} }
local south = { id="south", def={width=28,height=18} }
local function dims(map) return map.def.width*2, map.def.height*2 end
local function height(map,cx,cz)
  -- Deterministic raised terrain so a generic Y=0 plane cannot pass.
  local bias = map == current and 1 or (map == east and 4 or 7)
  return bias + ((cx*3 + cz*5) % 6)
end
local VoxelScene = { groundAt=function(map,cx,cz) return height(map,cx,cz) end }
local RenderDistance = {
  radius=function() return 720 end,
  point=function(x,z,player)
    local px=(player.px or 0)+8; local pz=(player.py or 0)+8
    local dx,dz=x-px,z-pz
    return dx*dx+dz*dz <= 720*720
  end,
}

local V = {}
function V.require(name)
  if name == "VoxelScene" then return VoxelScene end
  if name == "RenderDistance" then return RenderDistance end
  error("unexpected require " .. tostring(name), 0)
end

local drawCalls = 0
love = { graphics = {
  newMesh=function(fmt,cap)
    local m={cap=cap}
    function m:setVertices(v,start,count) self.count=count or #v end
    function m:setDrawRange(a,b) self.range=b end
    return m
  end,
  newShader=function(src) return {send=function() end} end,
  setBlendMode=function() end,
  setDepthMode=function() end,
  setShader=function() end,
  setColor=function() end,
  draw=function(mesh) drawCalls=drawCalls+1 end,
} }

local WL = assert(loadfile(ROOT .. "lib/voxel_atmos/WorldLightning.lua"))(V)
local WorldLighting = assert(loadfile(ROOT .. "lib/voxel_atmos/WorldLighting.lua"))(V)
local Voxel3D = {
  far=820, eye={320,60,250}, focus={320,0,250}, vp={},
  beginEffect=function() return true end,
  endEffect=function() end,
}
local neighbors = {
  {map=east, ox=40*2*16, oy=0},
  {map=south, ox=0, oy=30*2*16},
}
local focus={320,0,250}
local player={px=focus[1]-8,py=focus[3]-8}

local zones={near=0,mid=0,far=0}
local quadrants={0,0,0,0}
local terrainHits=0
local cloudHits=0
local mapHits=0
for i=1,240 do
  local b=WL.strike(focus,108,{deckSpan=24,map=current,neighbors=neighbors,player=player,Voxel3D=Voxel3D})
  check(b~=nil,"strike allocated")
  local s=WL.lastStrike
  if s then
    zones[s.zone]=(zones[s.zone] or 0)+1
    check(s.dist<=720.001,"strike stays inside active voxel render distance")
    local dx,dz=s.x-focus[1],s.z-focus[3]
    local q=(dx>=0 and dz>=0) and 1 or ((dx<0 and dz>=0) and 2 or ((dx<0 and dz<0) and 3 or 4))
    quadrants[q]=quadrants[q]+1
    local map = s.region=="current" and current or (s.region=="neighbor:1" and east or (s.region=="neighbor:2" and south or nil))
    if map and s.cellX and s.cellZ then
      mapHits=mapHits+1
      local expected=height(map,s.cellX,s.cellZ)+0.08
      if math.abs(s.y-expected)<0.0001 then terrainHits=terrainHits+1 end
    end
    if s.topY>=108+24*0.18-0.001 and s.topY<=108+24*0.82+0.001 then cloudHits=cloudHits+1 end
  end
end
check(mapHits==240,"all strikes land on current/rendered-neighbour map cells")
check(terrainHits==240,"every strike endpoint uses VoxelScene.groundAt terrain height")
check(cloudHits==240,"every bolt origin is inside the published 3D cloud deck band")
-- 8.1.22 raised-deck integration: a bolt given the former 108-unit deck scaled
-- by 1.50 must physically begin around 162 rather than silently keeping the old
-- short channel length.
local raised=WL.strike(focus,162,{deckSpan=24,map=current,neighbors=neighbors,player=player,Voxel3D=Voxel3D})
check(raised and WL.lastStrike.topY>=162+24*.18-.001,"lightning geometry begins in 50-percent-raised cloud deck")

check(zones.near>0 and zones.mid>0 and zones.far>0,"storm contains near, mid and far strikes")
check(quadrants[1]>0 and quadrants[2]>0 and quadrants[3]>0 and quadrants[4]>0,
  "strikes surround the player in all four world quadrants")

-- Stored world coordinates are camera-independent.
local before=WL.lastStrike
local bx,by,bz=before.x,before.y,before.z
Voxel3D.eye={-400,180,700}; Voxel3D.focus={100,0,-500}
WL.draw(Voxel3D)
check(WL.lastStrike.x==bx and WL.lastStrike.y==by and WL.lastStrike.z==bz,
  "camera movement cannot drag an existing lightning strike")
check(drawCalls>0,"world bolt submits actual 3D geometry")

-- Local weather lighting uses those same world-space strikes.
local beforeDraws=drawCalls
local ok=WorldLighting.draw(Voxel3D,WL)
local st=WorldLighting.status()
check(ok==true,"world lighting draw succeeds")
check((st.vertices or 0)>0,"world lighting emits localized 3D light-volume vertices")
check((st.draws or 0)>0 and drawCalls>beforeDraws,"world lighting reaches a draw submission")

-- Weather handoff safety: entering RAIN/HEAVY uses this cheap clear path so
-- no storm bolt/light volume can finish its old lifetime inside rain-only weather.
check(WL.active(),"transition setup has a live world lightning bolt")
WL.clear()
check(not WL.active() and #WL.sample()==0,"world lightning clear immediately removes every live 3D bolt")

io.write(string.format("world lightning: %d passed, %d failed | zones near=%d mid=%d far=%d\n",
  checks-failures, failures, zones.near or 0, zones.mid or 0, zones.far or 0))
os.exit(failures==0 and 0 or 1)
