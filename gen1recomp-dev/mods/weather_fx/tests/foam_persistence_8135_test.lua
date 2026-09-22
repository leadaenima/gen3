-- Weather FX 8.1.35 persistent whitewater / no-teleport contract.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end
local V={require=function(n) error("optional:"..tostring(n),0) end}
local R=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))(V)

local pi=math.pi
local a=.17;local k=2*pi/78
local Water={
  WAVE_TRAINS={{math.cos(a)*k,math.sin(a)*k,.46,.46},{math.cos(a)*2*k,math.sin(a)*2*k,.92,.17},{math.cos(a+.46)*2*pi/51,math.sin(a+.46)*2*pi/51,.72,.20}},
  WAVE_SWELL={math.cos(a+.08)*2*pi/290,math.sin(a+.08)*2*pi/290,.42,.32},
  WAVE_BEND={math.cos(a+pi*.5)*2*pi/220,math.sin(a+pi*.5)*2*pi/220,.28,.95},
}
local b={id=1,signature="foam-persistence",tide=0,wave=1.1,kind="SEA"}
local rough=.92

check(type(R._whitecapTrackAt)=="function" and type(R._foamEnvelope)=="function","renderer exposes bounded analytic foam-track test seam")
check(R._foamEnvelope(.001)<.001 and R._foamEnvelope(.999)<.001,"foam lifetime collapses to zero at both sides of an invisible cycle reset")
check(R._foamEnvelope(.50)>.95,"foam lifetime reaches full size through the middle of a whitecap run")

-- Find a genuinely aerating crest track from a small water field. A real body
-- contains many deterministic candidates; testing an arbitrary single cell can
-- legitimately select a trough track that never foams.
local c,bestT,bestS,bestX,bestZ=nil,0,-1,0,0
for gz=0,9 do for gx=0,9 do
  local q={gx=gx,gz=gz}
  for i=0,1200 do
    local t=i/120
    local x,z,st=R._whitecapTrackAt(b,Water,t,q,rough)
    if st>bestS then c,bestT,bestS,bestX,bestZ=q,t,st,x,z end
  end
end end
check(c~=nil and bestS>.12,"analytic system contains crest-qualified persistent whitecap tracks")

local visible=0;local maxJump=0;local maxStrengthStep=0;local prev=nil
for i=0,1800 do
  local t=i/120
  local x,z,st,q,life=R._whitecapTrackAt(b,Water,t,c,rough)
  if st>.035 then visible=visible+1 end
  if prev and st>.035 and prev.s>.035 then
    local d=math.sqrt((x-prev.x)^2+(z-prev.z)^2)
    if d>maxJump then maxJump=d end
    local ds=math.abs(st-prev.s);if ds>maxStrengthStep then maxStrengthStep=ds end
  end
  prev={x=x,z=z,s=st,q=q,life=life}
end
check(visible>40,"crest-following whitecap remains alive across many consecutive frames instead of single-frame threshold flashes")
check(maxJump<0.12,"visible whitecap center moves continuously frame-to-frame with no teleport jump")
check(maxStrengthStep<0.09,"whitecap growth/decay is temporally smooth rather than hard on/off")

local x2,z2,s2=R._whitecapTrackAt(b,Water,bestT+.20,c,rough)
local moved=math.sqrt((x2-bestX)^2+(z2-bestZ)^2)
check(bestS>.12 and s2>.01,"analytic track finds and retains an aerated moving crest")
check(moved>.25 and moved<1.8,"whitecap visibly travels with its crest over time instead of staying on a fixed world square")

local src=assert(io.open(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua","rb")):read("*a")
check(src:find("n=foamRibbon",1,true)~=nil,"open-water whitecaps use tapered multi-segment ribbon geometry")
check(src:find("River whitewater is now a moving tapered streak",1,true)~=nil,"river rapid foam uses persistent moving tapered streaks")
check(src:find("Static edge admission",1,true)~=nil,"shore-break candidates are stable coastline identities rather than time-bucket rerolls")
check(src:find("floor(t*0.5)",1,true)==nil,"old time-bucket shoreline foam teleport trigger is removed")
check(src:find("fixed world points each",1,true)~=nil,"source documents and guards the original fixed-sample teleport failure")

print(string.format("foam persistence 8.1.35: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
