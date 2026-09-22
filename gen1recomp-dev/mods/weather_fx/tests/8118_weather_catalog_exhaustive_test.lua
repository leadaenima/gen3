local passed,failed=0,0
local function ck(v,m) if v then passed=passed+1 else failed=failed+1; io.write('FAIL '..m..'\n') end end
local function finite(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local Types=assert(loadfile('lib/Types.lua'))()
local ids=Types.ids(); local known={}; for _,id in ipairs(ids) do known[id]=true end
ck(#ids==29,'exact 29-weather catalogue retained after RAVE removal')
local allowedCh={rain=true,rainSpeed=true,rainAngle=true,rainLen=true,splash=true,snow=true,snowSpeed=true,snowDrift=true,hail=true,sand=true,ash=true,psy=true,debris=true,fog=true,fogSpeed=true,veil=true,dim=true,cool=true,warm=true,glare=true,gust=true,strike=true}
local seen={}
for _,id in ipairs(ids) do
  local d=Types.get(id); ck(type(d)=='table',id..' resolves'); ck(d.id==id,id..' id stable'); ck(not seen[id],id..' unique'); seen[id]=true
  ck(type(d.label)=='string' and #d.label>0,id..' label'); ck(finite(tonumber(d.minMin) or 0) and finite(tonumber(d.maxMin) or 0),id..' finite dwell')
  ck((tonumber(d.minMin) or 0)>=0 and (tonumber(d.maxMin) or 0)>=(tonumber(d.minMin) or 0),id..' dwell ordering')
  if d.natural~=false then ck((tonumber(d.weight) or 0)>0,id..' natural weather has schedule weight') end
  if d.weight~=nil then ck(finite(d.weight) and d.weight>=0,id..' weight finite/nonnegative') end
  if d.dayWeight~=nil then ck(finite(d.dayWeight) and d.dayWeight>=0,id..' dayWeight finite/nonnegative') end
  if d.nightWeight~=nil then ck(finite(d.nightWeight) and d.nightWeight>=0,id..' nightWeight finite/nonnegative') end
  if d.chipType~=nil then ck(type(d.chipType)=='string' and #d.chipType>0,id..' chipType valid') end
  if d.battle~=nil then ck(type(d.battle)=='string' and #d.battle>0,id..' battle id valid') end
  local ch=d.ch or {}; ck(type(ch)=='table',id..' channels table')
  for k,v in pairs(ch) do
    ck(allowedCh[k]==true,id..' channel name '..tostring(k)..' is known')
    ck(finite(v),id..' channel '..tostring(k)..' finite')
    if k~='rainAngle' then ck(v>=0,id..' channel '..tostring(k)..' nonnegative') end
    ck(Types.channel(d,k)==v,id..' channel accessor '..tostring(k))
  end
  ck(Types.hasLightning(id)==((tonumber(ch.strike) or 0)>0),id..' lightning authority equals strike channel')
  ck((Types.strikeRate(id) or 0)==(tonumber(ch.strike) or 0),id..' strikeRate exact')
  if type(d.follows)=='table' then for other,v in pairs(d.follows) do ck(v==true,id..' follows flag '..other); ck(known[other] or Types.get(other).id==other,id..' follows target resolves '..other) end end
end
ck(Types.get('__UNKNOWN__').id=='CLEAR','unknown weather degrades to CLEAR')
ck(Types.channel(nil,'rain')==0,'nil definition channel is zero')
ck(Types.channel({},'rain')==0,'missing channel is zero')
-- Specific user-approved authority invariants that have regressed before.
ck(Types.channel(Types.get('RAIN_LIGHT'),'rain')==0.90,'RAIN remains substantial steady rain')
ck(Types.channel(Types.get('RAIN_HEAVY'),'rain')==1.22,'HEAVY RAIN amount frozen')
ck(Types.channel(Types.get('HEAVY_RAIN'),'rain')==1.50,'PRIMAL rain amount frozen')
ck(Types.strikeRate('RAIN_LIGHT')==0 and Types.strikeRate('RAIN_HEAVY')==0,'ordinary rain remains non-electrical')
ck(Types.strikeRate('HEAVY_RAIN')==6 and Types.strikeRate('STORM')==18 and Types.strikeRate('PSYSTORM')==84,'severe lightning rates frozen')
ck(Types.channel(Types.get('SNOW_LIGHT'),'snow')==3.60 and Types.channel(Types.get('BLIZZARD'),'snow')==5.50,'snow density repair frozen')
ck(Types.channel(Types.get('HAIL'),'snow')==0 and Types.channel(Types.get('HAIL'),'hail')==0.9,'hail remains pellets only')
ck(Types.strikeRate('GALE')==0,'GALE remains non-electrical')
print(string.format('8.1.18 exhaustive weather catalogue: %d passed, %d failed',passed,failed))
os.exit(failed>0 and 1 or 0)
