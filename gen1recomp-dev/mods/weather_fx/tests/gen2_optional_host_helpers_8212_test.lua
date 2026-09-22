-- Weather FX 8.2.12: optional voxel-host helpers must fail quietly.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1; print('PASS '..n) else fail=fail+1; print('FAIL '..n) end end
love={graphics={getDimensions=function() return 320,288 end}}
local protectedFailures=0
local V={}
V.safeCall=function(fn,...)
  local ok,a,b,c=pcall(fn,...)
  if not ok then protectedFailures=protectedFailures+1 end
  return ok,a,b,c
end
local Config={get=function() return {npcLightning={enabled=true,chance=1,duration=3,nearRadius=192}} end}
function V.require(name)
  if name=='Config' then return Config end
  if name=='VoxelScene' then return {groundAt=function() return 0 end} end
  if name=='SpatialIndex' then return nil end
  if name=='RenderDistance' then error('optional RenderDistance absent on Gen2Recomped-DramaticShapes',0) end
  error('missing '..tostring(name),0)
end
local player={px=16,py=16,cellX=1,cellY=1,def={sprite='SPRITE_PLAYER'}}
local npc={px=32,py=32,cellX=2,cellY=2,def={sprite='SPRITE_LASS'}}
local state={map={id='NEW_BARK_TOWN'},player=player,entities={player,npc},ghosts={}}
local Vox={
  vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},
  size=function() return 320,288 end,
  project=function(x,y,z) return 160,120,1 end,
}
local N=assert(loadfile(ROOT..'lib/voxel_atmos/NpcLightning.lua'))(V)
N.observe(state)
local count=N.candidateCount(Vox,{})
ck(count==1,'missing optional RenderDistance still admits visible NPC through fallback')
ck(protectedFailures==0,'missing optional RenderDistance does not enter Weather FX protected-failure telemetry')
-- Probe again to verify the cached-negative path stays silent and stable.
ck(N.candidateCount(Vox,{})==1,'cached missing optional RenderDistance remains stable')
ck(protectedFailures==0,'cached missing helper remains silent')
local f=assert(io.open(ROOT..'lib/voxel_atmos/NpcLightning.lua','rb')); local src=f:read('*a'); f:close()
ck(src:find('pcall(V.require, "RenderDistance")',1,true)~=nil,'NpcLightning uses quiet optional-module probe')
print(('8.2.12 optional Gen2 host helpers: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
