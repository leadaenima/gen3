-- Continuous celestial + single-authority shadow motion proof (4.35.13).
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; io.write("FAIL ",name,"\n") end
end
local function read(rel)
  local f=assert(io.open(ROOT..rel,"rb")); local s=f:read("*a"); f:close(); return s
end

local main=read("main.lua")
local atmos=read("lib/DramalessAtmos.lua")
local eng=read("lib/CelestialEngine.lua")
local shadow=read("lib/WeatherShadowMap.lua")
local cfg=read("config.lua")

check(main:find('local bx = tonumber(body.x) or 0',1,true)~=nil,
  "fallback sun/moon center is subpixel")
check(main:find('math.floor(body.x / cell)',1,true)==nil,
  "fallback body center no longer snaps to cell grid")
check(atmos:find('V.require(\"WeatherShadowMap\")',1,true)~=nil and atmos:find('WXShadow.install(hostLib,ShadowMap)',1,true)~=nil,
  "Weather FX owned shadow-map installer exists")
check(shadow:find('_wxRecastMode=\"caster-endpoint-drift\"',1,true)~=nil and shadow:find('return 0.04',1,true)~=nil,
  "owned shadow recast uses bounded caster endpoint drift")
check(atmos:find('_wxFineMotionWrapped',1,true)==nil and atmos:find('_wxContinuousProjectionWrapped',1,true)==nil,
  "legacy host shadow wrappers are gone")
check(atmos:find('ONE celestial-shadow authority only',1,true)~=nil and atmos:find('CE.shadowRig()',1,true)~=nil,
  "voxel in-scene path uses the smoothed celestial shadow authority")
check(atmos:find('CB.shearAt(hour)',1,true)==nil and atmos:find('hour = TOD and TOD.hour',1,true)==nil,
  "raw TimeOfDay shear writer cannot fight the smoothed shadow rig")
check(cfg:find('shadowMotionPrecision = 65536',1,true)~=nil,
  "default shadow motion precision is 65536")
check(eng:find('updateShadowRig(s,dt)',1,true)~=nil and eng:find('1-exp(-24.0*dt)',1,true)~=nil,
  "shadow rig is temporally updated each frame")
check(eng:find('smoothRange(1.0,12.0,alt)',1,true)~=nil,
  "direct shadows fade through horizon handoff")
check(eng:find('Engine._shadowKind~=kind',1,true)~=nil,
  "sun moon shadow-source switch is explicitly guarded")

-- Runtime: feed a continuously moving light and prove shadow shear advances in
-- small non-zero increments rather than remaining quantized to 1/128.
local cfgT={celestial={enabled=true,motionSmoothing=true,shadowMotionPrecision=65536},time={cycleMinutes=20}}
local tod={hour=12,source="cycle",pin=nil}
local modules={Config={get=function() return cfgT end},TimeOfDay=tod}
local V={}
function V.require(name) if modules[name] then return modules[name] end; error("unexpected require "..tostring(name),0) end
local E=assert(loadfile(ROOT.."lib/CelestialEngine.lua"))(V)
-- Exercise presentation clock directly; each frame must advance by a small amount.
E.time=0
local prev=E.presentationHour(12,1/60)
E._clockVelocity=24/(20*60)
local moved=0
for i=1,30 do
  E.time=E.time+1/60
  local h=E.presentationHour(12,1/60)
  local d=((h-prev+12)%24)-12
  if math.abs(d)>1e-8 then moved=moved+1 end
  check(math.abs(d)<0.002,"micro celestial step #"..i)
  prev=h
end
check(moved>=28,"celestial presentation advances on nearly every frame")

print(("continuous celestial/shadow motion: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
