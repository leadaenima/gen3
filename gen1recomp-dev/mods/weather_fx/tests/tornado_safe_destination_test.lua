local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local pass,fail=0,0
local function check(v,n) if v then pass=pass+1 else fail=fail+1;io.write("FAIL: ",n,"\n") end end

local Map={}
function Map.isOutside(def) return def and def.outdoor==true end
function Map.isOutdoor(def) return def and def.outdoor==true end
function Map.defIsWaterCell(def,ts,x,y) return def and (def.waterAll==true or (def.waterCells and def.waterCells[y..":"..x])) or false end
function Map.defIsWalkableCell(def,ts,x,y)
  return x>=0 and y>=0 and x<(def.width or 0) and y<(def.height or 0) and not Map.defIsWaterCell(def,ts,x,y) and not (def.blocked and def.blocked[y..":"..x])
end
function Map.defPassable(def,ts,x,y,surfing)
  if x<0 or y<0 or x>=(def.width or 0) or y>=(def.height or 0) or (def.blocked and def.blocked[y..":"..x]) then return false end
  return (not Map.defIsWaterCell(def,ts,x,y)) or (surfing and true or false)
end
package.preload["src.world.Map"]=function() return Map end

local function outdoor(id,connections,extra)
  local d={id=id,outdoor=true,tileset="OVERWORLD",width=6,height=6,connections=connections or {},warps={}}
  for k,v in pairs(extra or {}) do d[k]=v end;return d
end
local maps={
  ORIGIN=outdoor("ORIGIN",{right={map="SAFE",offset=0}}),
  SAFE=outdoor("SAFE",{left={map="ORIGIN",offset=0}}),
  ISLAND=outdoor("ISLAND",{}), -- flat but no way off
  DOOR=outdoor("DOOR",{right={map="SAFE",offset=0}},{warps={{x=2,y=2}}}),
  WATER=outdoor("WATER",{right={map="WATER2",offset=0}},{waterAll=true}),
  WATER2=outdoor("WATER2",{left={map="WATER",offset=0}},{waterAll=true}),
  SURF_ISLAND=outdoor("SURF_ISLAND",{right={map="WATER2",offset=0}},{waterCells={ ["2:3"]=true,["2:4"]=true,["2:5"]=true }}),
  CAVE={id="CAVE",outdoor=false,tileset="CAVE",width=6,height=6,connections={},warps={}},
  HOUSE={id="HOUSE",outdoor=false,tileset="HOUSE",width=6,height=6,connections={},warps={}},
}
local game={save={visited={ORIGIN=true,SAFE=true,ISLAND=true,DOOR=true,WATER=true,SURF_ISLAND=true,CAVE=true,HOUSE=true}},data={maps=maps,field={outsideTilesets={OVERWORLD=true},tilesets={OVERWORLD={},CAVE={},HOUSE={}},flyWarps={SAFE={x=2,y=2},ISLAND={x=2,y=2},DOOR={x=2,y=2},WATER={x=2,y=2},SURF_ISLAND={x=2,y=2},CAVE={x=2,y=2},HOUSE={x=2,y=2}}}}}
local surf=false
local player={cellX=2,cellY=2,facing="down",surfing=false,px=32,py=32}
local ow={map={id="ORIGIN",isWaterCell=function() return false end},player=player}
function ow:partyKnows(m) return m=="SURF" and surf end
function ow:syncSurfingPikachu() self.synced=true end
local scene={now={visible="world",outdoor=true,indoors=false,mapId="ORIGIN",playerPosKnown=true,playerWorldX=32,playerWorldY=32}}
function scene.overworld() return ow end
local values={tornado="on"}
local cfg={indoorMaps={HOUSE=true,CAVE=true},tornado={enabled=true,minVisited=2,carryChance=.10,roamSeconds=180,formationSeconds=8,ropeSeconds=12,spawnDistanceMin=150,spawnDistanceMax=250,maxActive=3,secondaryChance=0,outbreakChance=0,waterTwister=true}}
local modules={Config={get=function() return cfg end},Settings={is=function(k,v) return k=="tornado" and values.tornado==v end},WeatherState={current=function() return {id="GALE"} end},Scene=scene,VoxelAtmosBridge={presentation3d=function() return true end},WindEngine={direction=function() return 1,0 end}}
local warpCalls={}
local mod={game=game,save={_d={},set=function(self,k,v) self._d[k]=v end,get=function(self,k,d) local v=self._d[k];if v==nil then return d end;return v end},world={},hooks={wrap=function() end},log={info=function() end,warn=function() end}}
function mod.world:warpTo(id,x,y,facing,opts)
  warpCalls[#warpCalls+1]={id=id,x=x,y=y}
  scene.now.mapId=id;ow.map={id=id,isWaterCell=function(self,cx,cy) return maps[id].waterAll==true end};player.cellX,player.cellY=x,y
  return true
end
local V={mod=mod,require=function(n) local m=modules[n];if m then return m end;error("missing "..n,0) end}
local T=assert(loadfile(ROOT.."lib/Tornado.lua"))(V);modules.Tornado=T

check(T.validateLanding("SAFE",2,2,"land")==true,"walkable outdoor landing with outdoor edge exit is safe")
check(T.validateLanding("ISLAND",2,2,"land")==false,"flat isolated outdoor map with no exit is rejected")
check(T.validateLanding("DOOR",2,2,"land")==false,"door/cave-entrance warp cell is rejected as landing")
check(T.validateLanding("CAVE",2,2,"land")==false,"cave map is categorically rejected")
check(T.validateLanding("HOUSE",2,2,"land")==false,"building/interior map is categorically rejected")
check(T.landingFor("SAFE") and T.landingFor("SAFE").mode=="land","safe fly coordinate accepted only after escape proof")
check(T.landingFor("ISLAND")==nil,"visited plus flat does not make isolated map eligible")
check(T.landingFor("CAVE")==nil and T.landingFor("HOUSE")==nil,"visited interiors never become tornado destinations")
local dl=T.landingFor("DOOR");check(dl and dl.source=="connection" and not (dl.x==2 and dl.y==2),"unsafe Fly/door coordinate is rejected while a separate safe outdoor-connection cell remains eligible")
check(T.landingFor("WATER")==nil,"water-only destination rejected without current Surf capability")
check(T.landingFor("SURF_ISLAND")==nil,"land island whose only escape requires water is rejected without Surf")

surf=true
local wl=T.landingFor("WATER")
check(wl and wl.mode=="water","water destination becomes eligible only with legal Surf capability")
check(T.validateLanding("WATER",2,2,"water")==true,"Surf path can reach a real outdoor water connection")
check(T.landingFor("SURF_ISLAND") and T.landingFor("SURF_ISLAND").mode=="land","land island becomes eligible when a walk+Surf route proves escape")
T.remember("ORIGIN",2,2,"down",false)
check(T.carry("WATER")==true,"guarded carry accepts proven water destination when Surf is known")
check(scene.now.mapId=="WATER","carry uses explicit safe destination")
check(player.surfing==false,"warp itself does not falsely claim Surf active")
check(T.activateSurfLanding(wl)==true and player.surfing==true and ow.synced==true,"water landing activates Surf before control can return")

-- If the party loses/host refuses Surf before landing can be established, fail
-- safe by returning to the exact origin rather than releasing control on water.
player.surfing=false;surf=false
T.remember("ORIGIN",2,2,"left",false)
local r={stage="transfer"}
check(T.activateSurfLanding(wl)==false,"water landing refuses to release player when Surf cannot be established")
check(T.emergencyReturn(r)==true and r.stage=="returning","failed Surf activation immediately starts emergency return")
check(warpCalls[#warpCalls].id=="ORIGIN","emergency return targets saved valid origin, not another guessed cell")

-- Only safe/usable maps survive the destination list.
scene.now.mapId="ORIGIN";ow.map={id="ORIGIN",isWaterCell=function() return false end};surf=false
local ds=T.destinations("ORIGIN");local set={};for _,id in ipairs(ds) do set[id]=true end
check(set.SAFE==true,"safe outdoor destination remains selectable")
check(set.DOOR and not set.ISLAND and not set.CAVE and not set.HOUSE and not set.WATER and not set.SURF_ISLAND,"only destinations with a distinct proven safe landing survive filtering")

io.write(string.format("tornado safe destinations: %d passed, %d failed\n",pass,fail))
os.exit(fail==0 and 0 or 1)
