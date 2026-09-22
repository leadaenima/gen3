local V = ...

-- Read-only behavioural hints for companion NPC/Pokémon mods. Weather FX does
-- not take ownership of actors; it publishes intents that another system may
-- choose to consume.
local B={}
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
function B.npc(climate,surface)
  climate=climate or {}; surface=surface or {}
  local storm=tonumber(climate.storm) or 0; local precip=tonumber(climate.precip) or 0; local wind=tonumber(climate.wind) or 0; local temp=tonumber(climate.temperature) or 14
  return {
    seekShelter=clamp(math.max(precip*.82,storm,wind*.62),0,1),
    avoidOpen=clamp(storm*.88+wind*.22,0,1),
    hurry=clamp(precip*.45+storm*.50+math.max(0,2-temp)*.025,0,1),
    caution=clamp((tonumber(surface.ice) or 0)*.9+(tonumber(surface.mud) or 0)*.3,0,1),
  }
end
local TYPE={
  WATER={rain=.45,humidity=.20}, ELECTRIC={storm=.55,rain=.10}, FIRE={heat=.35,rain=-.25,snow=-.30},
  ICE={cold=.55,snow=.45,heat=-.35}, FLYING={wind=.18,storm=-.30}, GRASS={rain=.18,humidity=.18,heat=-.10},
  GHOST={fog=.35,night=.12}, ROCK={sand=.28,rain=-.08}, GROUND={sand=.30,rain=-.10}, BUG={rain=-.12,heat=.08},
}
function B.pokemon(typeName,climate,extra)
  climate=climate or {}; extra=extra or {}; local p=TYPE[tostring(typeName or ''):upper()] or {}
  local temp=tonumber(climate.temperature) or 14; local score=1
  score=score+(p.rain or 0)*(tonumber(climate.precip) or 0)+(p.humidity or 0)*(tonumber(climate.humidity) or .4)+(p.storm or 0)*(tonumber(climate.storm) or 0)+(p.wind or 0)*(tonumber(climate.wind) or 0)
  score=score+(p.heat or 0)*clamp((temp-20)/15,0,1)+(p.cold or 0)*clamp((5-temp)/15,0,1)+(p.snow or 0)*(tonumber(extra.snow) or 0)+(p.fog or 0)*clamp(1-(tonumber(climate.visibility) or 1),0,1)+(p.sand or 0)*(tonumber(extra.sand) or 0)+(p.night or 0)*(tonumber(extra.night) or 0)
  return clamp(score,.35,1.75)
end
return B
