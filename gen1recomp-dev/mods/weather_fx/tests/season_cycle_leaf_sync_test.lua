-- Weather FX 4.35.32 accelerated season duration + 2D/3D leaf colour sync.
local ROOT=(arg and arg[0] and arg[0]:match('^(.*[/\\])')) or './tests/'
ROOT=ROOT:gsub('tests[/\\]$','')
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

local DAY_SECONDS=24*60 -- default cycleMinutes=24: one in-game day is 24 real minutes
local DAYS_PER_SEASON=15
local SEASON_SECONDS=DAY_SECONDS*DAYS_PER_SEASON

local currentValues={seasons='on',hemisphere='northern',seasonNotify='off',leafColor='seasonal'}
local cfg={
  time={source='cycle',cycleMinutes=24},
  seasons={enabled=true,notify=false,daysPerSeason=DAYS_PER_SEASON},
}
local TOD={source='cycle',elapsed=0}
local save={}
local mod={
  options={get=function(_,k) return currentValues[k] end},
  events={on=function() end},
  save={get=function(_,k,d) if save[k]==nil then return d end return save[k] end,
        set=function(_,k,v) save[k]=v end},
  log={info=function() end,warn=function() end},
  find=function() return nil end,
}
local Config={get=function() return cfg end}
local V={mod=mod}
local Seasons,Settings,Types
function V.require(name)
  if name=='Config' then return Config end
  if name=='TimeOfDay' then return TOD end
  if name=='Types' then return Types end
  if name=='Settings' then return Settings end
  if name=='Seasons' then return Seasons end
  error('unexpected require '..tostring(name),0)
end
Types=assert(loadfile(ROOT..'lib/Types.lua'))(V)
Settings=assert(loadfile(ROOT..'lib/Settings.lua'))(V)
Seasons=assert(loadfile(ROOT..'lib/Seasons.lua'))(V)
Seasons._bootstrapped=true
Seasons._lastPersisted='SPRING'

local function at(seconds, expected, label)
  TOD.elapsed=seconds
  Seasons.update(0,nil)
  check(Seasons.current()==expected,label..' -> '..expected)
end

-- Exactly 15 in-game days = 6 real hours per season at the default clock.
check(SEASON_SECONDS==6*60*60,'15 in-game days equal exactly six real hours at 24-minute days')
check(SEASON_SECONDS*4==24*60*60,'four accelerated seasons equal exactly 24 real hours')
at(0,'SPRING','cycle start')
at(14*DAY_SECONDS+DAY_SECONDS-0.001,'SPRING','last instant before day 15')
at(15*DAY_SECONDS,'SUMMER','day 15 boundary')
at(30*DAY_SECONDS,'AUTUMN','day 30 boundary')
at(45*DAY_SECONDS,'WINTER','day 45 boundary')
at(60*DAY_SECONDS,'SPRING','day 60 wraps full accelerated year')

-- Settings.leafColor is the common season authority used by both renderers.
local expected={
  SPRING='green', SUMMER='green', AUTUMN='orange', WINTER='brown'
}
for season,color in pairs(expected) do
  Seasons.id=season
  currentValues.leafColor='seasonal'
  check(Settings.leafColor()==color,season..' resolves shared seasonal leaf color '..color)
end

-- 2D/legacy leaf renderer calls the same authority and uses the same RGB tint
-- as the 3D WorldPrecip leaf pass.
local P=assert(loadfile(ROOT..'lib/Particles.lua'))(V)
local rgb={
  green={0.30,0.58,0.22}, orange={0.82,0.42,0.14}, brown={0.48,0.30,0.14}, yellow={0.78,0.68,0.18}
}
local function tintMatches(color)
  local r,g,b=P.leafTint(); local e=rgb[color]
  return math.abs(r-e[1])<1e-9 and math.abs(g-e[2])<1e-9 and math.abs(b-e[3])<1e-9
end
for season,color in pairs(expected) do
  Seasons.id=season
  currentValues.leafColor='seasonal'
  check(tintMatches(color),'2D leaf tint follows '..season..' through shared season authority')
end

-- Manual colour remains an explicit override for BOTH renderers.
Seasons.id='AUTUMN'; currentValues.leafColor='yellow'
check(Settings.leafColor()=='yellow','manual LEAF COLOR overrides seasonal mapping')
check(tintMatches('yellow'),'2D leaf renderer obeys same manual override as 3D renderer')

-- Static bridge guard: the 3D pass must still resolve Settings.leafColor(), not
-- a separate season timer or hard-coded seasonal table.
local f=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb'))
local wp=f:read('*a'); f:close()
check(wp:find('S.leafColor',1,true)~=nil,'3D leaf renderer still consumes shared Settings.leafColor authority')
local pf=assert(io.open(ROOT..'lib/Particles.lua','rb'))
local ps=pf:read('*a'); pf:close()
check(ps:find('S.leafColor',1,true)~=nil and ps:find('leafTint()',1,true)~=nil,
  '2D leaf renderer consumes shared Settings.leafColor authority')

io.write(string.format('season cycle/leaf sync: %d passed, %d failed\n',passed,failed))
os.exit(failed==0 and 0 or 1)
