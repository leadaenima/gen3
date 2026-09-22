local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end end
local function read(p) local f=assert(io.open(p,'r')); local s=f:read('*a'); f:close(); return s end
local T=assert(loadfile('lib/Types.lua'))({})
check(T.byId.RAVE==nil,'RAVE weather definition is absent')
for _,id in ipairs(T.PINNED or {}) do check(id~='RAVE','RAVE is absent from pinned weather selector') end
local S=read('lib/Settings.lua')
check(S:find('raveMusic',1,true)==nil and S:find('raveStrobe',1,true)==nil,'RAVE settings/helpers are absent')
check(not io.open('lib/RaveMusic.lua','r'),'RaveMusic runtime module is absent')
local A=read('lib/Audio.lua')
check(A:find('RaveMusic',1,true)==nil and A:find('raveOwnsMusic',1,true)==nil,'audio has no RAVE ownership path')
local C=read('lib/voxel_atmos/CinematicAtmos.lua')
check(C:find('raveAmount',1,true)==nil and C:find('_drawRave',1,true)==nil and C:find('weatherFxRave',1,true)==nil,'3D atmosphere has no RAVE render path')
local D=read('lib/DramalessAtmos.lua')
check(D:find('weatherFxRave',1,true)==nil and D:find('raveShowWanted',1,true)==nil,'3D host bridge has no RAVE carry/show path')
local B=read('lib/BattleDraw.lua')
check(B:find('raveCarry',1,true)==nil and B:find('RAVE lasers',1,true)==nil,'battle renderer has no RAVE carryover')
local M=read('main.lua')
check(M:find('raveOwnsMusic',1,true)==nil,'main no longer ducks game music for RAVE')
local f=io.open('assets/sounds/rave/rave_pixel_rush.ogg','rb')
check(f==nil,'bundled RAVE soundtrack directory is removed'); if f then f:close() end
print(('rave removal 8.2.14: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
