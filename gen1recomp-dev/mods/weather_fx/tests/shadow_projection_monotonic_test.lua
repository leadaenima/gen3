-- Weather FX 8.1.19 — owned shadow projection monotonicity proof.
-- Reproduce the host's rotating-light texel snap, then execute the production
-- WeatherShadowMap fit and prove its receiver projection never steps backward.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; io.write("FAIL ",name,"\n") end
end
local function read(rel)
  local f=assert(io.open(ROOT..rel,"rb")); local s=f:read("*a"); f:close(); return s
end
local atmos=read("lib/DramalessAtmos.lua")
local owned=read("lib/WeatherShadowMap.lua")
local eng=read("lib/CelestialEngine.lua")
check(atmos:find('V.require("WeatherShadowMap")',1,true)~=nil and atmos:find('WXShadow.install(hostLib,ShadowMap)',1,true)~=nil,
  "Weather FX installs its owned shadow engine")
check(owned:find('_wxProjectionMode="weather-owned-continuous"',1,true)~=nil,
  "projection reports Weather-owned continuous mode")
check(owned:find('Intentionally NO light-space floor(l/texel)',1,true)~=nil,
  "solar light-space texel snap is deliberately absent")
check(owned:find('return math.floor((tonumber(v) or 0)*16 + 0.5) / 16',1,true)~=nil,
  "camera anchor is independently stabilized at 1/16 world pixel")
check(owned:find('caster%-endpoint%-drift')~=nil and owned:find('return 0.04',1,true)~=nil,
  "recast policy is sub-pixel caster-endpoint drift")
check(atmos:find('_wxFineMotionWrapped',1,true)==nil and atmos:find('_wxContinuousProjectionWrapped',1,true)==nil,
  "legacy host shadow wrappers are removed")
check(eng:find('shadow rig may',1,true)~=nil and eng:find('never reverse direction',1,true)~=nil,
  "celestial shadow rig retains its monotonic guard")

local Mat4=assert(loadfile(ROOT.."lib/voxel_atmos/stubs/Mat4.lua"))({})
local VoxelState={angle=0.7,FOCAL=1.0}
local Shadows={off=function() return false end}
local hostLib={require=function(name)
  if name=="Mat4" then return Mat4 end
  if name=="VoxelState" then return VoxelState end
  if name=="Shadows" then return Shadows end
  if name=="PixelCanvas" then error("not present",0) end
  error("unexpected host require "..tostring(name),0)
end}
local oldLove=_G.love
_G.love={graphics={newShader=function() return {} end,newCanvas=function() return {} end}}
local WX=assert(loadfile(ROOT.."lib/WeatherShadowMap.lua"))({require=function(name)
  if name=="Quality" then return {tier=function() return "high" end} end
  error("unexpected Weather FX require "..tostring(name),0)
end})
local SM={KX=-1.2,KZ=0,HEIGHT=160,BIAS=.5,SLOPE=3.1,FAR_CAP=2.5,SIZES={1024,1536,2048}}
local ok,why=WX.install(hostLib,SM)
check(ok,"owned shadow engine installs in projection harness: "..tostring(why))
_G.love=oldLove

local Z01={1,0,0,0, 0,1,0,0, 0,0,0.5,0.5, 0,0,0,1}
local function toUnit(sign)
  return {0.5,0,0,0.5, 0,0.5*sign,0,0.5, 0,0,1,0, 0,0,0,1}
end
local function transform(m,x,y,z)
  return m[1]*x+m[2]*y+m[3]*z+m[4],m[5]*x+m[6]*y+m[7]*z+m[8],m[9]*x+m[10]*y+m[11]*z+m[12]
end
local HEIGHT,FAR_CAP,FOCAL=160,2.5,1.0
local function groundReach(vh,angle)
  local cap=FAR_CAP*vh; local half=math.atan(1/(2*FOCAL)); local below=(math.pi/2-angle)-half
  if below<=0.02 then return cap end
  local dist=FOCAL*vh; local horizon=dist*math.cos(angle)/math.tan(below)
  return math.max(vh/2,math.min(cap,horizon-dist*math.sin(angle)))
end
local function stockFit(kx,kz)
  local cx,cy,vw,vh,angle,res=100,100,320,240,0.7,2048
  local dx,dy,dz=kx,-1,kz; local len=math.sqrt(dx*dx+dy*dy+dz*dz)
  local view=Mat4.lookAt({0,0,0},{dx/len,dy/len,dz/len},{0,0,-1})
  local reach=HEIGHT*math.max(math.abs(kx),math.abs(kz))+24; local north=groundReach(vh,angle); local spread=north*0.5
  local xs={cx-vw/2-spread,cx+vw/2+spread+reach}; local ys={-32,HEIGHT}; local zs={cy-north,cy+vh/2+reach}
  local l,r,b,t,zn,zf
  for _,x in ipairs(xs) do for _,y in ipairs(ys) do for _,z in ipairs(zs) do
    local px,py,pz=transform(view,x,y,z)
    l=l and math.min(l,px) or px; r=r and math.max(r,px) or px; b=b and math.min(b,py) or py; t=t and math.max(t,py) or py
    zn=zn and math.min(zn,pz) or pz; zf=zf and math.max(zf,pz) or pz
  end end end
  local w,h=r-l,t-b; local tx,ty=w/res,h/res
  l=math.floor(l/tx)*tx; b=math.floor(b/ty)*ty; r,t=l+w,b+h
  local near,far=-zf-64,-zn+64; local proj=Mat4.ortho(l,r,b,t,near,far)
  proj=Mat4.mul(Mat4.scale(1,-1,1),proj); proj=Mat4.mul(Z01,proj)
  return Mat4.mul(toUnit(1),Mat4.mul(proj,view))
end

local stockReverse,wxReverse,wxMoved=0,0,0
local prevStock,prevWx
for i=0,5000 do
  local kx=-1.2+(1.0*i/5000); SM.KX=kx
  local sm=stockFit(kx,0); local fit=SM._fitForTest(100,100,320,240,2048); local wm=fit.uv
  local sx=select(1,transform(sm,100,0,100)); local wx=select(1,transform(wm,100,0,100))
  if prevStock then
    local ds,dw=sx-prevStock,wx-prevWx
    if ds < -1e-12 then stockReverse=stockReverse+1 end
    if dw < -1e-12 then wxReverse=wxReverse+1 end
    if math.abs(dw)>1e-12 then wxMoved=wxMoved+1 end
  end
  prevStock,prevWx=sx,wx
end
check(stockReverse>20,"stock host texel snap reproduces reverse projection steps")
check(wxReverse==0,"Weather FX owned projection has zero reverse steps")
check(wxMoved>4900,"Weather FX owned projection advances on essentially every sun sample")
print(("shadow projection monotonicity: %d passed, %d failed; stock reversals=%d, wx reversals=%d")
  :format(passed,failed,stockReverse,wxReverse))
os.exit(failed==0 and 0 or 1)
