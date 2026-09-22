local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end end
local mode='off'
local configDebug=false
local Config={get=function() return {debug=configDebug,debugRain=false} end}
local Settings={debugHudMode=function(config) if config and config.get().debug then return 'full' end return mode end,debugRain=function() return false end,presentMode=function() return 'auto' end}
local State={id='STORM',level=1,pinnedBy='auto',describe=function() return 'AUTO Storm 42s' end}
local Scene={now={mapId='ROUTE_1',outdoor=true,indoors=false}}
local TOD={tod='NITE'}
local Quality={describe=function() return 'AUTO/HIGH 60.0fps' end}
local Bridge={active=function() return true end,handlesPrecipitation=function() return true end,handlesSnow=function() return false end,handlesFog=function() return true end,reason=function() return 'full-atmos:TEST' end}
local Battle={describe=function() return 'RAINY' end}
local Particles={counts=function() return 10,20,3,4 end}
local Audio={describe=function() return 'rain.ogg50%' end}
local Fronts={describe=function() return 'KANTO RAIN' end}
local Seasons={describe=function() return 'SUMMER' end}
local BuildingLight={debugInfo=function() return {dist=8,factor=.3,starMul=.55} end}
local mods={Settings=Settings,Config=Config,WeatherState=State,Scene=Scene,TimeOfDay=TOD,Quality=Quality,VoxelAtmosBridge=Bridge,Battle=Battle,Particles=Particles,Audio=Audio,Fronts=Fronts,Seasons=Seasons,BuildingLight=BuildingLight}
local V={require=function(name) if mods[name] then return mods[name] end error(name) end}
local HUD=assert(loadfile('lib/DebugHUD.lua'))(V)
local lines
lines=HUD.lines(); check(#lines==0,'DEBUG HUD OFF produces no overlay lines')
mode='simple'; lines=HUD.lines()
check(#lines==4,'SIMPLE HUD stays compact')
check(table.concat(lines,' | '):find('wx:STORM',1,true)~=nil,'SIMPLE shows active weather')
check(table.concat(lines,' | '):find('map:ROUTE_1',1,true)~=nil,'SIMPLE shows map id')
check(table.concat(lines,' | '):find('v3:',1,true)~=nil,'SIMPLE shows 3D bridge status')
check(table.concat(lines,' | '):find('why:3d%-owned')~=nil,'SIMPLE explains active render path')
mode='3d'; lines=HUD.lines()
check(#lines==4 and lines[2]:find('precip:yes',1,true)~=nil,'3D HUD reports voxel ownership families')
mode='full'; lines=HUD.lines(); local full=table.concat(lines,' | ')
check(#lines>=9,'FULL HUD adds detailed diagnostics')
check(full:find('btl:RAINY',1,true)~=nil,'FULL shows battle weather status')
check(full:find('2d:r10 s20 g3 sp4',1,true)~=nil,'FULL shows particle counts')
check(full:find('audio:rain.ogg50%%')~=nil,'FULL shows audio state')

-- Draw path actually paints when enabled and stays silent when off.
local prints,rects=0,0
love={graphics={
  print=function() prints=prints+1 end,rectangle=function() rects=rects+1 end,
  setColor=function() end,setBlendMode=function() end,push=function() end,pop=function() end,
  getFont=function() return {getWidth=function(_,s) return #s*6 end,getHeight=function() return 9 end} end,
}}
mode='simple'; check(HUD.draw({gameX=0,gameY=0})==true and prints==4 and rects==1,'enabled HUD renders panel and lines')
mode='off'; prints=0; rects=0; check(HUD.draw({})==false and prints==0 and rects==0,'disabled HUD performs no draw work')
configDebug=true; lines=HUD.lines(); check(#lines>=9,'config.debug still forces FULL HUD for folder installs')
print(('debug HUD: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
