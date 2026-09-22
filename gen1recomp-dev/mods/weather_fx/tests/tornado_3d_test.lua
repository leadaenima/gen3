-- Weather FX 3D Gale tornado + flat-world interaction regression.
-- Exercises behavior, not only source strings: distant spawn, fixed carry roll,
-- water ingestion, outbreak cap, pickup/visited-map transfer/landing, rope-out,
-- movement freeze, flat-world footprint classification and 3D mesh submission.

local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; io.write("FAIL: ",name,"\n") end
end
local function approx(a,b,e) return math.abs((a or 0)-(b or 0))<=(e or 1e-6) end

-- ---- FlatWorldInteraction executable behavior ----
local FWV={}
local fakeMap={id="MAP_A",widthCells=8,heightCells=8}
function fakeMap:cellTile(cx,cz)
  if cx==1 and cz==1 then return 2 end -- canopy
  if cx==2 and cz==1 then return 3 end -- roof/solid
  if cx==3 and cz==1 then return 4 end -- water shape
  return 1
end
function fakeMap:isWaterCell(cx,cz) return cx==4 and cz==1 end
local shapes={
  [1]={class="ground",h=0},[2]={class="tree",h=14},
  [3]={class="roof",h=12},[4]={class="water",h=0},
}
local TileShape={forMap=function(map) return shapes end}
local VoxelScene={groundAt=function(map,cx,cz) return (cx+cz)*0.25 end}
local FW=assert(loadfile(ROOT.."lib/FlatWorldInteraction.lua"))(FWV)
check(FW.observeVoxel({map=fakeMap,neighbors={}},VoxelScene,TileShape)==true,"flat-world field observes voxel map")
local q={}
FW.sampleAt(1*16+8,1*16+8,q); check(q.canopy and q.shelter>=.6,"tree/canopy creates shelter")
FW.sampleAt(2*16+8,1*16+8,q); check(q.roof and q.solid and q.shelter>.9,"roof is solid sheltered footprint")
FW.sampleAt(3*16+8,1*16+8,q); check(q.water and q.drag>1,"water shape is open high-flow footprint")
FW.sampleAt(4*16+8,1*16+8,q); check(q.water,"map water authority is recognized")
FW.sampleAt(0*16+8,1*16+8,q); check(q.shelter>0 and q.shelter<.9,"open cell receives nearby obstruction shelter")

-- Static map safety API used by the real tornado destination validator.
local MapAPI={}
function MapAPI.isOutside(def) return def and def.outdoor==true end
function MapAPI.isOutdoor(def) return def and def.outdoor==true end
function MapAPI.defIsWaterCell(def,tileset,x,y) return def and def.water and def.water[y..":"..x] or false end
function MapAPI.defIsWalkableCell(def,tileset,x,y) return x>=0 and y>=0 and x<(def.width or 0) and y<(def.height or 0) and not MapAPI.defIsWaterCell(def,tileset,x,y) and not (def.blocked and def.blocked[y..":"..x]) end
function MapAPI.defPassable(def,tileset,x,y,surfing)
  if x<0 or y<0 or x>=(def.width or 0) or y>=(def.height or 0) or (def.blocked and def.blocked[y..":"..x]) then return false end
  return MapAPI.defIsWalkableCell(def,tileset,x,y) or (surfing and MapAPI.defIsWaterCell(def,tileset,x,y))
end
package.preload["src.world.Map"]=function() return MapAPI end

-- ---- Tornado runtime harness ----
local values={tornado="on"}
local cfg={tornado={enabled=true,everySeconds=75,minVisited=4,carryChance=.10,
  roamSeconds=180,formationSeconds=8,ropeSeconds=12,spawnDistanceMin=150,
  spawnDistanceMax=250,maxActive=3,secondaryChance=.12,outbreakChance=.035,
  waterTwister=true,sandstorms=false,funnel=true,funnelSeconds=2.5}}
local weather={id="GALE"}
local scene={now={visible="world",indoors=false,outdoor=true,mapId="MAP_A",playerPosKnown=true,playerWorldX=0,playerWorldY=0}}
local player={px=0,py=0,cellX=0,cellY=0}
local voxelState={map={id="MAP_A"},player=player,neighbors={}}
local warpTarget,warpX,warpY=nil,nil,nil
local worldWarpCalls,privateWarpCalls=0,0
local ow={map={id="MAP_A",isWaterCell=function() return false end},player=player}
function ow:partyKnows(move) return move=="SURF" end
function ow:startWarpTo(dest,x,y)
  privateWarpCalls=privateWarpCalls+1
  assert(type(x)=="number" and type(y)=="number","real warp seam requires destination coordinates")
  warpTarget,warpX,warpY=dest,x,y; self.map={id=dest,isWaterCell=function() return false end}; scene.now.mapId=dest; voxelState.map={id=dest}
end
function scene.overworld() return ow end
local game={
  save={visited={MAP_A=true,MAP_B=true,MAP_C=true,MAP_D=true}},
  data={
    maps={
      MAP_A={id="MAP_A",outdoor=true,tileset="OVERWORLD",width=8,height=8,connections={right={map="MAP_B",offset=0}},warps={}},
      MAP_B={id="MAP_B",outdoor=true,tileset="OVERWORLD",width=8,height=8,connections={right={map="MAP_A",offset=0}},warps={}},
      MAP_C={id="MAP_C",outdoor=true,tileset="OVERWORLD",width=8,height=8,connections={right={map="MAP_A",offset=0}},warps={}},
      MAP_D={id="MAP_D",outdoor=true,tileset="OVERWORLD",width=8,height=8,connections={right={map="MAP_A",offset=0}},warps={}},
    },
    field={flyWarps={MAP_B={x=3,y=4},MAP_C={x=5,y=6},MAP_D={x=6,y=5}},outsideTilesets={OVERWORLD=true},tilesets={OVERWORLD={}}},
  },
}
local world={warpTo=function(self,dest,x,y,facing,opts)
  worldWarpCalls=worldWarpCalls+1
  assert(type(x)=="number" and type(y)=="number","supported WorldAPI warp requires coordinates")
  warpTarget,warpX,warpY,warpFacing=dest,x,y,facing
  scene.now.mapId=dest;ow.map={id=dest,isWaterCell=function() return false end};voxelState.map={id=dest}
  return true
end}
local bridge={active=function() return true end,presentation3d=function() return true end}
local flat={}
function flat.ready() return true end
function flat.sampleAt(x,z,out)
  out=out or {}; local water=(x>=90 and x<=220 and z>=-80 and z<=80)
  local solid=(x>=45 and x<=62 and z>=90 and z<=116)
  out.water=water;out.solid=solid;out.canopy=false;out.roof=solid
  out.shelter=solid and .96 or 0;out.drag=water and 1.08 or (solid and .25 or 1);out.groundY=0
  return out
end
local wind={direction=function() return 1,0 end,peek=function() return {x=1,z=0} end}
local modules={
  Config={get=function() return cfg end},
  Settings={is=function(k,v) return k=="tornado" and values.tornado==v end},
  WeatherState={current=function() return weather end},
  Scene=scene,VoxelAtmosBridge=bridge,FlatWorldInteraction=flat,WindEngine=wind,
}
local wrappedCollision=nil
local mod={game=game,world=world,save={_d={},set=function(self,k,v) self._d[k]=v end,get=function(self,k,d) local v=self._d[k];if v==nil then return d end;return v end},
  hooks={wrap=function(self,name,fn) if name=="movement.collision" then wrappedCollision=fn end end},
  log={info=function() end}}
local V={mod=mod,require=function(name) local m=modules[name];if m then return m end;error("unexpected require "..tostring(name),0) end}
local T=assert(loadfile(ROOT.."lib/Tornado.lua"))(V); modules.Tornado=T
T.observeVoxelState(voxelState)
check(T.installHooks()==true and type(wrappedCollision)=="function","carry installs documented movement-collision guard")

-- Host activity and Weather FX presentation are distinct. A live voxel host
-- with WX PRESENT=2D must stay on the relocation-only flat path; FPV/strict
-- 3D uses the procedural world-space controller.
bridge.presentation3d=function() return false end
check(T.describe():match("2d gale relocation")~=nil,"active voxel host + 2d presentation uses relocation-only 2d tornado path")
bridge.presentation3d=function() return true end
check(T.describe():match("3d gale")~=nil,"strict 3d presentation owns 3d Gale tornado")

local function seq(vals,default)
  local i=0;return function() i=i+1;local v=vals[i];if v==nil then return default or .5 end;return v end
end
-- Distance and angle consume first two RNG values; the third decides carry.
T._setRandom(seq({0,0,.099},.5))
local r=T.spawn(false)
check(r and r.seeker==true,"9.9% roll enters fixed 10% carry branch")
check(r and math.sqrt((r.x-player.px)^2+(r.z-player.py)^2)>=149,"carry tornado forms in the distance, not on player")
check(r and r.destination and r.destination~="MAP_A","carry destination is an already visited different map")
T.invalidate();T.observeVoxelState(voxelState);scene.now.mapId="MAP_A";ow.map={id="MAP_A"};voxelState.map={id="MAP_A"};warpTarget=nil
T._setRandom(seq({0,0,.101},.5))
r=T.spawn(false)
check(r and r.seeker==false,"10.1% roll does not pick player up")

-- Water ingestion is gradual and reversible while roaming.
r.stage="roam";r.age=9;r.roamAge=0;r.x=105;r.z=0;r.heading=0;r.speed=1;r.waterBlend=0
for _=1,12 do T.update(.25) end
check(r.waterBlend>.5,"roaming tornado gradually becomes water-loaded over water")
r.x=260;r.z=0;r.heading=0;r.speed=1
for _=1,16 do T.update(.25) end
check(r.waterBlend<.5,"water twister drains back toward ordinary funnel off water")

-- Three minutes means 180 seconds of mature roam, then upward rope-out.
r.stage="roam";r.roamAge=179.5;r.age=20;r.x=260;r.z=0
for _=1,3 do T.update(.25) end
check(r.stage=="rope","mature roamer ropes out after about 180 seconds")
local before=#T.renderState(); weather.id="CLEAR"; for _=1,49 do T.update(.25) end
check(#T.renderState()==before-1,"rope-out completes and removes expired tornado")
weather.id="GALE"

-- Rare outbreak remains bounded to maxActive=3.
T.invalidate();T.observeVoxelState(voxelState);scene.now.mapId="MAP_A";ow.map={id="MAP_A"};voxelState.map={id="MAP_A"}
cfg.tornado.carryChance=0;cfg.tornado.outbreakChance=1;cfg.tornado.secondaryChance=1;cfg.tornado.maxActive=3
T._setRandom(function() return 0 end)
for _=1,38 do T.update(.25) end -- first schedule is 9 seconds at RNG=0
check(#T.renderState()==3,"rare outbreak can spawn multiple simultaneous Gale tornadoes")
for _=1,340 do T.update(.25) end
check(#T.renderState()<=3,"multi-tornado storm never exceeds hard active cap")

-- Player-seeking tornado physically approaches before pickup, then transfers to
-- visited map, resumes airborne on destination, lands gently and ropes out.
T.invalidate();scene.now.mapId="MAP_A";ow.map={id="MAP_A"};voxelState.map={id="MAP_A"};warpTarget=nil
cfg.tornado.carryChance=.10;cfg.tornado.outbreakChance=0;cfg.tornado.secondaryChance=0
T.observeVoxelState(voxelState);T._setRandom(seq({0,0,.099},.5))
r=T.spawn(false);check(r and r.seeker,"carry scenario spawned seeker")
local spawnedX,spawnedZ=r.x,r.z
for _=1,120 do T.update(.25); if r.stage=="pickup" then break end end
check(r.stage=="pickup","seeker travels across map and reaches player before pickup")
check(math.sqrt((spawnedX-player.px)^2+(spawnedZ-player.py)^2)>100,"seeker did not spawn over player")
local pp=T.presentationPose();check(pp and pp.lift>=2,"pickup supplies airborne orbit presentation pose")
local allow=wrappedCollision(function() return true end,true,{mover=player})
check(allow==false,"real player movement is frozen only during tornado carry")
for _=1,20 do T.update(.25) end
check(warpTarget~=nil and (warpTarget=="MAP_B" or warpTarget=="MAP_C" or warpTarget=="MAP_D") and type(warpX)=="number" and type(warpY)=="number","pickup uses supported guarded warp with real coordinates to visited map")
check(worldWarpCalls==1 and privateWarpCalls==0,"current-host carry succeeds through public world API without private fallback")
T.observeVoxelState(voxelState)
for _=1,8 do T.update(.25) end
check(r.stage=="landing","destination map resumes same carry as landing stage")
local landStart=T.presentationPose();check(landStart and landStart.lift>10,"player remains airborne at start of destination landing")
for _=1,14 do T.update(.25) end
local landLate=T.presentationPose();check(landLate==nil or landLate.lift<landStart.lift,"landing lowers player rather than dropping instantly")
for _=1,3 do T.update(.25) end
check(r.stage=="rope" and not T.isCarrying(),"control returns after gentle landing and tornado begins rope-out above player")

-- ---- Real 3D procedural mesh submission ----
local drawCount,submitted,submittedMaxY=0,0,-1e9
love={graphics={
  newShader=function() return {send=function() end} end,
  newMesh=function(fmt,cap,mode,usage)
    return {setVertices=function(self,v,s,n)
      submitted=math.max(submitted,n or #v)
      for i=1,(n or #v) do local row=v[i];if row and tonumber(row[2]) then submittedMaxY=math.max(submittedMaxY,row[2]) end end
    end,setDrawRange=function() end}
  end,
  setBlendMode=function() end,setDepthMode=function() end,setShader=function() end,setColor=function() end,
  draw=function() drawCount=drawCount+1 end,
}}
-- Put a mature waterspout back in the renderer list.
T.invalidate();T.observeVoxelState(voxelState)
local live=T.renderState();live[1]={id=91,x=120,z=0,age=30,formation=8,roamFor=180,ropeFor=12,stage="roam",ropeAge=0,spin=4.6,waterBlend=1,groundY=0}
modules.CinematicAtmos={precipitationDeck=function() return 177,18 end}
modules.WeatherState={elapsed=31,current=function() return weather end}
local T3=assert(loadfile(ROOT.."lib/voxel_atmos/Tornado3D.lua"))(V)
local Vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},eye={0,20,-40},beginEffect=function() return false end,endEffect=function() end}
check(T3.draw(Vox)==true and drawCount==1,"world-space tornado submits real 3D mesh")
check(submitted>1000,"procedural funnel has dense shell/helix/debris geometry without particle pool")
check(submittedMaxY>174,"tornado geometry physically reaches the 50-percent-raised live cloud deck")
local geom,layers=T3.geometryStatus()
check(geom>1800 and layers.shell and layers.sheath and layers.wallCloud and layers.waterSpray and layers.debris,
  "realistic waterspout adds surface spray, ragged sheath, wall-cloud attachment and ingested debris")
check(not layers.groundSkirt,"full waterspout uses water spray instead of fake land dust skirt")
live[1].waterBlend=0;submitted=0
check(T3.draw(Vox)==true,"land tornado realism pass submits")
local geom2,layers2=T3.geometryStatus()
check(geom2>geom*.75 and layers2.groundSkirt==true and not layers2.waterSpray,"land tornado adds broad low dirt/debris ground-contact skirt")
check(geom2<6000,"single realistic tornado geometry remains strictly bounded for low-end hardware")

io.write(string.format("3d Gale tornado: %d passed, %d failed\n",passed,failed))
os.exit(failed==0 and 0 or 1)
