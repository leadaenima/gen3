local ROOT=(arg and arg[0] or ''):match('^(.*)tools[/\\][^/\\]*$') or './'
local fronts={
 {id=511,weather='STORM',cloudWeather='STORM',x=1200,z=0,bankX=480,bankZ=0,rx=1000,rz=2400,radius=1000,sizeClass='synoptic',vx=-1.2,vz=.1,shaft=.90,kind='rain',flash=0},
 {id=512,weather='STORM',cloudWeather='STORM',x=1150,z=700,bankX=520,bankZ=360,rx=900,rz=2100,radius=900,sizeClass='synoptic',vx=-.9,vz=-.2,shaft=.86,kind='rain',flash=0},
}
love={graphics={getDimensions=function() return 1920,1080 end}}
local Settings={cloudsOn=function() return true end,get=function() return 'on' end,cloudHeightScale=function() return 1.5 end}
local WeatherSetting={new=function() return {get=function() return 'full' end} end}
local ForestAtmos={time=211.75,RAMP={day={fog={.8,.8,.8},ray={1,1,1}}}}
local DistantWeather={items=function() return fronts,#fronts end}
local WeatherWorldSpace={toLocal=function(x,z) return x,z end}
local generic={}
local V={mod={id='weather_fx',options={get=function() return nil end}},weatherFxId='CLEAR',weatherFxChannels={}}
function V.require(n)
 if n=='Settings' then return Settings elseif n=='WeatherSetting' then return WeatherSetting elseif n=='ForestAtmos' then return ForestAtmos end
 if n=='DistantWeather' then return DistantWeather elseif n=='WeatherWorldSpace' then return WeatherWorldSpace end
 if n=='Quality' then return {budget=function() return {worldPrecip=1} end} elseif n=='Scene' then return {now={visible='world',outdoor=true}} end
 if n=='MesoscaleField' then return {ready=function() return false end} elseif n=='PerformanceGovernor' then return {scale=function() return 1 end} end
 return generic
end
V.safeCall=pcall
local Ccpu=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V)
local Cgpu=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V)
local vox={eye={0,12,0},focus={0,40,200},player={0,0,0},far=1800,size=function() return 1920,1080 end}
local frame={level=1,canopy=false,weather={coverage=0,cloudShade=1.02},rayColor={1,.96,.9}}
local map={id='BENCH'}
-- warm both paths before timing
for _=1,4 do Ccpu._buildDistantWeather(vox,frame,map,false);Cgpu._buildDistantWeather(vox,frame,map,true) end
local loops=80
collectgarbage('collect');local t0=os.clock();local ncpu=0
for _=1,loops do local _,_,n=Ccpu._buildDistantWeather(vox,frame,map,false);ncpu=n end
local tcpu=os.clock()-t0
collectgarbage('collect');local t1=os.clock();local nskip=0
for _=1,loops do local _,_,n=Cgpu._buildDistantWeather(vox,frame,map,true);nskip=n end
local tskip=os.clock()-t1
local ratio=(tskip>0) and tcpu/tskip or 0
print(string.format('front_precip_cpu_builder rows=%d loops=%d seconds=%.6f',ncpu,loops,tcpu))
print(string.format('front_precip_instanced_cpu_prep rows=%d loops=%d seconds=%.6f',nskip,loops,tskip))
print(string.format('front_precip_cpu_prep_speedup=%.3fx reduction=%.2f%%',ratio,(tcpu>0) and (1-tskip/tcpu)*100 or 0))
print('old_per_frame_hashes=36000 old_per_frame_vertex_rows=36000 old_per_frame_index_values=54000 old_vertex_float_bytes=1008000')
if ncpu<36000 or nskip~=0 or tskip>=tcpu then os.exit(1) end
