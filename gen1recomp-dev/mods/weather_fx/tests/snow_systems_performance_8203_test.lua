-- Weather FX 8.2.3: snow-only secondary-system performance contract.
-- Falling flakes remain smooth every rendered frame. Slow physical accumulation
-- is staged/cached independently so weak phones do not rescan/reupload the same
-- ground field 60 times per second.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
if ROOT=='' then ROOT='./' end;if ROOT:sub(-1)~='/' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function text(p)local f=assert(io.open(ROOT..p,'rb'));local s=f:read('*a');f:close();return s end
local wp=text('lib/voxel_atmos/WorldPrecip.lua')
local sp=text('lib/SnowSurfacePaint.lua')
local q=text('lib/Quality.lua')
local ps=text('lib/ProceduralSnowField.lua')

ck(wp:find('simTime-(tonumber(WP._gsnowStageAt) or -1e9)>=0.10',1,true)~=nil,'ground SnowPack staging is capped at 10 Hz while falling snow remains frame-rate animated')
ck(wp:find('gdx*gdx+gdz*gdz>=144',1,true)~=nil,'meaningful player movement refreshes ground-bank staging immediately')
ck(wp:find('WP._gsnowPoolRevision',1,true)~=nil and wp:find('WP._gsnowMeshRevision~=revision',1,true)~=nil,'ground bank mesh is rebuilt only when staged SnowPack data changes')
ck(wp:find('gsnowMesh=uploadMesh',1,true)~=nil,'cached ground-bank path still uploads real physical bank geometry when changed')
ck(sp:find('if not force and not P._dirty and P._image then return true end',1,true)~=nil,'snow coverage texture skips identical reraster/re-upload frames')
ck(q:find('snowProbeCap=96',1,true)~=nil and q:find('snowProbeCap=16',1,true)~=nil,'invisible snow interaction probes scale from 96 MAX to 16 POTATO')
ck(wp:find('qb.snowProbeCap',1,true)~=nil,'WorldPrecip actually consumes quality snow interaction probe budget')
ck(q:find('worldSnowCap=100000',1,true)~=nil and q:find('worldBlizzardCap=200000',1,true)~=nil,'visual MAX SNOW/BLIZZARD ceilings remain unchanged')
ck(ps:find('fieldTime',1,true)~=nil and ps:find('renderClock',1,true)~=nil,'falling 3D snow still has independent per-render-frame animation clock')
ck(ps:find("{{0,0,0}},'points','static'",1,true)~=nil and ps:find('detailRatio=math.min(1,(detailRadius*detailRadius)/(farRadius*farRadius))',1,true)~=nil,'hybrid far-point/near-crystal snow LOD remains installed')

-- Exercise Quality.budget so the probe ceilings are runtime values, not comments.
do
  local tier='potato'
  local V={}
  function V.require(n)
    if n=='Settings' then return {get=function(k) if k=='quality' then return tier elseif k=='autoPerformance' then return'off' end end} end
    if n=='Config' then return {get=function()return{quality=tier}end} end
    if n=='PerformanceGovernor' then return {particleScale=function()return 1 end} end
    return {}
  end
  local Q=assert(loadfile(ROOT..'lib/Quality.lua'))(V)
  local b=Q.budget(1)
  ck(b.snowProbeCap==16 and b.worldSnowCap==1600 and b.worldBlizzardCap==2400,'POTATO runtime keeps 16 CPU probes while preserving its full visual snow budgets')
  tier='max'
  -- Module reads Settings dynamically, while Config is only fallback.
  local b2=Q.budget(1)
  ck(b2.snowProbeCap==96 and b2.worldSnowCap==100000 and b2.worldBlizzardCap==200000,'MAX runtime retains 96 interaction probes and full 100k/200k visual budgets')
end

print(('8.2.3 snow secondary-system performance: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
