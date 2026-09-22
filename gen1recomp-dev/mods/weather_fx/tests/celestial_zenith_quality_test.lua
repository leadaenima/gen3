local passed,failed=0,0
local function check(v,n) if v then passed=passed+1 else failed=failed+1;print('FAIL '..n) end end
local cache={}
local V={}
function V.require(n) if cache[n] then return cache[n] end; local f=assert(loadfile('lib/'..n..'.lua')); local m=f(V); cache[n]=m; return m end
local N=V.require('NightSky')
local function dir(pitchDeg,yawDeg)
  local p=math.rad(pitchDeg); local y=math.rad(yawDeg or 0); local cp=math.cos(p)
  return cp*math.cos(y),math.sin(p),cp*math.sin(y)
end
-- Low quality frequently runs a smaller host canvas. Projection must stay valid
-- all the way to exact zenith at every representative canvas size; quality is
-- not allowed to remove celestial catalogue entries.
for _,wh in ipairs({{320,288},{240,216},{160,144},{106,96},{80,72}}) do
  local w,h=wh[1],wh[2]
  for _,pitch in ipairs({0,45,80,88,89.9}) do
    local x,y,z=dir(pitch,25); local host={eye={0,0,0},focus={x,y,z},fovY=math.rad(65),vp={999}}
    local sx,sy,front=N.projectDirection(host,x,y,z,w,h)
    check(sx and math.abs(sx-w/2)<1e-5 and math.abs(sy-h/2)<1e-5 and front>0,('forward vault centered %dx%d pitch %.1f'):format(w,h,pitch))
  end
  local host={eye={0,0,0},focus={0,1,0},fovY=math.rad(65),vp={999}}
  local sx,sy,front=N.projectDirection(host,0,1,0,w,h)
  check(sx and math.abs(sx-w/2)<1e-5 and math.abs(sy-h/2)<1e-5 and front>0,('exact zenith visible %dx%d'):format(w,h))
  local a1,b1=N.projectDirection(host,.05,.9987,0,w,h); local a2,b2=N.projectDirection(host,-.05,.9987,0,w,h)
  check(a1 and a2 and math.abs(a1-a2)>.45,('zenith horizontal separation survives %dx%d'):format(w,h))
  check(b1 and b2,('zenith neighbors remain visible %dx%d'):format(w,h))
end
print(('celestial zenith projection: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
