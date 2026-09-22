-- Weather FX 8.1.60: real 2D NPC lightning targeting/reaction contract.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local checks,fail=0,0
local function ck(v,m) checks=checks+1;if v then io.write("PASS ",m,"\n") else fail=fail+1;io.write("FAIL ",m,"\n") end end

local drawCalls,circles,lines,rects=0,0,0,0
local currentShader=nil
local shader={send=function() end}
love={
  math={random=function() return .5 end},
  graphics={
    newShader=function() return shader end,
    getShader=function() return currentShader end,setShader=function(s) currentShader=s end,
    getColor=function() return 1,1,1,1 end,setColor=function() end,
    push=function() end,pop=function() end,translate=function() end,scale=function() end,
    setLineWidth=function() end,
    draw=function() drawCalls=drawCalls+1 end,
    circle=function() circles=circles+1 end,
    line=function() lines=lines+1 end,
    rectangle=function() rects=rects+1 end,
  }
}

local cfg={npcLightning={enabled=true,chance=.10,duration=3.0}}
local sprite={frameWidth=16,frameHeight=16,anchorX=8,anchorY=16,image={}}
function sprite:getScreenOrigin(px,py,cx,cy) return px-cx,py-cy-4 end
function sprite:getPoseGeometry(facing,phase,flip) return {width=16,height=16,anchorX=8,anchorY=16,quad={},mirror=flip and true or false} end
function sprite:resolveImage() return self.image end
local function ent(x,y,name)
  local e={px=x,py=y,cellX=math.floor(x/16),cellY=math.floor(y/16),facing="down",sprite=sprite,def={sprite=name or "SPRITE_LASS"}}
  function e:pose() return self.sprite,self.px,self.py,self.facing,0,false end
  return e
end
local player=ent(40,40,"SPRITE_RED")
local npc=ent(96,80,"SPRITE_LASS")
local off=ent(400,80,"SPRITE_BUG_CATCHER")
local rock=ent(112,80,"SPRITE_BOULDER");rock.def.pushable=true
local ow={player=player,npcs={npc,off,rock},entities={player,npc,off,rock},camera={x=40,y=40}}
local Scene={now={visible="world",outdoor=true,indoors=false,camX=40,camY=40},viewport={x=80,y=0,w=800,h=720},overworld=function() return ow end}
local V={}
function V.require(name)
  if name=="Scene" then return Scene end
  if name=="Config" then return {get=function() return cfg end} end
  error("unexpected require "..tostring(name),0)
end

local N=assert(loadfile(ROOT.."lib/NpcLightning2D.lua"))(V)
local seq,i={.099,0},1
N._setRandom(function() local v=seq[i] or 0;i=i+1;return v end)
local impact=N.rollImpact(40,40,960,720,nil,0,0)
ck(impact and impact.entity==npc,"10% 2D roll selects the visible real NPC and excludes player/object/offscreen actors")
ck(impact and math.abs(impact.hitX-400)<.01,"2D bolt x endpoint includes the real letterboxed playfield offset")
ck(impact and math.abs(impact.hitY-202.4)<.2,"2D bolt y endpoint lands on the current NPC head/upper body")
N._setRandom(function() return .101 end)
ck(N.rollImpact(40,40,960,720,nil,0,0)==nil,"roll above 10% leaves ordinary 2D terrain lightning unchanged")

ck(N.hit(impact),"2D hit starts a three-second presentation-only NPC reaction")
N.update(.05);local c0=circles
ck(N.draw(0,0,960,720,40,40)==true and drawCalls>=1,"struck 2D NPC is redrawn over the finished world frame")
ck(circles==c0,"2D smoke begins after the initial electrical flash instead of hiding in it")
N.update(.20);c0=circles
ck(N.draw(0,0,960,720,40,40)==true and circles>=c0+2,"large high-contrast smoke puffs visibly start after impact")
N.update(.55);local l0=lines
ck(N.draw(0,0,960,720,40,40)==true,"charred 2D reaction remains active after the electrocution flash")
ck(circles>c0,"smoke keeps emitting during the charred state")
for _=1,9 do N.update(.25) end
ck(N.activeCount()==1,"2D char/smoke reaction survives nearly the full configured three seconds")
N.update(.25);N.update(.05)
ck(N.activeCount()==0,"2D reaction restores the untouched NPC after three seconds")

-- The physical overlay channel itself must be retargetable without changing the
-- strike serial/pulse authority that audio and 3D consumers share.
local L=assert(loadfile(ROOT.."lib/Lightning.lua"))(V)
L.timer=0
L.update(.016,60,"full",40,40,960,720,6,"STORM")
local serial=L.strikeSerial
ck(serial>0 and L.retarget(impact.hitX,impact.hitY,40,40,960,720,6),"live 2D lightning channel accepts the validated NPC endpoint")
ck(math.abs((L.hitX or 0)-impact.hitX)<1e-6 and math.abs((L.hitY or 0)-impact.hitY)<1e-6,"retargeted 2D bolt terminates exactly on the selected NPC")
ck(L.strikeSerial==serial,"retargeting preserves the original strike/thunder serial")

io.write(string.format("8.1.60 2D NPC lightning: %d passed, %d failed\n",checks-fail,fail))
os.exit(fail==0 and 0 or 1)
