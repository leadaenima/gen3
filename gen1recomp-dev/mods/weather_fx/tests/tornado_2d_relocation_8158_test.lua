local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local p,f=0,0;local function ck(v,m) if v then p=p+1;print('PASS '..m) else f=f+1;print('FAIL '..m) end end
local cfg={tornado={enabled=true,everySeconds=120,minVisited=4,carryChance=1,funnel=true,funnelSeconds=2.5,waterTwister=true,sandstorms=false}}
local Settings={is=function(k,v) return k=='tornado' and v=='on' end,tornadoPickupChance=function() return 1 end,weatherDisabled=function() return false end};local WS={level=1,current=function() return {id='GALE'} end}
local defs={A={id='A',outdoor=true,tileset='OVERWORLD',width=8,height=8,connections={right={map='B',offset=0}},warps={}},B={id='B',outdoor=true,tileset='OVERWORLD',width=8,height=8,connections={left={map='A',offset=0}},warps={}}}
local Map={};function Map.isOutside(d) return d.outdoor end;function Map.isOutdoor(d) return d.outdoor end;function Map.defIsWaterCell() return false end;function Map.defPassable(d,ts,x,y) return x>=0 and y>=0 and x<d.width and y<d.height end;Map.defIsWalkableCell=Map.defPassable;package.preload['src.world.Map']=function() return Map end
local player={cellX=2,cellY=2,px=32,py=32,facing='down',surfing=false,draw=function() end};local map={id='A',isWaterCell=function() return false end};local ow={map=map,player=player,camera={x=7,y=9},playerHidden=false};function ow:partyKnows() return false end
local Scene={now={visible='world',indoors=false,outdoor=true,mapId='A',playerPosKnown=true,playerWorldX=32,playerWorldY=32},overworld=function() return ow end}
local game={save={visited={A=true,B=true}},data={maps=defs,field={outsideTilesets={OVERWORLD=true},tilesets={OVERWORLD={}},flyWarps={}}}}
local pending=nil;local warps=0;local world={};function world:warpTo(dest,x,y,face,opts) warps=warps+1;pending={dest=dest,x=x,y=y,opts=opts};return true end
local save={};local mod={game=game,world=world,save={set=function(self,k,v) save[k]=v end,get=function(self,k,d) local v=save[k];if v==nil then return d end;return v end},log={info=function() end,warn=function() end}}
local Funnel=assert(loadfile(ROOT..'lib/Funnel.lua'))({});local Bridge={presentation3d=function() return false end,active=function() return false end};local Flat={ready=function() return true end,sampleAt=function(x,z,o) o=o or {};o.water=false;o.solid=false;o.groundY=0;return o end}
local V={mod=mod};function V.require(n) local m={Config={get=function() return cfg end},Settings=Settings,WeatherState=WS,Scene=Scene,Funnel=Funnel,VoxelAtmosBridge=Bridge,FlatWorldInteraction=Flat};if m[n] then return m[n] end error(n) end
love={math={random=function() return 0 end}};local T=assert(loadfile(ROOT..'lib/Tornado.lua'))(V);T._setRandom(function() return 0 end)
for _=1,480 do T.update(.25) end
ck(T.isCarrying() and Funnel.active and Funnel.phaseName()=='approach','2D GALE starts relocation with only one other safe visited map despite legacy minVisited=4')
local camx,camy=ow.camera.x,ow.camera.y
for _=1,30 do ow.camera.x,ow.camera.y=99,101;T.update(.1);if Funnel.phaseName()=='blackout' then break end end
ck(Funnel.phaseName()=='blackout' and warps==1 and pending and pending.dest=='B','player sweep reaches blackout and starts real destination warp')
ck(ow.playerHidden==true,'normal player sprite is hidden while tornado carries replay copy off-screen')
ck(ow.camera.x==camx and ow.camera.y==camy,'source camera remains locked throughout sweep-off')
for _=1,10 do T.update(.1) end;ck(Funnel.phaseName()=='blackout','blackout does not reveal source map while destination is pending')
-- Complete the actual host transition.
Scene.now.mapId='B';ow.map={id='B',isWaterCell=function() return false end};player.cellX,player.cellY=pending.x,pending.y;Scene.now.playerWorldX=pending.x*16;Scene.now.playerWorldY=pending.y*16
if pending.opts and pending.opts.onDone then pending.opts.onDone() end
for _=1,80 do T.update(.1);if not Funnel.active then break end end
ck(not T.isCarrying() and not Funnel.active,'2D relocation completes after destination becomes live')
ck(ow.playerHidden==false,'real player is restored before tornado leaves right')
ck(Scene.now.mapId=='B' and save.tornadoFrom=='A','2D tornado changes actual map and preserves source return record')
print(('2D relocation runtime 8.1.58: %d passed, %d failed'):format(p,f));os.exit(f==0 and 0 or 1)
