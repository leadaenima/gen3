-- Weather FX 8.1.19 owned-shadow runtime contract.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; io.write("FAIL ",name,"\n") end
end

local Mat4=assert(loadfile(ROOT.."lib/voxel_atmos/stubs/Mat4.lua"))({})
local allocs,depthAllocs,setTargets,draws=0,0,{},0
local function canvas(w,h,opts)
  local c={w=w,h=h,opts=opts,released=false}
  function c:release() self.released=true end
  function c:setFilter() end
  function c:newImageData()
    return {getPixel=function(_,x,y) return 0,0,(y or 0)/3,1 end}
  end
  return c
end
local PixelCanvas={new=function(w,h,opts)
  allocs=allocs+1
  if opts and opts.format and tostring(opts.format):find("depth") then depthAllocs=depthAllocs+1 end
  return true,canvas(w,h,opts)
end}
local shader={send=function() return true end}
local graphics={
  newShader=function() return shader end,
  newCanvas=function(w,h,opts) allocs=allocs+1; return canvas(w,h,opts) end,
  setCanvas=function(t) setTargets[#setTargets+1]=t end,
  getCanvas=function() return nil end,
  clear=function() end,
  setDepthMode=function() end,getDepthMode=function() return nil,false end,
  setMeshCullMode=function() end,getMeshCullMode=function() return "none" end,
  setBlendMode=function() end,getBlendMode=function() return "alpha","alphamultiply" end,
  setColor=function() end,getColor=function() return 1,1,1,1 end,
  setShader=function() end,getShader=function() return nil end,
  draw=function(mesh) draws=draws+1; if mesh and mesh.fail then error("forced draw fault") end end,
  newMesh=function() return {release=function() end} end,
  newImage=function() return {release=function() end} end,
}
local image={newImageData=function()
  return {setPixel=function() end}
end}
local oldLove=_G.love; _G.love={graphics=graphics,image=image}

local VoxelState={angle=0.7,FOCAL=1.0}
local Shadows={off=function() return false end}
local hostLib={require=function(name)
  if name=="Mat4" then return Mat4 end
  if name=="VoxelState" then return VoxelState end
  if name=="PixelCanvas" then return PixelCanvas end
  if name=="Shadows" then return Shadows end
  error("unexpected host require "..tostring(name),0)
end}
local quality="high"
local WXV={require=function(name)
  if name=="Quality" then return {tier=function() return quality end} end
  error("unexpected WX require "..tostring(name),0)
end}
local oldCalls=0
local SM={KX=-0.5,KZ=0.1,HEIGHT=160,BIAS=.5,SLOPE=3.1,FAR_CAP=2.5,SIZES={1024,1536,2048},res=1024,vSign=1,
  available=function() oldCalls=oldCalls+1; return true end,
  begin=function() oldCalls=oldCalls+1; return true end,
  stale=function() oldCalls=oldCalls+1; return false end,
  finish=function() oldCalls=oldCalls+1 end,
}
local W=assert(loadfile(ROOT.."lib/WeatherShadowMap.lua"))(WXV)
local ok,why=W.install(hostLib,SM)
check(ok,"owned engine installs: "..tostring(why))
check(SM._wxOwned and SM._wxEngineVersion=="WeatherShadowMap/1","Weather FX ownership marker")
check(oldCalls==0,"install does not execute host shadow implementation")

local before=allocs
check(SM.available()==true,"availability succeeds")
check(allocs==before,"available does not allocate/resize shadow canvases")
check(SM.stale("1,2,3,4,5,6,7,geom") == true,"uncommitted map is stale")
local begun=SM.begin(100,100,320,240)
check(begun,"owned shadow pass begins")
check(allocs>=before+2 and depthAllocs>=1,"first real pass allocates color plus explicit depth")
local sawDepth=false
for _,t in ipairs(setTargets) do if type(t)=="table" and t.depthstencil then sawDepth=true end end
check(sawDepth,"explicit DPI-matched depth attachment is preferred")
local mesh={setTexture=function() end}
SM.draw(mesh,nil); SM.sprites(true); SM.sprites(false)
check(SM.finish("1,2,3,4,5,6,7,geom") == true,"completed pass commits")
check(SM.active()==true and SM.texture()~=nil,"committed map is active and sampleable")
check(SM.stale("1,2,3,4,5,99,101,geom") == false,"host 1/128 light signature fields no longer force recast")

local committed=SM.sunDir()[1]
SM.KX=SM.KX+0.0001 -- 0.016 world px at the 160px max caster
check(SM.stale("1,2,3,4,5,100,102,geom") == false,"sub-threshold light drift reuses map")
check(math.abs(SM.sunDir()[1]-committed)<1e-12,"receiver keeps committed light while map is reused")
SM.KX=SM.KX+0.0003
check(SM.stale("1,2,3,4,5,101,103,geom") == true,"greater-than-0.04px caster drift requests recast on HIGH")
check(SM.stale("2,2,3,4,5,101,103,geom") == true,"camera/geometry signature change still invalidates")

local allocAfterFirst=allocs
for i=1,20 do SM.available() end
check(allocs==allocAfterFirst,"repeated availability cannot churn GPU maps")

-- A caster/driver fault is contained: finish restores state and refuses to
-- publish the damaged map instead of poisoning the following scene pass.
SM.KX=-0.4
check(SM.begin(100,100,320,240),"fault-injection pass begins")
SM.draw({fail=true},nil)
check(SM.finish("1,2,3,4,5,1,1,geom") == false,"draw fault rejects damaged pass")
check(SM.active()==false,"damaged shadow texture is not advertised active")

-- Low quality uses a larger permitted endpoint drift, but geometry invalidation
-- remains exact. This reduces recast pressure without lowering caster coverage.
quality="low"; SM.KX=-0.4
check(SM.begin(100,100,320,240),"low-quality recovery pass begins")
check(SM.finish("3,2,3,4,5,1,1,geom"),"low-quality recovery commits")
SM.KX=SM.KX+0.0005 -- .08px < LOW .12 threshold
check(SM.stale("3,2,3,4,5,9,9,geom") == false,"LOW bounded drift reduces unnecessary recasts")
SM.KX=SM.KX+0.0005
check(SM.stale("3,2,3,4,5,9,9,geom") == true,"LOW still recasts before .16px accumulated drift")

SM.invalidate()
check(SM.active()==false and SM.stale("3,2,3,4,5,9,9,geom"),"invalidate releases readiness")
check(oldCalls==0,"host shadow implementation is never called after ownership")
_G.love=oldLove
print(("weather shadow engine: %d passed, %d failed; allocations=%d depth=%d draws=%d")
  :format(passed,failed,allocs,depthAllocs,draws))
os.exit(failed==0 and 0 or 1)
