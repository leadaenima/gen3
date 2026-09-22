-- Weather FX 8.2.12: native Gen2Recomped bundled DramaticShapes host detection.
local scriptPath=(arg and arg[0]) or 'tests/gen2_builtin_voxel_host_8212_test.lua'
local ROOT=scriptPath:match('^(.*)[/\\]tests[/\\][^/\\]*$') or '.'
local pass,fail=0,0
local function ck(ok,name) if ok then pass=pass+1 else fail=fail+1; print('FAIL '..name) end end
local dn={time=function() return 0.5 end}
local hostLib={require=function(name) if name=='DayNight' then return dn elseif name=='FirstPerson' then return {engaged=function() return false end} end error('missing '..tostring(name)) end}
local host={exports={lib=hostLib}}
local mod={find=function(first,second) local id=second or first; if id=='Gen2Recomped-DramaticShapes' then return host end end}
local V={mod=mod}
local src=assert(io.open(ROOT..'/lib/Interop.lua','rb')):read('*a')
local Interop=assert((loadstring or load)(src,'@Interop'))(V)
local h,id=Interop.voxel()
ck(h==host and id=='Gen2Recomped-DramaticShapes','Interop selects bundled Gen2Recomped voxel host')
ck(Interop.hostLib()==hostLib,'exports.lib surface is exposed')
local gotDn,gotId=Interop.dayNight()
ck(gotDn==dn and gotId=='Gen2Recomped-DramaticShapes','DayNight resolves through bundled host exports.lib')
local wide,wid=Interop.wideBattle()
ck(wide==true and wid=='Gen2Recomped-DramaticShapes','bundled live-world battle host is wide/3D')
local settings=assert(io.open(ROOT..'/lib/Settings.lua','rb')):read('*a')
ck(settings:find('Gen2Recomped%-DramaticShapes')~=nil,'Settings recognizes bundled host')
local atmos=assert(io.open(ROOT..'/lib/DramalessAtmos.lua','rb')):read('*a')
ck(atmos:find('Gen2Recomped%-DramaticShapes')~=nil,'3D atmosphere host list recognizes bundled host')
print(('gen2 builtin voxel host 8.2.12: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
