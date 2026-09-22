local V = ...
-- Non-invasive reaction model. It exposes intent/affinity to companion NPC and
-- encounter mods; it does not rewrite their entities or AI tables.
local E={state={shelter=0,caution=0,activity=1,flyingActivity=1,waterActivity=1,electricActivity=1,iceActivity=1}}
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
function E.update(dt,climate,events,surface)
  climate=climate or {}; surface=surface or {}; local s=E.state
  local storm=clamp(tonumber(climate.storm) or 0,0,1); local precip=clamp(tonumber(climate.precip) or 0,0,1); local wind=clamp(tonumber(climate.wind) or 0,0,1.4); local temp=tonumber(climate.temperature) or 14; local vis=clamp(tonumber(climate.visibility) or 1,0,1)
  local target={shelter=clamp(precip*.62+storm*.65+wind*.28,0,1),caution=clamp(storm*.72+(1-vis)*.5+(tonumber(surface.ice) or 0)*.35,0,1),activity=clamp(1-storm*.25-(1-vis)*.12,0,1),flyingActivity=clamp(1-storm*.65-wind*.42,0,1),waterActivity=clamp(.75+precip*.4,0,1.25),electricActivity=clamp(.78+storm*.45,0,1.3),iceActivity=clamp(.72+math.max(0,4-temp)*.06,0,1.3)}
  local f=1-math.exp(-math.max(0,tonumber(dt) or 0)/3); for k,v in pairs(target) do s[k]=(tonumber(s[k]) or v)+(v-(tonumber(s[k]) or v))*f end
end
function E.peek() return E.state end
function E.sample() local o={}; for k,v in pairs(E.state) do o[k]=v end; return o end
function E.affinity(kind) kind=tostring(kind or ''):lower(); local s=E.state; if kind:find('water',1,true) then return s.waterActivity elseif kind:find('electric',1,true) then return s.electricActivity elseif kind:find('ice',1,true) then return s.iceActivity elseif kind:find('flying',1,true) then return s.flyingActivity end; return s.activity end
return E
