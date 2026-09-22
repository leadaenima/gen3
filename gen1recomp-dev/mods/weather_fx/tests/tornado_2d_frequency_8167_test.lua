local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local p,f=0,0;local function ck(v,m) if v then p=p+1;print('PASS '..m) else f=f+1;print('FAIL '..m) end end
local cfg={tornado={enabled=true,everySeconds=90,minVisited=1,carryChance=.10,funnel=true,funnelSeconds=2.5,waterTwister=true,sandstorms=false}}
local Settings={is=function(k,v)return k=='tornado'and v=='on'end,tornadoPickupChance=function()return .10 end,weatherDisabled=function()return false end}
local WS={level=1,current=function()return{id='GALE'}end}
local defs={A={id='A',outdoor=true,tileset='OVERWORLD',width=8,height=8,connections={right={map='B',offset=0}},warps={}},B={id='B',outdoor=true,tileset='OVERWORLD',width=8,height=8,connections={left={map='A',offset=0}},warps={}}}
local Map={};function Map.isOutside(d)return d.outdoor end;function Map.isOutdoor(d)return d.outdoor end;function Map.defIsWaterCell()return false end;function Map.defPassable(d,ts,x,y)return x>=0 and y>=0 and x<d.width and y<d.height end;Map.defIsWalkableCell=Map.defPassable;package.preload['src.world.Map']=function()return Map end
local player={cellX=2,cellY=2,px=32,py=32,facing='down',surfing=false,draw=function()end};local ow={map={id='A',isWaterCell=function()return false end},player=player,camera={x=0,y=0}};function ow:partyKnows()return false end
local Scene={now={visible='world',indoors=false,outdoor=true,mapId='A',playerPosKnown=true,playerWorldX=32,playerWorldY=32},overworld=function()return ow end}
local game={save={visited={A=true,B=true}},data={maps=defs,field={outsideTilesets={OVERWORLD=true},tilesets={OVERWORLD={}},flyWarps={}}}}
local mod={game=game,world={warpTo=function()return true end},save={set=function()end,get=function(self,k,d)return d end},log={info=function()end,warn=function()end}}
local Funnel=assert(loadfile(ROOT..'lib/Funnel.lua'))({});local Bridge={presentation3d=function()return false end,active=function()return false end};local Flat={ready=function()return true end,sampleAt=function(x,z,o)o=o or{};o.water=false;o.solid=false;o.groundY=0;return o end}
local V={mod=mod};function V.require(n)local m={Config={get=function()return cfg end},Settings=Settings,WeatherState=WS,Scene=Scene,Funnel=Funnel,VoxelAtmosBridge=Bridge,FlatWorldInteraction=Flat};if m[n]then return m[n]end error(n)end
love={math={random=function()return 0 end}};local T=assert(loadfile(ROOT..'lib/Tornado.lua'))(V);T._setRandom(function()return 0 end)
for _=1,359 do T.update(.25) end
ck(not Funnel.active and not T.isCarrying(),'normal 2D Gale has no tornado before 90 seconds')
T.update(.25)
ck(Funnel.active and T.isCarrying(),'normal 2D Gale performs its first 10% relocation roll at exactly 90 seconds')
ck(T.describe():find('2d gale relocation tornado',1,true)~=nil,'2D tornado becomes visible relocation event after successful roll')
T.invalidate();Funnel.stop();cfg.tornado.everySeconds=30;T._setRandom(function()return 0 end)
for _=1,119 do T.update(.25) end
ck(not Funnel.active,'EXTREME-style 30-second cadence does not fire early')
T.update(.25)
ck(Funnel.active,'higher tornado frequency shortens 2D Gale opportunity spacing')
print(('2D tornado frequency 8.1.67: %d passed, %d failed'):format(p,f));os.exit(f==0 and 0 or 1)
