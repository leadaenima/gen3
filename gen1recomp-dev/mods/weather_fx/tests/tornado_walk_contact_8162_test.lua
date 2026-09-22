local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local p,f=0,0;local function ck(v,m) if v then p=p+1;print('PASS '..m) else f=f+1;print('FAIL '..m) end end
local cfg={tornado={enabled=true,everySeconds=99999,maxActive=3,formationSeconds=8,roamSeconds=180,ropeSeconds=12,carryChance=.10,touchRadius=14,waterTwister=true,funnel=true,funnelSeconds=2.5,sandstorms=false}}
local Settings={is=function(k,v) return k=='tornado' and v=='on' end,tornadoPickupChance=function() return .10 end,weatherDisabled=function() return false end}
local WS={level=1,current=function() return {id='GALE'} end}
local defs={
  ROUTE_1={id='ROUTE_1',outdoor=true,tileset='OVERWORLD',width=10,height=10,connections={right={map='PALLET',offset=0}},warps={}},
  PALLET={id='PALLET',outdoor=true,tileset='OVERWORLD',width=10,height=10,connections={left={map='ROUTE_1',offset=0}},warps={}},
}
local function liveMap(id)
  local m={id=id,widthCells=20,heightCells=20,def=defs[id]};function m:isWaterCell() return false end;return m
end
local player={cellX=1,cellY=4,px=16,py=64,facing='right',surfing=false}
local ow={map=liveMap('ROUTE_1'),player=player,camera={x=0,y=0}};function ow:partyKnows() return false end
local Scene={now={visible='world',indoors=false,outdoor=true,mapId='ROUTE_1',playerPosKnown=true,playerWorldX=16,playerWorldY=64},overworld=function() return ow end}
local game={save={visited={ROUTE_1=true,PALLET=true}},data={maps=defs,field={outsideTilesets={OVERWORLD=true},tilesets={OVERWORLD={}},flyWarps={}}}}
local Map={};function Map.isOutside(d) return d.outdoor end;function Map.isOutdoor(d) return d.outdoor end;function Map.defIsWaterCell() return false end;function Map.defPassable(d,ts,x,y) return x>=0 and y>=0 and x<d.width and y<d.height end;Map.defIsWalkableCell=Map.defPassable;package.preload['src.world.Map']=function() return Map end
local Flat={ready=function() return true end,sampleAt=function(x,z,o) o=o or {};o.water=false;o.solid=false;o.groundY=0;return o end}
local Bridge={presentation3d=function() return true end,active=function() return true end};local Wind={direction=function() return 1,0 end};local Funnel={active=false,update=function() end,stop=function() end}
local save,warps={},0
function ow:setMap(dest,x,y,face)
  warps=warps+1;ow.map=liveMap(dest);player.cellX,player.cellY=x,y;player.px,player.py=x*16,y*16;player.facing=face or 'down';Scene.now.mapId=dest;Scene.now.playerWorldX,Scene.now.playerWorldY=player.px,player.py;return true
end
local world={overworld=function() return ow end,warpTo=function() error('public warp must not be needed') end}
local mod={game=game,world=world,save={set=function(self,k,v) save[k]=v end,get=function(self,k,d) local v=save[k];if v==nil then return d end;return v end},log={info=function() end,warn=function() end}}
local V={mod=mod};function V.require(n) local m={Config={get=function() return cfg end},Settings=Settings,Scene=Scene,Funnel=Funnel,WeatherState=WS,VoxelAtmosBridge=Bridge,FlatWorldInteraction=Flat,WindEngine=Wind};if m[n] then return m[n] end error(n) end
love={math={random=function() return .25 end}}
local T=assert(loadfile(ROOT..'lib/Tornado.lua'))(V);T._setRandom(function() return .25 end)

-- Seed a valid different destination. The direct-contact path must choose it even
-- though the funnel is an ordinary roamer rather than a 10% seeker.
local landing=T.landingFor('PALLET');ck(landing~=nil,'different visited outdoor destination is escape-safe')

-- Deliberately stale voxel render snapshot: old 8.1.61 playerInfo preferred this
-- and could therefore miss the real gameplay player walking into the funnel.
local stalePlayer={px=304,py=304,cellX=19,cellY=19,facing='left'}
T.observeVoxelState({map=ow.map,neighbors={},player=stalePlayer})
T._gale=true;T.nextSpawn=1e9
local r={id=1,x=80,z=64,mapId='ROUTE_1',age=9,roamAge=0,formation=8,roamFor=180,ropeFor=12,stage='roam',ropeAge=0,seeker=false,destination=nil,heading=0,speed=0,spin=4.5,waterBlend=0,groundY=0,wander=0,seekAge=0}
T.active={r}

-- Player starts outside the visible contact envelope.
player.px,player.py=16,88;player.cellX,player.cellY=1,5;Scene.now.playerWorldX,Scene.now.playerWorldY=16,88
T.update(.05);ck(r.stage=='roam','approach starts outside tornado contact')

-- Move into the rendered ground circulation: centre separation ~=28.8px. The
-- old 14px anchor-point core misses this even though the player's body overlaps
-- the ~21px debris skirt. The repaired contact geometry must start pickup.
player.px,player.py=64,88;player.cellX,player.cellY=4,5;Scene.now.playerWorldX,Scene.now.playerWorldY=64,88
T.update(.05)
ck(r.stage=='pickup' and r.contactCarry==true,'walking into visible 3D tornado footprint starts pickup')
ck(r.destination=='PALLET','ordinary contact chooses a different safe visited map')

-- Complete the real carry state machine and require a live map change.
local seen={[r.stage]=true}
for _=1,90 do T.update(.25);seen[r.stage]=true;if r.stage=='rope' then break end end
ck(seen.depart and seen.transfer and seen.arrival and seen.landing,'walk-in contact traverses full carry choreography')
ck(warps==1 and ow.map.id=='PALLET','walk-in contact actually relocates player to different live map')

-- Swept contact: neither endpoint is inside 30px, but the player crosses right
-- through the tornado between updates. This protects fast/free-move camera modes.
T.invalidate();ow.map=liveMap('ROUTE_1');Scene.now.mapId='ROUTE_1';player.px,player.py=16,64;player.cellX,player.cellY=1,4;Scene.now.playerWorldX,Scene.now.playerWorldY=16,64
T.observeVoxelState({map=ow.map,neighbors={},player=stalePlayer});T._gale=true;T.nextSpawn=1e9
local s={id=2,x=80,z=64,mapId='ROUTE_1',age=9,roamAge=0,formation=8,roamFor=180,ropeFor=12,stage='roam',ropeAge=0,seeker=false,destination=nil,heading=0,speed=0,spin=4.5,waterBlend=0,groundY=0,wander=0,seekAge=0};T.active={s}
T.update(.05);player.px,player.py=144,64;player.cellX,player.cellY=9,4;Scene.now.playerWorldX,Scene.now.playerWorldY=144,64;T.update(.05)
ck(s.stage=='pickup' and s.contactCarry==true,'swept player motion cannot tunnel through tornado contact')

-- A render snapshot on the wrong location must never override the live player.
ck(stalePlayer.px==304 and player.px==144,'test kept voxel snapshot stale while live player moved')

print(('tornado walk contact 8.1.62: %d passed, %d failed'):format(p,f));os.exit(f==0 and 0 or 1)
