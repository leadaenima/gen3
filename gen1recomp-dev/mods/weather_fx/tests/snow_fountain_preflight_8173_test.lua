-- Weather FX 8.1.73: first-frame snow/blizzard must prove procedural field
-- before allocation so the legacy instanced column path is not the visible owner.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local fronts=false
local Settings={isFirstPerson=function()return false end,splashOn=function()return false end,cloudHeightScale=function()return 1.5 end,
  snowAccumulationEnabled=function()return false end,weatherRenderDistanceScale=function()return 1 end,get=function(k)if k=='fronts'then return 'off'end return 'config'end}
local Config={get=function()return{fronts={enabled=fronts}}end}
local Quality={budget=function()return{worldPrecip=1,worldRadiusCap=750,worldSnowCap=5000,worldBlizzardCap=10000,worldRainCap=5000,worldHailCap=5000,worldSandCap=5000,worldAshCap=5000,worldDebrisCap=5000,snowPackDrawCap=0,footDrawCap=0,splash=0}end}
local proven=false;local probes=0;local reanchors=0
local PS={}
function PS.stats()return{proven=proven,failed=false}end
function PS.canVirtualize()return proven end
function PS.probe() probes=probes+1;proven=true;return true end
function PS.reanchor()reanchors=reanchors+1 end
local PP={stats=function()return{proven=false,failed=false}end,canVirtualize=function()return false end}
local V={safeCall=pcall}
function V.require(n)if n=='Settings'then return Settings elseif n=='Config'then return Config elseif n=='Quality'then return Quality elseif n=='ProceduralSnowField'then return PS elseif n=='ProceduralPrecipField'then return PP end error('no '..n,0)end
local W=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
local vox={far=512,eye={0,10,0},vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}}
local meta={anchorKind='live-player',deckY=120,deckSpan=24,Voxel3D=vox,player={px=0,py=0},map={id='A'}}
W.preflight(vox,{8,0,8},{wxId='BLIZZARD',snowIntensity=5},meta)
ck(probes==1 and proven,'blizzard procedural snow is proven before update')
W.update(1/60,{8,0,8},{wxId='BLIZZARD',snowIntensity=5},meta)
local st=W.snowVirtualization()
ck(st.fullVisual==true and st.simulated<=96 and st.procedural==st.logical,'first blizzard update immediately uses distributed procedural field, not giant legacy instance pool')
-- A map change is known to preflight before update; reanchor immediately.
meta.map={id='B'};meta.player={px=320,py=160};W.preflight(vox,{8,0,8},{wxId='BLIZZARD',snowIntensity=5},meta)
W.update(1/60,{8,0,8},{wxId='BLIZZARD',snowIntensity=5},meta)
ck(reanchors>=1,'map change immediately reanchors procedural snow field')
ck(W.snowVirtualization().fullVisual==true,'blizzard remains visible immediately after map change')
print(('snow fountain preflight 8.1.73: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
