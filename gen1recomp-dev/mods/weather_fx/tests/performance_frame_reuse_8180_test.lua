-- Weather FX 8.1.80 exact-visual frame-spatial/runtime reuse regression.
local ROOT=(arg and arg[1]) or ((arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './')
if ROOT~='' and ROOT:sub(-1)~='/' and ROOT:sub(-1)~='\\' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function read(p) local f=assert(io.open(ROOT..p,'rb'));local s=f:read('*a');f:close();return s end

local manifest=read('manifest.json')
local ca=read('lib/voxel_atmos/CinematicAtmos.lua')
local wp=read('lib/voxel_atmos/WorldPrecip.lua')

local vmaj,vmin,vpatch=manifest:match('"version"%s*:%s*"(%d+)%.(%d+)%.(%d+)"')
ck(tonumber(vmaj)==8 and tonumber(vmin)==1 and (tonumber(vpatch) or 0)>=80,'manifest preserves 8.1.80+ frame-reuse baseline')
ck(ca:find('function CinematicAtmos._refreshSpatialFrame(Voxel3D)',1,true)~=nil,'3D atmosphere owns one frame-spatial refresh')
ck(ca:find('CinematicAtmos._refreshSpatialFrame(Voxel3D)',1,true)~=nil,'draw refreshes spatial state once before atmosphere passes')
ck(ca:find('st and st.owner==Voxel3D and st.billboardValid',1,true)~=nil,'billboard basis reuses frame-spatial cache')
ck(ca:find('st and st.owner==Voxel3D and st.horizontalValid',1,true)~=nil,'horizontal camera basis reuses frame-spatial cache')
ck(ca:find('st and st.owner==Voxel3D and st.aspect',1,true)~=nil,'viewport aspect reuses frame-spatial cache')
ck(ca:find('st and st.owner==Voxel3D and st.fieldValid',1,true)~=nil,'weather-field basis reuses frame-spatial cache')
ck(ca:find('st and st.owner==Voxel3D and st.anchorValid and st.anchor',1,true)~=nil,'weather-cell traversal reuses frame anchor')
ck(ca:find('local focusX,focusZ=',1,true)~=nil and not ca:find('local focus = { rawFocus[1] - cloudShiftX',1,true),'weather-cell traversal removes transient focus table')

ck(ca:find('function CinematicAtmos._applySequentialQuadMap',1,true)~=nil,'stream meshes cache sequential quad vertex maps')
for _,key in ipairs({'mist','roll','particles','rain','rays','distant-weather'}) do
  ck(ca:find('CinematicAtmos._applySequentialQuadMap("'..key..'"',1,true)~=nil,'cached sequential map used by '..key)
end
ck(ca:find('rec and rec.mesh==mesh and rec.count==n',1,true)~=nil,'vertex-map cache invalidates on mesh identity or index-count change')

ck(ca:find('CinematicAtmos._uniformScratch = CinematicAtmos._uniformScratch or',1,true)~=nil,'atmosphere owns reusable shader-uniform scratch')
ck(ca:find('function CinematicAtmos._curveUniform(Voxel3D)',1,true)~=nil,'curve uniform reuses persistent vector')
ck(not ca:find('"curve", { Voxel3D.curveX or 0',1,true) and not ca:find('"curve",{Voxel3D.curveX or 0',1,true),'hot atmosphere passes no longer allocate curve vectors')
ck(ca:find('CinematicAtmos._defaultMistWind',1,true)~=nil and ca:find('CinematicAtmos._zero2',1,true)~=nil,'default mist vectors are persistent')
ck(ca:find('particleCool={0,0,0}',1,true)~=nil and ca:find('rainColor={0,0,0}',1,true)~=nil,'particle/rain color uniforms use persistent vectors')
ck(ca:find('identity4={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}',1,true)~=nil,'ray fallback identity matrix is persistent')

-- Zero-quality-loss release invariants.
ck(wp:find('local RAIN_MAX = 12000',1,true)~=nil,'rain 12,000 cap preserved')
ck(wp:find('local HAIL_MAX = 45000',1,true)~=nil,'hail 45,000 cap preserved')
ck(wp:find('local SNOW_MAX = 100000',1,true)~=nil,'snow 100,000 base cap preserved')
ck(ca:find('local function eachWeatherCell',1,true)~=nil,'weather-cell geometry algorithm remains present')
ck(ca:find('abs(side) <= sideSpan and abs(depth) <= depthSpan',1,true)~=nil,'landscape frustum cell filter remains exact')
ck(ca:find('local okUpload = V.safeCall(mesh.setVertices, mesh, verts, 1, need)',1,true)~=nil,'stream meshes still upload exact current vertex rows')

print(('performance frame reuse 8.1.80: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
