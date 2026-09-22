local passed,failed=0,0
local function ck(v,m) if v then passed=passed+1 else failed=failed+1; if failed<=30 then io.write('FAIL '..m..'\n') end end end
local function finite(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local Types=assert(loadfile('lib/Types.lua'))(); local Wind=assert(loadfile('lib/WindEngine.lua'))()
local expected={PSYSTORM='psychic',SANDSTORM='sand',DUSTSTORM='sand',BLIZZARD='blizzard',THUNDERSNOW='blizzard',GALE='gale',STRONG_WINDS='gale',BRAWL_WIND='gale',FLOCKSTORM='gale',STORM='storm',DRAGONSTORM='storm',HEAVY_RAIN='storm',SNOW_LIGHT='snow',SLEET='snow',HAIL='snow',ASHFALL='ash',RAIN_HEAVY='rain'}
local dts={0,1/240,1/120,1/60,1/30,0.1,0.2,0.5,2.0}
local function run(id,seed)
  Wind._reset(seed); local d=Types.get(id); local state={id=id,ch=d.ch}
  local prev=Wind.state()
  for round=1,36 do for _,dt in ipairs(dts) do
    local s=Wind.update(dt,state)
    for _,k in ipairs({'angle','x','z','strength','envelope','advectX','advectZ','audio','pitch'}) do ck(finite(s[k]),id..' '..k..' finite') end
    ck(s.strength>=0,id..' nonnegative strength'); ck(s.envelope>=0 and s.envelope<=1.35,id..' envelope range'); ck(s.audio>=0 and s.audio<=1,id..' audio range'); ck(s.pitch>=0.82 and s.pitch<=1.08,id..' pitch range')
    ck(math.abs(math.sqrt(s.x*s.x+s.z*s.z)-s.strength)<1e-9,id..' vector magnitude matches strength')
    -- physical advection is capped over hitches; it must never teleport absurdly.
    local jump=math.sqrt((s.advectX-prev.advectX)^2+(s.advectZ-prev.advectZ)^2); ck(jump<0.25,id..' bounded advection step')
    prev={advectX=s.advectX,advectZ=s.advectZ}
  end end
  return Wind.state()
end
for _,id in ipairs(Types.ids()) do
  local gust=Types.channel(Types.get(id),'gust'); local key,p=Wind.profileFor(id,gust); ck(type(key)=='string' and type(p)=='table',id..' profile resolves')
  if expected[id] then ck(key==expected[id],id..' approved wind family '..expected[id]) end
  local a=run(id,123456); local b=run(id,123456)
  for _,k in ipairs({'profile','angle','x','z','strength','envelope','advectX','advectZ','audio','pitch','serial'}) do ck(a[k]==b[k],id..' deterministic reset '..k) end
end
print(string.format('8.1.18 wind stress: %d passed, %d failed',passed,failed))
os.exit(failed>0 and 1 or 0)
