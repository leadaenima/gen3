local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/"
ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(ok,msg) if ok then passed=passed+1; print("PASS "..msg) else failed=failed+1; print("FAIL "..msg) end end

local setting='on'; local wx='GALE'; local chance=1
local cfg={tornado={enabled=true,everySeconds=120,minVisited=2,carryChance=.10,funnel=true,funnelSeconds=2.5,sandstorms=false}}
local Settings={
  is=function(k,v) return k=='tornado' and setting==v end,
  tornadoPickupChance=function() return chance end,
}
local ow={map={id='ROUTE_1',isWaterCell=function() return false end},player={cellX=1,cellY=2,facing='down',surfing=false}}
function ow:partyKnows() return false end
local Scene={now={visible='world',indoors=false,outdoor=true,mapId='ROUTE_1'},overworld=function() return ow end}
local startCount=0; local startOpts=nil; local doneCb=nil
local Funnel={active=false,update=function() end}
function Funnel.start(sec,done,opts) startCount=startCount+1; doneCb=done; startOpts=opts; Funnel.active=true end
function Funnel.stop() Funnel.active=false end
local State={level=1,current=function() return {id=wx} end}
local game={save={visited={ROUTE_1=true,PALLET=true,CERULEAN=true}},data={maps={
  ROUTE_1={id='ROUTE_1',outdoor=true,tileset='OVERWORLD',width=8,height=8,connections={right={map='PALLET',offset=0}},warps={}},
  PALLET={id='PALLET',outdoor=true,tileset='OVERWORLD',width=8,height=8,connections={left={map='ROUTE_1',offset=0}},warps={}},
  CERULEAN={id='CERULEAN',outdoor=true,tileset='OVERWORLD',width=8,height=8,connections={left={map='ROUTE_1',offset=0}},warps={}},
},field={outsideTilesets={OVERWORLD=true},tilesets={OVERWORLD={}},flyWarps={PALLET={x=3,y=4},CERULEAN={x=5,y=6}}}}}
local Map={}
function Map.isOutside(def) return def and def.outdoor==true end
function Map.isOutdoor(def) return def and def.outdoor==true end
function Map.defIsWaterCell() return false end
function Map.defIsWalkableCell(def,ts,x,y) return x>=0 and y>=0 and x<def.width and y<def.height end
function Map.defPassable(def,ts,x,y) return x>=0 and y>=0 and x<def.width and y<def.height end
package.preload['src.world.Map']=function() return Map end
local save={}; local carried=nil
local world={warpTo=function(self,d,x,y) carried=d; return true end}
local mod={game=game,world=world,save={set=function(self,k,v) save[k]=v end,get=function(self,k,d) local v=save[k];if v==nil then return d end;return v end},log={info=function() end,warn=function() end}}
local V={mod=mod}
function V.require(name)
  local m={Config={get=function() return cfg end},Settings=Settings,Scene=Scene,Funnel=Funnel,WeatherState=State,VoxelAtmosBridge={presentation3d=function() return false end,active=function() return false end}}
  if m[name] then return m[name] end error(name)
end
love={math={random=function() return 0 end}}
local T=assert(loadfile(ROOT..'lib/Tornado.lua'))(V); T._setRandom(function() return 0 end)

for _=1,480 do T.update(.25) end
check(startCount==1,'2D Gale schedules exactly one relocation tornado at carry interval')
check(startOpts and startOpts.mode=='carry2d','2D tornado explicitly uses left-to-right carry mode')
check(startOpts and tonumber(startOpts.pickupAt) and startOpts.pickupAt>0.4 and startOpts.pickupAt<0.7,'pickup occurs while tornado crosses screen centre')
check(type(startOpts and startOpts.onPickup)=='function','visual tornado has a mid-crossing pickup callback')
check(T.isCarrying(),'player movement is locked while 2D relocation tornado is active')
startOpts.onPickup()
check(carried=='CERULEAN' or carried=='PALLET','2D tornado relocates only to an already-visited destination')
check(carried~='ROUTE_1' and save.tornadoFrom=='ROUTE_1','2D tornado excludes current map and records safe origin')
doneCb(); Funnel.active=false
check(not T.isCarrying(),'player movement unlocks after tornado exits on destination map')

-- Non-Gale wind never gets a 2D tornado, even at 100% carry chance.
wx='STRONG_WINDS'; startCount=0; startOpts=nil; doneCb=nil; T._legacyTimer=0
for _=1,520 do T.update(.25) end
check(startCount==0,'2D tornado never spawns in STRONG WINDS; authored GALE only')

-- Carry chance OFF means no visual tornado at all.
wx='GALE'; chance=0; startCount=0; T._legacyTimer=0
for _=1,520 do T.update(.25) end
check(startCount==0,'CARRY CHANCE OFF means no 2D tornado is shown')

-- No eligible visited destination means no visual tornado at all.
chance=1; game.save.visited={ROUTE_1=true}; startCount=0; T._legacyTimer=0
for _=1,520 do T.update(.25) end
check(startCount==0,'no safe previously visited destination means no 2D tornado is shown')

print(('2D Gale relocation tornado 8.1.57: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
