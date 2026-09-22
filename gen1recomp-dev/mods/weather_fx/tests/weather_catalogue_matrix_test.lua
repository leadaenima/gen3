local ROOT=""
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1;io.write("FAIL "..name.."\n") end
end
local Types=assert(loadfile(ROOT.."lib/Types.lua"))()

local expected={
  CLEAR={rain=false,snow=false,hail=false,sand=false,ash=false,debris=false,fog=false,lightning=false},
  SUNNY={sun=true,lightning=false},
  HARSH_SUN={sun=true,lightning=false},
  RAIN_LIGHT={rain=true,lightning=false},
  RAIN_HEAVY={rain=true,lightning=false},
  HEAVY_RAIN={rain=true,lightning=true},
  STORM={rain=true,lightning=true},
  SNOW_LIGHT={snow=true,lightning=false},
  BLIZZARD={snow=true,lightning=false},
  HAIL={hail=true,lightning=false},
  SANDSTORM={sand=true,debris=true,lightning=false},
  STRONG_WINDS={debris=true,lightning=false},
  PLAIN_FRONT={debris=true,lightning=false},
  VERDANT_RAIN={rain=true,fog=true,lightning=false},
  BRAWL_WIND={debris=true,lightning=false},
  SMOG={fog=true,ash=true,lightning=false},
  DUSTSTORM={sand=true,debris=true,fog=true,lightning=false},
  FLOCKSTORM={debris=true,lightning=false},
  SWARM={debris=true,fog=true,lightning=false},
  HAUNTED_MIST={fog=true,debris=true,lightning=false},
  DRAGONSTORM={rain=true,snow=true,sand=true,debris=true,lightning=true},
  SLEET={rain=true,snow=true,hail=true,lightning=false},
  THUNDERSNOW={snow=true,lightning=true},
  ASHFALL={ash=true,fog=true,lightning=false},
  HEATWAVE={sun=true,lightning=false},
  GALE={rain=true,debris=true,lightning=false},
  PSYSTORM={rain=true,debris=true,lightning=true},
  MIST={fog=true,lightning=false},
  FOG={fog=true,lightning=false},
}

local ids=Types.ids()
check(#ids==29,"catalogue contains exactly 29 weather definitions after RAVE removal")
local seen={}
for _,id in ipairs(ids) do seen[id]=(seen[id] or 0)+1 end
for id in pairs(expected) do check(seen[id]==1,id.." exists exactly once") end

local function pos(id,key) return Types.channel(Types.get(id),key)>0.001 end
for id,e in pairs(expected) do
  local def=Types.get(id)
  if e.rain~=nil then check(pos(id,"rain")==e.rain,id.." rain family") end
  if e.snow~=nil then check(pos(id,"snow")==e.snow,id.." snow family") end
  if e.hail~=nil then check(pos(id,"hail")==e.hail,id.." hail family") end
  if e.sand~=nil then check(pos(id,"sand")==e.sand,id.." sand family") end
  if e.ash~=nil then check(pos(id,"ash")==e.ash,id.." ash family") end
  if e.debris~=nil then check(pos(id,"debris")==e.debris,id.." debris family") end
  if e.fog~=nil then check((pos(id,"fog") or pos(id,"veil"))==e.fog,id.." fog/veil family") end
  check(Types.hasLightning(id)==e.lightning,id.." lightning/thunder authority")
  if e.sun then check((def.sunny==true) or Types.channel(def,"warm")>0 or Types.channel(def,"glare")>0,id.." solar profile") end
end

local light=Types.get("RAIN_LIGHT").ch
local heavy=Types.get("RAIN_HEAVY").ch
local primal=Types.get("HEAVY_RAIN").ch
local storm=Types.get("STORM").ch
check(light.rain>=0.85,"normal RAIN has a visibly substantial authored rain demand")
check(heavy.rain>light.rain,"HEAVY RAIN density exceeds normal RAIN")
check(primal.rain>heavy.rain,"PRIMAL HEAVY RAIN density exceeds HEAVY RAIN")
check(storm.rain>light.rain,"STORM density exceeds normal RAIN")
check((light.rainSpeed or 0)<(heavy.rainSpeed or 0) and (heavy.rainSpeed or 0)<(primal.rainSpeed or 0),"rain speed hierarchy is normal < heavy < primal")
check(not Types.hasLightning("RAIN_LIGHT") and not Types.hasLightning("RAIN_HEAVY"),"plain rain tiers never invent lightning")
check(Types.hasLightning("HEAVY_RAIN") and Types.strikeRate("HEAVY_RAIN")==6,"Primal Heavy Rain explicitly owns lightning/thunder")
check(Types.hasLightning("STORM") and Types.strikeRate("STORM")>Types.strikeRate("HEAVY_RAIN"),"Storm remains electrically stronger than primal rain")
check(not Types.hasLightning("GALE"),"Gale remains non-electrical")

io.write(string.format("weather catalogue matrix: %d passed, %d failed\n",passed,failed))
os.exit(failed==0 and 0 or 1)
