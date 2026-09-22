local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local p,f=0,0;local function ck(v,m) if v then p=p+1;print('PASS '..m) else f=f+1;print('FAIL '..m) end end
local cfg={tornado={enabled=true,everySeconds=120,maxActive=3,formationSeconds=8,roamSeconds=180,ropeSeconds=12,carryChance=1,touchRadius=14,waterTwister=true,funnel=true,funnelSeconds=2.5,sandstorms=false}}
local Settings={is=function(k,v) return k=='tornado' and v=='on' end,tornadoPickupChance=function() return 1 end,weatherDisabled=function() return false end};local WS={level=1,current=function() return {id='GALE'} end}
local defs={A={id='A',outdoor=true,tileset='OVERWORLD',width=8,height=8,connections={right={map='B',offset=0}},warps={}},B={id='B',outdoor=true,tileset='OVERWORLD',width=8,height=8,connections={left={map='A',offset=0}},warps={}}}
local Map={};function Map.isOutside(d) return d.outdoor end;function Map.isOutdoor(d) return d.outdoor end;function Map.defIsWaterCell() return false end;function Map.defPassable(d,ts,x,y) return x>=0 and y>=0 and x<d.width and y<d.height end;Map.defIsWalkableCell=Map.defPassable;package.preload['src.world.Map']=function() return Map end
local player={cellX=2,cellY=2,px=32,py=32,facing='down',surfing=false,draw=function() end}
local function mkmap(id) local m={id=id,widthCells=8,heightCells=8,def=defs[id]};function m:isWaterCell() return false end;return m end
local ow={map=mkmap('A'),player=player,camera={x=0,y=0},playerHidden=false};function ow:partyKnows() return false end;function ow:rememberOutdoor() end;function ow:syncSurfingPikachu() end
local Scene={now={visible='world',indoors=false,outdoor=true,mapId='A',playerPosKnown=true,playerWorldX=32,playerWorldY=32},overworld=function() return ow end}
local direct,public=0,0
function ow:setMap(dest,x,y,face,opts) direct=direct+1;self.map=mkmap(dest);player.cellX,player.cellY,player.px,player.py=x,y,x*16,y*16;player.facing=face;Scene.now.mapId=dest;Scene.now.playerWorldX=x*16;Scene.now.playerWorldY=y*16;return true end
local world={};function world:overworld() return ow end;function world:warpTo(dest,x,y,face,opts) public=public+1;return true end
local saved={tornadoLandings={B={land={x=3,y=3,facing='down'}},A={land={x=2,y=2,facing='down'}}}}
local game={save={visited={A=true}},data={maps=defs,field={outsideTilesets={OVERWORLD=true},tilesets={OVERWORLD={}},flyWarps={}}}}
local mod={game=game,world=world,save={set=function(self,k,v) saved[k]=v end,get=function(self,k,d) local v=saved[k];if v==nil then return d end;return v end},log={info=function() end,warn=function() end}}
local Funnel=assert(loadfile(ROOT..'lib/Funnel.lua'))({});local mode3d=false;local Bridge={presentation3d=function() return mode3d end,active=function() return mode3d end};local Flat={ready=function() return true end,sampleAt=function(x,z,o) o=o or {};o.water=false;o.solid=false;o.groundY=0;return o end};local Wind={direction=function() return 1,0 end}
local V={mod=mod};function V.require(n) local m={Config={get=function() return cfg end},Settings=Settings,WeatherState=WS,Scene=Scene,Funnel=Funnel,VoxelAtmosBridge=Bridge,FlatWorldInteraction=Flat,WindEngine=Wind};if m[n] then return m[n] end error(n) end
love={math={random=function() return 0 end}};local T=assert(loadfile(ROOT..'lib/Tornado.lua'))(V);T._setRandom(function() return 0 end)
local dest=T.destinations('A');ck(#dest==1 and dest[1]=='B','Weather FX remembered outdoor map is eligible even when engine save.visited omits it')
-- 2D relocation: the public warp deliberately lies (returns true, changes nothing). The live setMap path must own the transfer.
for _=1,480 do T.update(.25) end
for _=1,80 do T.update(.1);if ow.map.id=='B' then break end end
ck(ow.map.id=='B' and direct==1,'2D tornado makes the destination map live')
ck(public==0,'2D tornado does not trust a queued/no-op public warp when live synchronous transfer exists')
-- Re-arm on A for strict 3D contact carry.
if Funnel.stop then Funnel.stop() end;T.invalidate();mode3d=true;ow.map=mkmap('A');player.cellX,player.cellY,player.px,player.py=2,2,32,32;Scene.now.mapId='A';Scene.now.playerWorldX=32;Scene.now.playerWorldY=32
direct,public=0,0;T._gale=true;T.nextSpawn=1e9
local r={id=1,x=32,z=32,mapId='A',age=9,roamAge=0,formation=8,roamFor=180,ropeFor=12,stage='roam',ropeAge=0,seeker=false,destination=nil,heading=0,speed=0,spin=4.5,waterBlend=0,groundY=0,wander=0,seekAge=0};T.active={r};T.update(.05)
for _=1,70 do T.update(.25);if ow.map.id=='B' then break end end
ck(ow.map.id=='B' and direct==1,'3D tornado makes the destination map live')
ck(public==0,'3D tornado shares the same proven synchronous transfer authority')
print(('tornado real transfer 8.1.61: %d passed, %d failed'):format(p,f));os.exit(f==0 and 0 or 1)
