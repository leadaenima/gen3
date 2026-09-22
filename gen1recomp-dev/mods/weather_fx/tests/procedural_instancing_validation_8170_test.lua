-- Weather FX 8.1.70: procedural snow/hail must self-test per-instance seed
-- behavior and fail open to the legacy CPU renderer when instances collapse.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1; print('PASS '..n) else fail=fail+1; print('FAIL '..n) end end

local function makeLove(collapse)
  local g={_collapse=collapse}
  function g.getSupported() return {instancing=true} end
  function g.newMesh(_,verts)
    return {attachAttribute=function() return true end, release=function() end}
  end
  function g.newShader(_) return {send=function() return true end, release=function() end} end
  function g.push() end; function g.pop() end; function g.origin() end
  function g.setCanvas(_) end; function g.clear() end; function g.setBlendMode() end; function g.setShader(_) end
  function g.drawInstanced(_,_) end
  function g.newCanvas(w,h)
    local canvas={w=w,h=h,release=function() end}
    function canvas:newImageData()
      return {
        getPixel=function(_,x,y)
          local centers = g._collapse and {8} or {8,24,40,56}
          for _,cx in ipairs(centers) do
            if math.abs(x-cx)<=1 and math.abs(y-8)<=1 then return 1,1,1,1 end
          end
          return 0,0,0,0
        end
      }
    end
    return canvas
  end
  return {graphics=g}
end

local function loadModule(rel,loveTable)
  love=loveTable
  local modules={}
  local V={}
  function V.require(name)
    if modules[name] then return modules[name] end
    if name=='MesoscaleField' then modules[name]={ready=function() return false end}; return modules[name] end
    if name=='InstanceSeedBuffer' then
      modules[name]={get=function() return {release=function() end},8192 end}
      return modules[name]
    end
    local m=assert(loadfile(ROOT..'lib/'..name..'.lua'))(V)
    modules[name]=m
    return m
  end
  V.safeCall=pcall
  return assert(loadfile(ROOT..rel))(V)
end

local SnowCollapsed=loadModule('lib/ProceduralSnowField.lua', makeLove(true))
ck(SnowCollapsed.supported()==false,'procedural snow rejects collapsed instance seeds and fails open')
SnowCollapsed.invalidate()
local SnowHealthy=loadModule('lib/ProceduralSnowField.lua', makeLove(false))
ck(SnowHealthy.supported()==true,'procedural snow accepts healthy per-instance seed variation')

local RainCollapsed=loadModule('lib/ProceduralPrecipField.lua', makeLove(true))
ck(RainCollapsed.supported()==false,'procedural hail/rain rejects collapsed instance seeds and fails open')
RainCollapsed.invalidate()
local RainHealthy=loadModule('lib/ProceduralPrecipField.lua', makeLove(false))
ck(RainHealthy.supported()==true,'procedural hail/rain accepts healthy per-instance seed variation')

local snowSrc=assert(io.open(ROOT..'lib/ProceduralSnowField.lua','rb')):read('*a')
ck(snowSrc:find('instance seed validation failed',1,true)~=nil,'snow source records the validation failure reason explicitly')
local rainSrc=assert(io.open(ROOT..'lib/ProceduralPrecipField.lua','rb')):read('*a')
ck(rainSrc:find('instance seed validation failed',1,true)~=nil,'precip source records the validation failure reason explicitly')

print(('procedural instancing validation 8.1.70: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
