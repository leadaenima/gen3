local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local pass,fail=0,0
local function check(v,n) if v then pass=pass+1 else fail=fail+1;io.write("FAIL: ",n,"\n") end end
local cfg={wind={playerMovement=true,headwindSlow=.10,tailwindBoost=.04,minimumStrength=.10}}
local flow={x=1,z=0,speed=1.2,shelter=0}
local scene={now={playerWorldX=100,playerWorldY=100}}
local tornado={isCarrying=function() return false end}
local modules={Config={get=function() return cfg end},WindFlow={sampleAt=function() return flow end},Scene=scene,Tornado=tornado,WindEngine={peek=function() return flow end}}
local wrapped=nil
local mod={hooks={wrap=function(self,name,fn) if name=="movement.speed" then wrapped=fn end end}}
local V={mod=mod,require=function(n) local m=modules[n];if m then return m end;error("missing "..n,0) end}
local W=assert(loadfile(ROOT.."lib/WindPlayer.lua"))(V)
check(W.distanceMultiplier(-1,0)<.91,"strong headwind produces bounded walking resistance")
check(W.distanceMultiplier(1,0)>1.03 and W.distanceMultiplier(1,0)<1.05,"tailwind assistance is deliberately smaller than headwind penalty")
check(math.abs(W.distanceMultiplier(0,1)-1)<.001,"crosswind does not cheaply speed/slow forward travel")
flow.speed=.05;flow.x=.05;check(W.distanceMultiplier(-1,0)==1,"calm/lull produces no movement penalty")
flow.speed=1.2;flow.x=1
check(W.installHooks() and type(wrapped)=="function","documented movement.speed hook installed")
local p={facing="left",surfing=false}
local head=wrapped(function(fr) return fr end,20,{player=p,onBike=false,surfing=false})
p.facing="right";local tail=wrapped(function(fr) return fr end,20,{player=p,onBike=false,surfing=false})
check(head>20,"walking against wind increases step duration")
check(tail<20 and tail>19,"walking with wind very slightly decreases step duration")
-- Voxel/base-game speed mods can legitimately return sub-1-frame movement
-- durations. Weather FX must preserve that host timescale instead of clamping
-- everything back to one frame and making fast speed tiers indistinguishable.
p.facing="left"
local fastHead=wrapped(function() return 0.50 end,20,{player=p,onBike=false,surfing=false})
p.facing="right"
local fastTail=wrapped(function() return 0.50 end,20,{player=p,onBike=false,surfing=false})
check(fastHead>0.50 and fastHead<0.60,"sub-1-frame host speed survives headwind as a ratio")
check(fastTail<0.50 and fastTail>0.45,"sub-1-frame host speed survives tailwind as a ratio")
check(fastHead<1 and fastTail<1,"Weather FX never clamps fast host movement back to one frame")
local bike=wrapped(function(fr) return fr end,20,{player=p,onBike=true,surfing=false})
local surfv=wrapped(function(fr) return fr end,20,{player=p,onBike=false,surfing=true})
check(bike==20 and surfv==20,"bike and Surf speed are not modified by weather wind")
cfg.wind.playerMovement=false;check(W.distanceMultiplier(-1,0)==1,"player setting/config can disable wind movement effect")
cfg.wind.playerMovement=true;tornado.isCarrying=function() return true end;check(W.distanceMultiplier(-1,0)==1,"tornado carry is never double-modified by wind walking")

-- FreeMove/FPV path: wrapper scales host world movement vector in memory and restores it.
tornado.isCarrying=function() return false end
local FP={moveWorld=function() return -1,0 end};local FM={tick=function() return FP.moveWorld() end}
local host={require=function(n) if n=="FreeMove" then return FM elseif n=="FirstPerson" then return FP end error(n) end}
check(W.installFreeMove(host)==true,"FPV/free-move host receives optional in-memory wind wrapper")
local x,z=FM.tick();check(x>-1 and x<-.88 and z==0,"free-move headwind reduces actual movement vector without changing collision authority")
io.write(string.format("wind player: %d passed, %d failed\n",pass,fail));os.exit(fail==0 and 0 or 1)
