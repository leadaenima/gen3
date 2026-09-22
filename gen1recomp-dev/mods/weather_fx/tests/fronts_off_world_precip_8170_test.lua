-- Weather FX 8.1.70: WEATHER FRONTS OFF must keep snow/hail world-scale,
-- and procedural snow/hail must use their own wind channels.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1; print('PASS '..n) else fail=fail+1; print('FAIL '..n) end end
local src=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb')):read('*a')
ck(src:find('function WP%._frontsEnabled%(')~=nil,'WorldPrecip exposes a dedicated fronts-enabled resolver')
ck(src:find('desiredSnowR = max(SNOW_MIN_R, lastFar * weatherDistanceScale)',1,true)~=nil,'snow radius is derived from rendered-world reach (including fronts OFF)')
ck(src:find('desiredRainR = max(4, lastFar * weatherDistanceScale)',1,true)~=nil,'rain/hail radius is derived from rendered-world reach when fronts are OFF')
ck(src:find('STREAM_RADIUS = frontsOn and min(radiusCap, desiredRainR) or max(4, desiredRainR)',1,true)~=nil,'fronts ON keeps quality budget while fronts OFF uses the player-capped whole-world rain/hail radius')
ck(src:find('grain%.simRadius%[kind%]=%(kind==3%) and STREAM_RADIUS or desiredRainR')~=nil,'hail and ash CPU fallback radius follows whole-world rain radius')
ck(src:find('PS%.draw.-wind=%{snow%.lastWindX or 0,snow%.lastWindZ or 0%}')~=nil,'procedural snow draw uses snow wind rather than grain wind')
ck(src:find('PS%.probe.-wind=%{snow%.lastWindX or 0,snow%.lastWindZ or 0%}')~=nil,'procedural snow probe uses snow wind rather than grain wind')
ck(src:find('PP%.draw.-wind=%{grain%.lastWindX or 0,grain%.lastWindZ or 0%}')~=nil,'procedural hail/sand/ash draw uses grain wind rather than snow wind')
ck(src:find('PP%.probe.-wind=%{grain%.lastWindX or 0,grain%.lastWindZ or 0%}')~=nil,'procedural hail probe uses grain wind rather than snow wind')
print(('fronts-off world precip 8.1.70: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
