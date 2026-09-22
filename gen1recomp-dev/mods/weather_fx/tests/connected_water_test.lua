local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,msg) if v then passed=passed+1;print("PASS "..msg) else failed=failed+1;print("FAIL "..msg) end end
local wind={x=1,z=.35,strength=.8,envelope=.8}
local phase=0
local modules={
  WindEngine={peek=function() return wind end},
  CelestialSim={sample=function() return {moon={phase=phase}} end},
  TimeOfDay={hour=6},
  Microclimate={peek=function() return {temperature=-7} end},
}
local wrapped
local mod={hooks={wrap=function(self,n,fn) if n=="movement.collision" then wrapped=fn end end}}
local V={mod=mod,require=function(n) if modules[n] then return modules[n] end error(n,0) end}
local CW=assert(loadfile(ROOT.."lib/ConnectedWater.lua"))(V);modules.ConnectedWater=CW
local function map(id,w,h,water)
  return {id=id,widthCells=w,heightCells=h,isWaterCell=function(self,x,z) return water[x..":"..z] or false end,isWalkableCell=function() return false end}
end
local a=map("A",2,2,{["0:0"]=true,["1:0"]=true,["0:1"]=true,["1:1"]=true})
local p={px=0,py=32,cellX=0,cellY=2,surfing=false}
CW.observeVoxel({map=a,neighbors={},player=p})
check(#CW.bodies==1 and CW.bodies[1].area==4,"four adjacent water cells become one body")
check(#CW.bodies[1].rects==1 and CW.bodies[1].rects[1].cells==4,"solid connected mask greedily merges to one surface rectangle")
local b=map("B",1,2,{["0:0"]=true})
CW.observeVoxel({map=a,neighbors={{map=b,ox=32,oy=0}},player=p})
check(#CW.bodies==1 and CW.bodies[1].area==5,"water stitches across connected map seam")
local c=map("C",4,1,{["0:0"]=true,["3:0"]=true})
CW.observeVoxel({map=c,neighbors={},player=p})
check(#CW.bodies==2,"disconnected ponds stay distinct")
-- Static map water masks are cached: an unchanged render topology must not
-- rescan every collision cell every frame.
local scans=0;local perf=map("PERF",3,3,{["1:1"]=true});local oldWater=perf.isWaterCell
perf.isWaterCell=function(self,x,z) scans=scans+1;return oldWater(self,x,z) end
CW.observeVoxel({map=perf,neighbors={},player=p});local firstScans=scans
for i=1,20 do CW.observeVoxel({map=perf,neighbors={},player=p}) end
check(firstScans==9 and scans==firstScans,"unchanged voxel topology reuses cached water mask without per-frame map scan")
-- Persist thermodynamics by real map+cell identity when a body leaves the
-- visible connected-map set, but never into an unrelated map at same coords.
CW.bodies[1].ice=.73;CW.bodies[1].temp=-4
local away=map("AWAY",1,1,{})
CW.observeVoxel({map=away,neighbors={},player=p})
local perfAgain=map("PERF",3,3,{["1:1"]=true})
CW.observeVoxel({map=perfAgain,neighbors={},player=p})
check(math.abs(CW.bodies[1].ice-.73)<.001,"water thermal state survives leaving and revisiting a map body")
local unrelated=map("UNRELATED",3,3,{["1:1"]=true});CW.observeVoxel({map=unrelated,neighbors={},player=p})
check(CW.bodies[1].ice<.01,"unrelated map at identical local coordinates cannot inherit water state")
-- Return to A and freeze it while player remains on dry land.
p.px,p.py,p.cellX,p.cellY=0,48,0,3
CW.observeVoxel({map=a,neighbors={},player=p})
local state={channel=function(k) return k=="snow" and 1 or 0 end}
for i=1,260 do CW.observeVoxel({map=a,neighbors={},player=p});CW.update(.25,state,{id="WINTER"}) end
local body=CW.bodies[1]
check(body.ice>=CW.LOAD_BEARING and body.loadBearing,"winter thermal state reaches load-bearing ice")
check(CW.isLoadBearingAt(8,8),"fresh observed frozen water reports walkable support")
check(CW.installHooks() and type(wrapped)=="function","documented movement collision hook installs")
local ctx={map=a,mover=p,toX=0,toY=0,fromX=0,fromY=1,reason="tile"}
local allowed=wrapped(function(v) return v end,false,ctx)
check(allowed==true and ctx.reason=="weather_fx_ice","only frozen cartridge water tile refusal is widened")
local entityCtx={map=a,mover=p,toX=0,toY=0,reason="entity"}
check(wrapped(function(v) return v end,false,entityCtx)==false,"entity collision remains blocked on ice")
p.surfing=true;ctx.reason="tile";check(wrapped(function(v) return v end,false,ctx)==false,"Surf movement is never rewritten by ice hook");p.surfing=false
-- Hold a player already standing on ice while warm thaw tries to remove it.
p.px,p.py=0,0;CW.observeVoxel({map=a,neighbors={},player=p});modules.Microclimate.peek=function() return {temperature=22} end
for i=1,180 do CW.observeVoxel({map=a,neighbors={},player=p});CW.update(.25,{channel=function() return 0 end},{id="SUMMER"}) end
check(CW.bodies[1].ice>=CW.THAW_HOLD,"thaw cannot remove load-bearing ice under player")
-- A player already on open/surf water cannot be trapped by new freeze.
CW.invalidate();modules.Microclimate.peek=function() return {temperature=-10} end;p.surfing=true
local surfMap=map("A_SURF",2,2,{["0:0"]=true,["1:0"]=true,["0:1"]=true,["1:1"]=true})
CW.observeVoxel({map=surfMap,neighbors={},player=p})
for i=1,320 do CW.observeVoxel({map=surfMap,neighbors={},player=p});CW.update(.25,state,{id="WINTER"}) end
check(CW.bodies[1].ice<CW.LOAD_BEARING and not CW.bodies[1].loadBearing,"active surfer prevents water freezing into walkable ice underneath")
p.surfing=false
-- Moon and size response.
local ocean=map("O",8,8,(function() local t={} for x=0,7 do for z=0,7 do t[x..":"..z]=true end end return t end)())
p.px,p.py=200,200;CW.observeVoxel({map=ocean,neighbors={},player=p});modules.Microclimate.peek=function() return {temperature=12} end
phase=0;modules.TimeOfDay.hour=3;CW.update(.25,{channel=function() return 0 end},{id="SUMMER"});local spring=math.abs(CW.bodies[1].tide)
phase=.25;CW.update(.25,{channel=function() return 0 end},{id="SUMMER"});local neap=math.abs(CW.bodies[1].tide)
check(spring>neap,"new/full moon spring tide exceeds quarter-moon neap tide")
wind.x,wind.z=0,1;CW.update(.25,{channel=function(k) return k=="rain" and 1.2 or 0 end},{id="SUMMER"})
check(math.abs(CW.windX)<.01 and CW.windZ>.99,"both world wind axes drive water direction")
for i=1,20 do CW.update(.25,{channel=function(k) return k=="rain" and 2 or 0 end},{id="SUMMER"}) end
check(#CW.ripples<=CW.MAX_RIPPLES and #CW.ripples>0,"rain ripple pool is active and globally bounded")
CW.observationAge=2
check(not CW.isLoadBearingAt(8,8),"stale 3D observation cannot leak ice collision into non-voxel play")
local s=CW.sample();check(s.bodies==1 and s.cells==64 and s.moonPhase==phase,"hydrosphere publishes bounded diagnostics")
print(string.format("connected water 8.1.29: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
