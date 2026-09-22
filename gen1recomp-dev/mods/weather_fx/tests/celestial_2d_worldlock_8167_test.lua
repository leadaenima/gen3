local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local p,f=0,0;local function ck(v,m)if v then p=p+1;print('PASS '..m)else f=f+1;print('FAIL '..m)end end
local TOD={hour=9}
local NightSky={projectDirection=function(V3,dx,dy,dz,w,h)
  -- deterministic stand-in for the production camera-basis projector: rotating
  -- camera yaw moves the same fixed world direction across the screen.
  local yaw=V3.yaw or 0;local c,s=math.cos(-yaw),math.sin(-yaw);local rx=dx*c-dz*s;local rz=dx*s+dz*c
  if rz<=-0.99 then return nil end
  return w*.5+rx*w*.25,h*.5-dy*h*.25
end}
local V={};function V.require(n)if n=='TimeOfDay'then return TOD elseif n=='NightSky'then return NightSky end error(n)end
local C=assert(loadfile(ROOT..'lib/CelestialBodies.lua'))(V)
local a=C.projectBoth(160,144,60,9,{yaw=0})
local b=C.projectBoth(160,144,60,9,{yaw=math.pi/2})
ck(a~=nil and b~=nil,'2D celestial projection accepts live voxel camera basis')
ck(math.abs((a.x or 0)-(b.x or 0))>5,'rotating voxel camera changes screen position of fixed world sun direction')
local c=C.projectBoth(160,144,60,9,nil)
ck(c~=nil,'non-voxel 2D celestial fallback remains available')
print(('2D celestial world-lock 8.1.67: %d passed, %d failed'):format(p,f));os.exit(f==0 and 0 or 1)
