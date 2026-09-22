local passed,failed=0,0
local function ck(v,m) if v then passed=passed+1 else failed=failed+1; if failed<=30 then io.write('FAIL '..m..'\n') end end end
local function finite(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local cfg={celestial={latitude=35,verticalOrbit=true,pairedMoonOrbit=true},time={cycleMinutes=24},seasons={daysPerSeason=15}}
local TOD={hour=12,source='accelerated',elapsed=0}
local V={require=function(n) if n=='Config' then return {get=function() return cfg end} elseif n=='TimeOfDay' then return TOD end end}
local S=assert(loadfile('lib/CelestialSim.lua'))(V)
local tw={DAY=true,GOLDEN=true,CIVIL=true,NAUTICAL=true,ASTRONOMICAL=true,NIGHT=true}
for day=0,360,15 do
  local rise,set=S.sunriseSunset(day); ck(finite(rise) and finite(set),'finite sunrise/set d'..day); ck(rise<set,'sunrise before sunset d'..day); ck((set-rise)>7 and (set-rise)<17,'credible day length d'..day)
  local prev=nil
  for q=0,95 do
    local h=q/4; local x=S.sample(h,day); local a=x.sun; local m=x.moon
    ck(finite(x.starVisibility) and x.starVisibility>=0 and x.starVisibility<=1,'star vis range')
    ck(tw[x.twilight]==true,'known twilight state')
    for _,b in ipairs({a,m}) do
      ck(finite(b.dx) and finite(b.dy) and finite(b.dz),'body vector finite')
      local len=math.sqrt(b.dx*b.dx+b.dy*b.dy+b.dz*b.dz); ck(math.abs(len-1)<1e-9,'body unit vector')
      ck(finite(b.alpha) and b.alpha>=0 and b.alpha<=1,'body alpha range')
      ck(finite(b.horizonFraction) and b.horizonFraction>=0 and b.horizonFraction<=1,'horizon fraction range')
      if b.color then for i=1,3 do ck(finite(b.color[i]) and b.color[i]>=0 and b.color[i]<=1.5,'body color finite') end end
    end
    local dot=a.dx*m.dx+a.dy*m.dy+a.dz*m.dz; ck(math.abs(math.abs(dot)-1)<1e-9,'paired vertical sun/moon remain collinear through eclipse handoff')
    ck(finite(m.phase) and m.phase>=0 and m.phase<1,'lunar phase range')
    ck(finite(m.illumination) and m.illumination>=0 and m.illumination<=1,'lunar illumination range')
    if prev then
      local dd=math.sqrt((a.dx-prev.dx)^2+(a.dy-prev.dy)^2+(a.dz-prev.dz)^2); ck(dd<0.12,'15-minute solar motion continuous')
    end
    prev={dx=a.dx,dy=a.dy,dz=a.dz}
  end
end
local last=-1
for i=-80,80 do
  local alt=i/20; local f=S.discHorizonFraction(alt,3.24); ck(finite(f) and f>=0 and f<=1,'disc fraction bounded'); ck(f+1e-12>=last,'disc fraction monotonic'); last=f
end
-- Lunar calendar sweep: no NaNs or phase-name holes through two full synodic cycles.
local names={NEW=true,WAXING_CRESCENT=true,FIRST_QUARTER=true,WAXING_GIBBOUS=true,FULL=true,WANING_GIBBOUS=true,LAST_QUARTER=true,WANING_CRESCENT=true}
for d=0,60 do for h=0,23,3 do local phase,angle,illum,age,name=S.lunarPhase(h,d); ck(finite(phase) and finite(illum) and finite(angle) and finite(age),'lunar sweep finite'); ck(phase>=0 and phase<1 and illum>=0 and illum<=1,'lunar sweep range'); ck(names[name]==true,'lunar phase named') end end
print(string.format('8.1.18 celestial stress: %d passed, %d failed',passed,failed))
os.exit(failed>0 and 1 or 0)
