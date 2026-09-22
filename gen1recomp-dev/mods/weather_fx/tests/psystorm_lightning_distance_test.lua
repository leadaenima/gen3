-- Weather FX 4.35.19 Psychic Storm lightning placement regression.
-- Ordinary PSYSTORM terrain bolts should overwhelmingly live in the mid/far
-- field, with a hard near-player exclusion floor. Multi-bolt bursts are spread
-- across distance bands instead of clustering beside the player. Explicit NPC
-- redirects remain exempt and are tested independently by npc_lightning_test.

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local checks, failures = 0, 0
local function check(ok,msg)
  checks=checks+1
  if not ok then failures=failures+1; io.write("FAIL: ",msg,"\n") end
end

math.randomseed(43519)
local V={}
function V.require(name) error("optional module unavailable: "..tostring(name),0) end
local WL=assert(loadfile(ROOT.."lib/voxel_atmos/WorldLightning.lua"))(V)
local focus={0,0,0}
local vox={far=900}

local zones={near=0,mid=0,far=0}
local minDist=1e9
for i=1,2000 do
  local b=WL.strike(focus,120,{Voxel3D=vox,weatherId="PSYSTORM"})
  check(b~=nil,"Psychic Storm single bolt allocates")
  if b then
    zones[b.zone]=(zones[b.zone] or 0)+1
    if b.dist < minDist then minDist=b.dist end
  end
end
local total=zones.near+zones.mid+zones.far
local nearFrac=zones.near/math.max(1,total)
local midFrac=zones.mid/math.max(1,total)
local farFrac=zones.far/math.max(1,total)
check(minDist >= 159.999,"ordinary Psychic Storm terrain bolt respects 160-unit near-player exclusion")
check(nearFrac < 0.08,"Psychic Storm ordinary near-field rate stays below 8%")
check(midFrac > 0.22 and midFrac < 0.44,"Psychic Storm mid-field rate remains substantial")
check(farFrac > 0.55,"most ordinary Psychic Storm bolts land in the far field")

WL.clear()
for n=2,4 do
  for rep=1,120 do
    local burst=WL.strikeBurst(focus,120,{Voxel3D=vox,weatherId="PSYSTORM"},n)
    check(#burst==n,"Psychic Storm burst allocates requested bolt count")
    for i,b in ipairs(burst) do
      check(b.dist >= 159.999,"Psychic Storm burst terrain bolt stays outside near-player exclusion")
      if i==1 or i>=3 then
        check(b.zone=="far","Psychic Storm burst outer members are forced far")
      elseif i==2 then
        check(b.zone=="mid","Psychic Storm second burst member is forced mid")
      end
    end
  end
end

-- Ordinary storm placement keeps its existing close-strike character and is
-- not accidentally converted to the Psychic Storm profile.
WL.clear()
local ordinaryNear=0
for i=1,400 do
  local b=WL.strike(focus,120,{Voxel3D=vox,weatherId="STORM"})
  if b and b.dist < 160 then ordinaryNear=ordinaryNear+1 end
end
check(ordinaryNear>0,"ordinary lightning weather still permits genuinely close terrain strikes")

io.write(string.format("psystorm lightning distance: %d passed, %d failed | near=%.3f mid=%.3f far=%.3f min=%.1f\n",
  checks-failures,failures,nearFrac,midFrac,farFrac,minDist))
os.exit(failures==0 and 0 or 1)
