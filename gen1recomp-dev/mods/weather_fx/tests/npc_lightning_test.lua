-- Rare visible-NPC lightning regression.
-- Proves configured roll/duration behavior, view/player/object filtering, reversible overlay,
-- and WorldLightning forced world endpoint metadata.

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local checks, failures = 0, 0
local function check(ok, msg)
  checks=checks+1
  if not ok then failures=failures+1; io.write("FAIL: ",msg,"\n") end
end

local fxDraws=0
local flatHistory={}
local function meshStub()
  return {setVertices=function() end,setDrawRange=function() end,release=function() end}
end
local function shaderStub()
  return {send=function() end,release=function() end}
end
love={graphics={
  setDepthMode=function() end,setBlendMode=function() end,setShader=function() end,setColor=function() end,
  newMesh=function() return meshStub() end,newShader=function() return shaderStub() end,
  draw=function() fxDraws=fxDraws+1 end,
}}

local VS={}
function VS.groundAt(map,cx,cz) return 4 end
local drawCalls=0
function VS.drawEntity(...) drawCalls=drawCalls+1; return true end
local RD={point=function() return true end}
local cfg={npcLightning={enabled=true,chance=0.10,duration=3.0}}
local V={}
function V.require(name)
  if name=="VoxelScene" then return VS end
  if name=="RenderDistance" then return RD end
  if name=="Config" then return {get=function() return cfg end} end
  error("unexpected require "..tostring(name),0)
end

local function entity(x,z,spriteName)
  local e={px=x,py=z,cellX=math.floor(x/16),cellY=math.floor(z/16),
    def={sprite=spriteName or "SPRITE_LASS"}}
  function e:pose()
    self._poseCalls=(self._poseCalls or 0)+1
    return {def={image="npc"},resolveImage=function() return {} end}, self.px, self.py, "down", 0, false
  end
  return e
end
local player=entity(40,40,"SPRITE_RED")
local npc=entity(96,80,"SPRITE_LASS")
local off=entity(400,80,"SPRITE_BUG_CATCHER")
local boulder=entity(110,80,"SPRITE_BOULDER"); boulder.def.pushable=true
local state={map={id="m"},player=player,entities={player,npc,off,boulder},ghosts={}}

local _canvas={getWidth=function() return 320 end,getHeight=function() return 288 end}
local Vox={
  eye={96,30,40}, vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},
  canvas=function() return _canvas end,
  size=function() return 320,288 end,
  project=function(x,y,z)
    if x>300 then return -50,100,1 end
    return 160+(x-104)*0.2, 120, 1
  end,
  flatten=function(color,amount)
    _G.__flatCalls=(_G.__flatCalls or 0)+1
    _G.__lastFlat=color
    if type(color)=="table" then flatHistory[#flatHistory+1]={color[1],color[2],color[3]} end
  end,
}

local N=assert(loadfile(ROOT.."lib/voxel_atmos/NpcLightning.lua"))(V)
local frontMetric=N.reactionMetrics({entity=npc,sprite={def={}},gh=4,lift=0,facing="down"})
local sideMetric=N.reactionMetrics({entity=npc,sprite={def={}},gh=4,lift=0,facing="left"})
local backMetric=N.reactionMetrics({entity=npc,sprite={def={}},gh=4,lift=0,facing="up"})
check(frontMetric.mode=="front" and frontMetric.eyeY>4 and frontMetric.headY>frontMetric.eyeY,"Gen1/Gen2 card-relative front face/head anchors are finite")
check(sideMetric.mode=="side" and sideMetric.side==-1,"side-facing sprite uses one visible-side eye anchor")
check(backMetric.mode=="back","back-facing sprite suppresses fake rear eyes")
local exact=N.reactionMetrics({entity={def={wxEyeAnchor={y=.60,sep=.10},wxHeadY=.82,wxWorldHeight=20,wxWorldWidth=18}},sprite={def={}},gh=2,lift=1,facing="down"})
check(math.abs(exact.eyeY-15)<1e-6 and math.abs(exact.headY-19.4)<1e-6,"sprite/entity metadata can provide exact Pokémon-specific eye/head anchors")
local neutral=N.reactionMetrics({entity={def={eyeAnchor={y=.58,sep=.08},headY=.84,spriteHeight=20,spriteWidth=18}},sprite={def={}},gh=2,lift=1,facing="right"})
check(neutral.mode=="side" and neutral.side==1 and math.abs(neutral.eyeY-14.6)<1e-6 and math.abs(neutral.headY-19.8)<1e-6,"neutral Gen1/Gen2 sprite metadata also supplies exact per-species anchors")
N.observe(state)
local seq,qi={0.099,0.0},1
N._setRandom(function() local v=seq[qi] or 0; qi=qi+1; return v end)
local impact=N.rollImpact(Vox,nil,{})
check(impact~=nil,"10% success roll finds a visible NPC")
check(impact and impact.npcTarget and impact.npcTarget.entity==npc,"player/offscreen/object candidates are excluded")
check(impact and math.abs(impact.x-104)<1e-6 and math.abs(impact.z-88)<1e-6,"NPC strike uses live sprite feet centre")
check(impact and math.abs(impact.y-18.4)<1e-6,"bolt endpoint lands at face-card-relative NPC head height")
check(impact and math.abs(impact.lightY-4.08)<1e-6,"localized strike light remains on ground under NPC")

N._setRandom(function() return 0.101 end)
check(N.rollImpact(Vox,nil,{})==nil,"roll above configured 10% keeps normal terrain targeting")
N._setRandom(function() return 0.0 end)
check(N.rollImpact(Vox,nil,{[npc]=true})==nil,"same NPC can be excluded from another bolt in the burst")

-- Voxel Realism keeps its exact posed list private. A live NPC must still be
-- targetable from authoritative state.entities coordinates even if pose() is
-- unavailable/unsafe when the lightning scheduler runs.
-- No def.sprite either: some live actors only resolve their visual identity via
-- pose(), and target admission must not depend on calling that method again.
local rawNpc={px=144,py=96,cellX=9,cellY=6,facing="left",def={}}
state.entities={player,rawNpc}; state.posed=nil; N.observe(state)
N._setRandom(function() return 0 end)
local rawImpact=N.rollImpact(Vox,1.0,{})
check(rawImpact and rawImpact.npcTarget and rawImpact.npcTarget.entity==rawNpc,
      "raw state.entities NPC remains eligible without pose()")
check(rawImpact and math.abs(rawImpact.x-152)<1e-6 and math.abs(rawImpact.z-104)<1e-6,
      "raw-coordinate NPC strike lands on actor world centre")
check((N.candidateCount and N.candidateCount(Vox,{}))==1,
      "live candidate diagnostic sees raw-coordinate NPC")

state.entities={player,npc,off,boulder}; N.observe(state)
cfg.npcLightning.enabled=false
check(N.rollImpact(Vox,nil,{})==nil,"config switch can disable the non-canon NPC lightning gag")
cfg.npcLightning.enabled=true

check(N.hit(impact.npcTarget),"hit starts temporary cartoon electrocution reaction")
check(N.activeCount()==1,"charred reaction is active immediately")
-- First flash: live NPC card goes bright white; eyes are deliberately hidden.
N.update(0.05)
local before=drawCalls; local fxBefore=fxDraws; local histBefore=#flatHistory
check(N.draw(Vox)==true and drawCalls==before+1,"impact flash redraws struck NPC as overlay")
local sawWhite=false for i=histBefore+1,#flatHistory do local c=flatHistory[i];if c[1]>.95 and c[2]>.95 and c[3]>.95 then sawWhite=true end end
check(sawWhite,"impact alternates through a bright cartoon flash")
check(fxDraws==fxBefore,"smoke waits until after the instantaneous strike flash begins")
-- Next alternating phase: black card plus visible procedural skeleton.
N.update(0.05)
fxBefore=fxDraws; histBefore=#flatHistory
check(N.draw(Vox)==true,"skeleton phase remains drawable")
local sawBlack=false for i=histBefore+1,#flatHistory do local c=flatHistory[i];if c[1]<.02 and c[2]<.02 and c[3]<.02 then sawBlack=true end end
check(sawBlack,"cartoon flash alternates to black silhouette")
check(fxDraws>=fxBefore+1,"black flash draws the internal skeleton before smoke onset")
-- After the sub-second electrocution flash, the ordinary charred/white-eye state returns.
for _=1,5 do N.update(0.16) end
fxBefore=fxDraws
check(N.draw(Vox)==true and fxDraws>=fxBefore+2,"post-flash charred state draws white eyes plus continuing smoke")
local smokeStats=N.stats()
check((smokeStats.smokeVerts or 0)>=72,"post-strike 3D smoke uses six large dual-layer puffs instead of sub-pixel wisps")
check((_G.__flatCalls or 0)>=2 and _G.__lastFlat==nil,"flatten override is always restored after overlay draw")
-- Smoke should still be puffing late in the requested three-second char period.
for _=1,7 do N.update(0.25) end
fxBefore=fxDraws
check(N.activeCount()==1 and N.draw(Vox)==true and fxDraws>=fxBefore+2,"smoke puff continues near the end of the three-second char state")
N.update(0.25)
check(N.activeCount()==1,"reaction remains active just before three seconds")
N.update(0.18)
check(N.activeCount()==0,"reaction expires after three seconds")
check(N.draw(Vox)==false,"expired reaction stops drawing and original host appearance is untouched")

-- Current voxel hosts publish the exact posed records they already drew. The
-- NPC lightning overlay must reuse those records rather than calling pose() a
-- second time and accidentally advancing an NPC hop/spinner animation.
local npc2=entity(128,80,"SPRITE_GENTLEMAN")
local function posed(e)
  local sprite={def={image="npc"},resolveImage=function() return {} end}
  return {entity=e,map=state.map,sprite=sprite,px=e.px,py=e.py,gh=4,lift=0,
          facing="down",phase=0,flip=false}
end
state.entities={player,npc,npc2}
state.posed={posed(player),posed(npc),posed(npc2)}
N.observe(state)
local poseBefore=(npc._poseCalls or 0)+(npc2._poseCalls or 0)
N._setRandom(function() return 0 end)
local posedImpact=N.rollImpact(Vox,1.0,{})
check(posedImpact and posedImpact.npcTarget,"posed-list targeting finds a visible NPC")
local poseAfter=(npc._poseCalls or 0)+(npc2._poseCalls or 0)
check(poseAfter==poseBefore,"target selection reuses host posed records without advancing NPC animation")
N.hit(posed(npc),3.0); N.hit(posed(npc2),3.0)
local drawBefore=drawCalls
local poseDrawBefore=(npc._poseCalls or 0)+(npc2._poseCalls or 0)
check(N.activeCount()==2,"two NPCs can hold simultaneous independent charred reactions")
check(N.draw(Vox)==true and drawCalls==drawBefore+2,"simultaneous NPC reactions redraw both targets")
check(((npc._poseCalls or 0)+(npc2._poseCalls or 0))==poseDrawBefore,
      "charred overlay draw reuses posed records without advancing NPC animation")
N.update(3.0) -- update intentionally clamps hitch dt; normal frame updates expire below
for _=1,12 do N.update(0.25) end
check(N.activeCount()==0,"simultaneous reactions independently restore after three seconds")

-- WorldLightning accepts the validated live NPC impact without changing its
-- normal map targeting API. No draw/GPU stub is required for allocation.
math.randomseed(4353)
local WL=assert(loadfile(ROOT.."lib/voxel_atmos/WorldLightning.lua"))(V)
local b=WL.strike({40,0,40},120,{Voxel3D=Vox,map=state.map,neighbors={},player=player,forcedImpact=impact})
local sample=WL.sample()
check(b~=nil and #sample==1,"forced NPC impact allocates one live world bolt")
check(sample[1].npcHit==true,"world bolt publishes NPC-hit metadata")
check(math.abs(sample[1].y-impact.y)<1e-6,"world bolt terminates at NPC head")
check(math.abs(sample[1].lightY-impact.lightY)<1e-6,"world lighting keeps the ground-level impact pool")

local callbackCount=0
WL.clear()
local burst=WL.strikeBurst({40,0,40},120,{Voxel3D=Vox,map=state.map,neighbors={},player=player,
  forcedImpactForBolt=function(i) callbackCount=callbackCount+1; return i==2 and impact or nil end},3)
check(callbackCount==3,"severe-storm burst asks for an NPC target independently per bolt")
local npcHits=0 for _,bb in ipairs(burst) do if bb.npcTarget then npcHits=npcHits+1 end end
check(npcHits==1,"only the bolt whose independent target roll succeeds becomes an NPC strike")

io.write(string.format("npc lightning: %d passed, %d failed\n",checks-failures,failures))
os.exit(failures==0 and 0 or 1)
