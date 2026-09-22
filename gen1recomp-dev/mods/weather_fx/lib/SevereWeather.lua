local V = ...
local S={state={type='none',severity=0,rotation=0,convective=0,whiteout=0,dust=0}}
local last='none'
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
function S.update(dt,climate,world,cloud,wind)
  climate=climate or {}; world=world or {}; cloud=cloud or {}; wind=wind or {}
  local storm=clamp(tonumber(climate.storm) or 0,0,1); local precip=clamp(tonumber(climate.precip) or 0,0,1); local temp=tonumber(climate.temperature) or 10; local speed=clamp(tonumber(wind.speed) or tonumber(climate.wind) or 0,0,1.5); local charge=clamp(tonumber(cloud.charge) or 0,0,1)
  local conv=clamp(storm*.52+charge*.34+precip*.14,0,1); local rot=clamp(storm*speed*.72+charge*.18,0,1); local white=(temp<1) and clamp(precip*.62+speed*.48,0,1) or 0; local dust=(temp>18) and clamp(speed*.62+(tonumber(climate.aerosol) or 0)*.38,0,1) or 0
  local typ,sev='none',0
  if white>.72 then typ,sev='blizzard',white elseif conv>.78 and rot>.62 then typ,sev='supercell',math.max(conv,rot) elseif conv>.64 then typ,sev='squall',conv elseif dust>.72 then typ,sev='duststorm',dust end
  local f=1-math.exp(-math.max(0,tonumber(dt) or 0)/2); S.state.severity=S.state.severity+(sev-S.state.severity)*f; S.state.type=typ; S.state.rotation=rot; S.state.convective=conv; S.state.whiteout=white; S.state.dust=dust
  if typ~=last then local E=V.require('EnvironmentalEvents'); if E and E.publish then E.publish('severe_weather_change',{from=last,to=typ,severity=S.state.severity}) end; last=typ end
end
function S.peek() return S.state end
function S.sample() local o={}; for k,v in pairs(S.state) do o[k]=v end; return o end
return S
