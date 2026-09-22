-- Weather FX 8.1.93: current Battle Art NPC-lightning actor bridge.
-- Battle Art keeps `posed` local to VoxelScene.render() and exposes that exact
-- list through CharacterRenderers.afterActors. Weather FX must consume the
-- public bridge before world lightning chooses a target; no second pose() call.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end

love={graphics={getDimensions=function()return 320,288 end}}
local Config={get=function()return{npcLightning={enabled=true,chance=.10,duration=3,nearRadius=192}}end}
local V={safeCall=pcall}
function V.require(n)
  if n=='Config' then return Config end
  if n=='VoxelScene' then return {groundAt=function()return 0 end} end
  if n=='RenderDistance' then return {point=function()return true end} end
  error('no module '..tostring(n),0)
end

local player={px=32,py=32,cellX=2,cellY=2,def={sprite='SPRITE_RED'}}
local npc={px=48,py=48,cellX=3,cellY=3,facing='down',def={sprite='SPRITE_LASS'}}
-- A second pose call is deliberately forbidden. Current Battle Art has already
-- resolved the sprite/position and gives Weather FX the finished actor record.
function npc:pose() error('Weather FX must not pose live Battle Art NPC twice',0) end
local state={map={id='TEST'},player=player,entities={player,npc},ghosts={}}
local sprite={def={image='npc'},resolveImage=function()return{}end}
local posed={
  {entity=player,isPlayer=true,role='player',sprite=sprite,px=32,py=32,gh=0,lift=0,facing='down',phase=0,flip=false},
  -- Deliberately differs from raw coords. The bridge must use what Battle Art
  -- actually rendered, including the resolved support/lift.
  {entity=npc,isPlayer=false,role='npc',sprite=sprite,px=96,py=80,gh=6,lift=2,facing='left',phase=1,flip=false},
}
local Vox={
  eye={48,30,20},vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},
  size=function()return 320,288 end,
  project=function(x,y,z)return 140+(x-100)*.1,120,1 end,
}
local N=assert(loadfile(ROOT..'lib/voxel_atmos/NpcLightning.lua'))(V)
N.observe(state)
ck(type(N.observeActors)=='function','NpcLightning exposes current-host actor observation seam')
local observed=type(N.observeActors)=='function' and N.observeActors({state=state,player=player,posed=posed,host={Voxel3D=Vox}})
ck(observed==true,'Battle Art afterActors context is accepted without mutating host state')
ck(N.candidateCount(Vox,{})==1,'exact Battle Art posed list yields one visible non-player target')
N._setRandom(function()return 0 end)
local impact=N.rollImpact(Vox,1.0,{})
ck(impact and impact.npcTarget and impact.npcTarget.entity==npc,'3D lightning redirects onto the exact host-rendered NPC')
ck(impact and math.abs(impact.x-104)<1e-9 and math.abs(impact.z-88)<1e-9,'strike endpoint uses Battle Art rendered actor position instead of stale/raw coordinates')
ck(impact and impact.lightY and math.abs(impact.lightY-6.08)<1e-9 and impact.y>impact.lightY,'strike uses host-resolved support/lift for ground light and head endpoint')
local st=N.stats(Vox)
ck(st.hostActorBridge==true and (st.hostActorFrames or 0)>=1,'diagnostics prove live host actor bridge is active')

local f=assert(io.open(ROOT..'lib/DramalessAtmos.lua','rb'));local src=f:read('*a');f:close()
local wired=(src:find('hostLib.require("CharacterRenderers")',1,true)
    or src:find('pcall(hostLib.require,"CharacterRenderers")',1,true))
  and src:find('weather_fx_npc_lightning_observer',1,true)
  and src:find('NL.observeActors',1,true)
  and src:find('Atmos._lastPosed = context.posed',1,true)
ck(wired~=nil,'Dramaless installs Battle Art afterActors bridge before endScene lightning draw')

print(('8.1.93 Battle Art NPC lightning bridge: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
