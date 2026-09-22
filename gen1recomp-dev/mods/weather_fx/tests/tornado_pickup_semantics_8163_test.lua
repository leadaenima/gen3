local ROOT=(arg and arg[1]) or '.'
if ROOT:sub(-1)~='/' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,m) if v then pass=pass+1;print('PASS '..m) else fail=fail+1;print('FAIL '..m) end end
local mode3d=false
local cfg={tornado={enabled=true,everySeconds=120,maxActive=3,formationSeconds=2,roamSeconds=180,ropeSeconds=3,carryChance=.10,touchRadius=14,waterTwister=true,funnel=true,funnelSeconds=1.0,sandstorms=false,spawnDistanceMin=80,spawnDistanceMax=80}}
local Settings={is=function(k,v) return k=='tornado' and v=='on' end,tornadoPickupChance=function() return .10 end,weatherDisabled=function() return false end}
local WS={level=1,current=function() return {id='GALE'} end}
local defs={
 A={id='A',outdoor=true,tileset='OVERWORLD',width=20,height=20,connections={right={map='B',offset=0}},warps={}},
 B={id='B',outdoor=true,tileset='OVERWORLD',width=20,height=20,connections={left={map='A',offset=0}},warps={}},
}
local Map={};function Map.isOutside(d) return d.outdoor end;function Map.isOutdoor(d) return d.outdoor end;function Map.defIsWaterCell() return false end
function Map.defPassable(d,ts,x,y) return x>=0 and y>=0 and x<d.width and y<d.height end;Map.defIsWalkableCell=Map.defPassable
package.preload['src.world.Map']=function() return Map end
local player={cellX=5,cellY=5,px=80,py=80,facing='down',surfing=false,inputLocked=false,draw=function() end}
local map={id='A',isWaterCell=function() return false end}
local ow={map=map,player=player,camera={x=0,y=0},playerHidden=false};function ow:partyKnows() return false end
local Scene={now={visible='world',indoors=false,outdoor=true,mapId='A',playerPosKnown=true,playerWorldX=80,playerWorldY=80},overworld=function() return ow end}
local game={save={visited={A=true,B=true}},data={maps=defs,field={outsideTilesets={OVERWORLD=true},tilesets={OVERWORLD={}},flyWarps={}}}}
local save={}
local world={};function world:warpTo() return false,'fallback disabled' end
function ow:setMap(dest,x,y,face,opts)
 map={id=dest,isWaterCell=function() return false end};ow.map=map
 -- Simulate Gen1 setMap rebuilding transition state and clearing a previous host lock.
 player.inputLocked=false
 player.cellX,player.cellY,player.px,player.py=x,y,x*16,y*16
 Scene.now.mapId=dest;Scene.now.playerWorldX=player.px;Scene.now.playerWorldY=player.py
end
local wrappedCollision
local mod={game=game,world=world,save={set=function(self,k,v) save[k]=v end,get=function(self,k,d) local v=save[k];if v==nil then return d end;return v end},log={info=function() end,warn=function() end},hooks={wrap=function(self,name,fn) if name=='movement.collision' then wrappedCollision=fn end end}}
local Funnel=assert(loadfile(ROOT..'lib/Funnel.lua'))({})
local Bridge={presentation3d=function() return mode3d end,active=function() return mode3d end}
local solidSeekerCorridor=false
local Flat={ready=function() return true end,sampleAt=function(x,z,o) o=o or {};o.water=false;o.solid=solidSeekerCorridor and true or false;o.groundY=0;return o end}
local Wind={direction=function() return 1,0 end}
local V={mod=mod};function V.require(n) local m={Config={get=function() return cfg end},Settings=Settings,WeatherState=WS,Scene=Scene,Funnel=Funnel,VoxelAtmosBridge=Bridge,FlatWorldInteraction=Flat,WindEngine=Wind};if m[n] then return m[n] end error(n) end
love={math={random=function() return 0 end}}
local T=assert(loadfile(ROOT..'lib/Tornado.lua'))(V);T.installHooks()
local function source() ow:setMap('A',5,5,'down');player.inputLocked=false;T.invalidate();player.inputLocked=false end

-- 2D semantics: screen event only, controls lock before sweep, transfer, unlock after drop.
source();mode3d=false;T._setRandom(function() return 0 end)
for i=1,490 do T.update(.25);if T._legacyCarry then break end end
ck(#T.active==0,'2D relocation creates no 3D world tornado')
ck(T._legacyCarry~=nil and Funnel.active and Funnel.phaseName()=='approach','2D successful carry roll starts screen sweep')
ck(player.inputLocked==true,'2D sweep asserts native player input lock immediately')
local beforeX,beforeY=player.px,player.py
-- Simulated attempted movement while lock is active must be rejectable by both native flag and collision safety net.
local ctx={mover=player,reason='tile'};local allowed=wrappedCollision and wrappedCollision(function(a)return a end,true,ctx)
ck(player.inputLocked==true and allowed==false,'2D sweep blocks both native/free-move and grid movement paths')
for i=1,150 do T.update(.1);if Scene.now.mapId=='B' then break end end
ck(Scene.now.mapId=='B','2D sweep performs real different-map transfer')
ck(player.inputLocked==true,'2D lock is reasserted after live map replacement')
for i=1,160 do T.update(.1);if not T.isCarrying() then break end end
ck(not T.isCarrying() and player.inputLocked==false,'2D sweep releases controls only after destination drop/exit')

-- 3D walk-in contact.
source();mode3d=true;T._gale=true;T.nextSpawn=1e9
local r={id=11,x=80,z=45,mapId='A',age=3,roamAge=0,formation=2,roamFor=180,ropeFor=3,stage='roam',ropeAge=0,seeker=false,destination=nil,heading=0,speed=0,spin=4.5,waterBlend=0,groundY=0,wander=0,seekAge=0};T.active={r}
T.update(.05);player.py=60;Scene.now.playerWorldY=60;T.update(.05)
ck(r.stage=='pickup' and r.contactCarry==true,'3D walk-in contact starts pickup')
ck(player.inputLocked==true,'3D walk-in pickup asserts native player input lock')
local p0=T.presentationPose();T.update(.6);local p1=T.presentationPose()
ck(p0 and p1 and p1.lift>p0.lift,'3D walk-in pickup visibly lifts the player')
for i=1,160 do T.update(.25);if Scene.now.mapId=='B' then break end end
ck(Scene.now.mapId=='B' and player.inputLocked==true,'3D walk-in transfer reaches different map while controls remain locked')
for i=1,160 do T.update(.25);if not T.isCarrying() then break end end
ck(not T.isCarrying() and player.inputLocked==false,'3D walk-in releases controls only after landing')

-- 3D seek: force only the 10% roll to be inside normal chance, then allow natural seeker motion.
-- The whole approach corridor is reported as static solid scenery. Ordinary
-- roamers still deflect from it; a committed seeker must not be permanently
-- repelled/orbit the player as 8.1.62 did in the real Route 1 run.
source();mode3d=true;solidSeekerCorridor=true
local seq={0,0,0.05,0,0,0,0,0,0};local si=0;T._setRandom(function() si=si+1;return seq[si] or 0 end)
local s=T.spawn(false)
ck(s and s.seeker==true and s.destination=='B','3D normal 10% roll creates seeker; 2D logic is not involved')
local d0=math.sqrt((s.x-player.px)^2+(s.z-player.py)^2);local dmin=d0
for i=1,1200 do T.update(.05);local d=math.sqrt((s.x-player.px)^2+(s.z-player.py)^2);if d<dmin then dmin=d end;if T.isCarrying() then break end end
ck((s.seekSceneryCrossings or 0)>0,'3D seeker actually traversed solid scenery samples during qualification')
ck(dmin<d0-30,'3D seeker travels toward player under its own movement despite solid scenery')
ck(T.isCarrying() and s.stage=='pickup','3D seeker reaches player and starts pickup without player approach')
ck(player.inputLocked==true,'3D seeker pickup asserts native player input lock')
local q0=T.presentationPose();T.update(.6);local q1=T.presentationPose();ck(q0 and q1 and q1.lift>q0.lift,'3D seeker visibly lifts the player')
for i=1,160 do T.update(.25);if Scene.now.mapId=='B' then break end end
ck(Scene.now.mapId=='B' and player.inputLocked==true,'3D seeker carries player to different live map')
for i=1,160 do T.update(.25);if not T.isCarrying() then break end end
ck(not T.isCarrying() and player.inputLocked==false,'3D seeker releases controls after landing')
solidSeekerCorridor=false

print(('tornado pickup semantics: %d passed, %d failed'):format(pass,fail));os.exit(fail==0 and 0 or 1)
