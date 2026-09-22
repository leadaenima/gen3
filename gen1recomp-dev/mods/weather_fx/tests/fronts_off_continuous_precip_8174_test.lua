-- Weather FX 8.1.74: WEATHER FRONTS OFF must not let player movement through
-- mesoscale noise cells pulse rain/snow/hail intensity or shader patchiness.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end

local wp=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb')):read('*a')
ck(wp:find('local frontsOn = WP._frontsEnabled()',1,true)~=nil,'WorldPrecip resolves front ownership before mesoscale precipitation scaling')
ck(wp:find('WP._uniformPrecipField = not frontsOn',1,true)~=nil,'WorldPrecip records uniform precipitation ownership when fronts are OFF')
ck(wp:find('if frontsOn then\n      local M=WP._mesoscaleModule()',1,true)~=nil,'player-position mesoscale intensity modulation is fronts-ON only')
ck(wp:find('rainI,snowI,hailI=rainI*localScale,snowI*localScale,hailI*localScale',1,true)~=nil,'fronts-ON mesoscale modulation remains inherited')
ck(wp:find('if baseRainI>.02 and rainI<=.02 then rainI=.021 end',1,true)~=nil,'fronts-ON rain banding cannot hard-toggle an active rain channel off at allocation threshold')
ck(wp:find('uniformField=WP._uniformPrecipField==true',1,true)~=nil,'runtime forwards uniform-field ownership into procedural precipitation')

local function graphicsHarness()
  local captures={}
  local g={}
  function g.getSupported() return {instancing=true} end
  function g.newMesh(_,_) return {attachAttribute=function() return true end,release=function() end} end
  function g.newShader(_)
    local sh={}
    function sh:send(k,v) captures[k]=v; return true end
    function sh:release() end
    return sh
  end
  function g.drawInstanced(_,_) return true end
  function g.setBlendMode() end
  function g.setDepthMode() end
  function g.setShader() end
  function g.setColor() end
  return g,captures
end
local function makeV(captures)
  local seed={release=function() end}
  local modules={
    InstanceSeedBuffer={get=function() return seed,8192 end},
    MesoscaleField={ready=function() return true end,renderParams=function() return {scale=520,frontScale=1180,offsetX=0,offsetZ=0,windX=1,windZ=0,patchiness=.91,floor=.07} end},
  }
  local V={safeCall=pcall}
  function V.require(name) return modules[name] end
  return V
end

local function exercise(rel,kind)
  local g,captures=graphicsHarness(); love={graphics=g}
  local V=makeV(captures)
  local P=assert(loadfile(ROOT..rel))(V)
  local vox={vp={},eye={0,8,0},beginEffect=function() return false end}
  local opts={count=8,eye={0,8,0},focus={0,0,0},wind={0,0},nearRadius=1.5,farRadius=256,topY=80,bottomY=-16,span=64,time=1,intensity=1,tint={1,1,1},uniformField=true}
  if kind then opts.kind=kind end
  local ok,n=P.draw(vox,opts)
  ck(ok==true and n==8,rel..' uniform-field draw succeeds')
  ck(captures.fieldPatchiness==0 and captures.fieldPatchFloor==1,rel..' fronts-OFF uniform mode removes mesoscale dry bands')
  captures.fieldPatchiness,captures.fieldPatchFloor=nil,nil
  opts.uniformField=false;opts.time=2
  ok,n=P.draw(vox,opts)
  ck(ok==true and n==8,rel..' fronts-ON draw succeeds')
  ck(math.abs((captures.fieldPatchiness or 0)-.91)<1e-9 and math.abs((captures.fieldPatchFloor or 0)-.07)<1e-9,rel..' fronts-ON mode preserves regional mesoscale banding')
end
exercise('lib/ProceduralPrecipField.lua','rain')
exercise('lib/ProceduralSnowField.lua',nil)


-- Exercise the actual WorldPrecip allocation edge. A changing mesoscale sample
-- must not pulse fronts-OFF rain as the player walks; fronts-ON may thin the
-- band, but an authored active rain channel must not fall through the engine's
-- >0.02 allocation gate solely because of mesoscale scaling.
do
  local function makeWorld(frontsEnabled)
    local msScale=1
    local Settings={isFirstPerson=function() return false end,splashOn=function() return false end,cloudHeightScale=function() return 1.5 end,
      snowAccumulationEnabled=function() return false end,weatherRenderDistanceScale=function() return 1 end,
      get=function(k) if k=='fronts' then return frontsEnabled and 'on' or 'off' end return 'config' end}
    local Config={get=function() return {fronts={enabled=frontsEnabled}} end}
    local Quality={budget=function() return {worldPrecip=.10,worldRadiusCap=96,worldRainCap=64,worldSnowCap=64,worldBlizzardCap=64,worldHailCap=64,worldSandCap=64,worldAshCap=64,worldDebrisCap=64,snowPackDrawCap=0,footDrawCap=0,splash=0} end}
    local M={peek=function() return {precipScale=msScale} end,ready=function() return true end}
    local V={safeCall=pcall}
    function V.require(name)
      if name=='Settings' then return Settings elseif name=='Config' then return Config elseif name=='Quality' then return Quality elseif name=='MesoscaleField' then return M end
      error('no '..tostring(name),0)
    end
    local W=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
    return W,function(v) msScale=v end
  end
  local meta={anchorKind='live-player',deckY=120,deckSpan=2,Voxel3D={far=96},player={px=0,py=0},map={id='A'}}
  local weather={wxId='RAIN',rainIntensity=.30}
  local W,setScale=makeWorld(false)
  setScale(1);W.update(.016,{8,0,8},weather,meta);local a=W.precipVirtualization().rain.logical
  meta.player.px=80;setScale(.05);W.update(.016,{88,0,8},weather,meta);local b=W.precipVirtualization().rain.logical
  meta.player.px=160;setScale(1.15);W.update(.016,{168,0,8},weather,meta);local c=W.precipVirtualization().rain.logical
  ck(a>0 and a==b and b==c,'fronts-OFF rain population stays continuous while walking across changing mesoscale samples')

  local WF,setFrontScale=makeWorld(true)
  meta.player.px=0;setFrontScale(1);WF.update(.016,{8,0,8},weather,meta);local fa=WF.precipVirtualization().rain.logical
  meta.player.px=80;setFrontScale(.05);WF.update(.016,{88,0,8},weather,meta);local fb=WF.precipVirtualization().rain.logical
  ck(fa>0 and fb>0,'fronts-ON mesoscale thinning cannot hard-stop an authored active rain channel at the allocation threshold')
end

print(('fronts-off continuous precip 8.1.74: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
