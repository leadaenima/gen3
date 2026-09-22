local pass,fail=0,0
local function ok(v,msg)
  if v then pass=pass+1;print('PASS '..msg) else fail=fail+1;print('FAIL '..msg) end
end
local function near(a,b,e) return math.abs((a or 0)-(b or 0))<=(e or 1e-6) end

local loader,err=loadfile('lib/SnowSurfacePaint.lua')
ok(loader~=nil,'SnowSurfacePaint module compiles')
if not loader then print(err);os.exit(1) end
local P=loader({})

local function poolOne(kind,profile,amount,y,x,z,r)
  local p={active=1,x={x or 10},z={z or 10},baseY={y or 0},amount={amount or 0.8},
    size={r or 5},kind={kind or 'ground'},class={kind or 'ground'},profile={profile or 'full'}}
  for k=1,8 do p['r'..k]={r or 5} end
  return p
end

local p=poolOne('tree','round',0.80,24,10,10,5)
local c,y,code=P.coverageAt(10,10,p)
ok(c>0.79 and c<=0.81 and near(y,24),'impact centre carries exact tree support height and coverage')
local outside=P.coverageAt(30,30,p)
ok(outside==0,'identical world geometry outside impact footprint remains unpainted')
local edge=P.coverageAt(13,10,p)
ok(edge>0 and edge<c,'coverage falls continuously across actual impact footprint')

-- Lower snow beneath the same X/Z must never repaint through a higher object.
local overlap={active=2,x={10,10},z={10,10},baseY={0,24},amount={1.0,0.55},size={5,5},
  kind={'ground','tree'},class={'ground','tree'},profile={'full','round'}}
for k=1,8 do overlap['r'..k]={5,5} end
local oc,oy=P.coverageAt(10,10,overlap)
ok(near(oy,24),'higher real support wins over lower snow at same X/Z')
ok(oc>0.54 and oc<0.57,'lower buried patch cannot bleed whitening through tree surface')

-- Melt is not a texture swap: the same surface simply receives less coverage.
local melt=poolOne('raised','full',0.90,12,4,4,4)
local before=P.coverageAt(4,4,melt)
melt.amount[1]=0.22
local after=P.coverageAt(4,4,melt)
ok(before>after and after>0,'decreasing SnowPack depth progressively removes repaint coverage')
melt.amount[1]=0
local gone=P.coverageAt(4,4,melt)
ok(gone==0,'fully melted snow restores zero repaint coverage')

ok(P.usePhysicalBank('tree','tree','round')==false,'trees use conformal repaint instead of detached radial cap')
ok(P.usePhysicalBank('raised','wall','full')==false,'ledges/roofs/raised scenery use conformal repaint instead of detached cap')
ok(P.usePhysicalBank('ground','ground','full')==true,'ground may retain physical thickness geometry')
ok(P.usePhysicalBank('ice','ice','full')==true,'load-bearing ice may retain physical snow thickness')

-- Exact host mesh identity contract.  The wrapper must never infer terrain by
-- texture/palette, because that would repaint every tile sharing an atlas slot.
local rootMesh,nbMesh,other={},{},{}
local rootMap={id='ROOT'};local nbMap={id='NB'}
local C={}
function C.peek(map,body)
  if map==rootMap then return rootMesh end
  if map==nbMap then return nbMesh end
end
local host={require=function(name) if name=='ChunkMesher' then return C end error(name) end}
local calls=0
local Voxel3D={draw=function(...) calls=calls+1;return 'host' end}
ok(P.install(host,Voxel3D)==true,'surface painter installs only through host public module seam')
P.observeScene({map=rootMap,neighbors={{map=nbMap}}},true)
ok(P._isTerrainMesh(rootMesh)==true and P._isTerrainMesh(nbMesh)==true,'current and neighbor exact terrain meshes are recognized by object identity')
ok(P._isTerrainMesh(other)==false,'non-terrain mesh is never admitted by shared atlas/texture coincidence')
local ret=Voxel3D.draw(rootMesh,nil,nil)
ok(ret=='host' and calls==1,'headless/no-GPU path always preserves original host terrain draw')
P.uninstall()
local beforeCalls=calls
Voxel3D.draw(other)
ok(calls==beforeCalls+1,'uninstall restores exact original host draw function')

local cap=poolOne('ground','full',0.5,0,2,3,3)
P.capture({},cap,2,3,100)
ok(P.debug().active==1,'live SnowPack capture exposes bounded repaint population')
P.clearCapture()
ok(P.debug().active==0,'empty/melted capture removes repaint population immediately')


-- Mocked GPU-path contract: the exact host terrain mesh is drawn once by the
-- host and once by the snow-only conformal pass. The mesh itself is never
-- rewritten. The cinematic-tree fallback must pair beginWater/endWater and
-- composite against the readable scene depth.
local overlayDraws,rectDraws,beginWaterCalls,endWaterCalls=0,0,0,0
local function newShader()
  return {send=function(self,...) return true end,release=function() end}
end
local data={setPixel=function(self,...) return true end,release=function() end}
local image={setFilter=function(self,...) end,replacePixels=function(self,...) return true end,release=function() end}
_G.love={timer={getTime=function() return 10 end},image={newImageData=function(w,h) return data end},graphics={
  newShader=function(src) return newShader() end,
  newImage=function(d) return image end,
  setShader=function(...) return true end,
  setDepthMode=function(...) return true end,
  setColor=function(...) return true end,
  draw=function(mesh) overlayDraws=overlayDraws+1 return true end,
  rectangle=function(...) rectDraws=rectDraws+1 return true end,
}}
local gpuMesh={}
local gpuMap={id='GPUROOT'}
local GC={peek=function(map,body) if map==gpuMap then return gpuMesh end end}
local gpuHost={require=function(name) if name=='ChunkMesher' then return GC end error(name) end,exports={}}
local hostDraws=0
local depth={}
local GV={
  vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},eye={0,20,0},curveX=0,curveZ=0,curveK=0,
  draw=function(...) hostDraws=hostDraws+1 return 'gpu-host' end,
  lighting=function() end,
  size=function() return 320,240 end,
  beginWater=function() beginWaterCalls=beginWaterCalls+1;return {},depth end,
  endWater=function() endWaterCalls=endWaterCalls+1 end,
}
ok(P.install(gpuHost,GV,gpuHost)==true,'GPU-path wrapper installs on exact host draw seam')
P.observeScene({map=gpuMap,neighbors={}},true)
local gp=poolOne('tree','round',0.82,16,10,10,5)
P.capture({},gp,10,10,96)
local gr=GV.draw(gpuMesh,nil,nil)
ok(gr=='gpu-host' and hostDraws==1,'host terrain draw remains authoritative before repaint overlay')
ok(overlayDraws==1,'snow repaint redraws the exact same terrain mesh once without remeshing')
local beforeRect=rectDraws
local screenOK=P.paintCinematicTreesFromDepth()
ok(screenOK==true and beginWaterCalls==1 and endWaterCalls==1,'cinematic-tree repaint uses paired readable-depth scene pass')
ok(rectDraws==beforeRect+1,'cinematic-tree repaint composites one bounded fullscreen depth-resolved pass')
P.uninstall()
_G.love=nil

print(string.format('snow surface repaint 8.1.66: %d passed, %d failed',pass,fail))
os.exit(fail==0 and 0 or 1)
