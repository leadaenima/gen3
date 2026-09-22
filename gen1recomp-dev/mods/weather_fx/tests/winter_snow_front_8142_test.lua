-- Weather FX 8.1.42 reachable snow-front family regression.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local V={}
local Types=assert(loadfile(ROOT..'lib/Types.lua'))(V)
local cells={}
local StormCells={cells=function() return cells end}
function V.require(n) if n=='Types' then return Types elseif n=='StormCells' then return StormCells end error(n,0) end
local D=assert(loadfile(ROOT..'lib/DistantWeather.lua'))(V)
local function one(weather)
  cells={{id=1,weather=weather,x=900,z=0,rx=620,rz=1500,age=210,life=600,vx=1,vz=0,charge=.2,flash=0,strikeSerial=0}}
  D.reset();D.update(.016,0,0);local q=D.sample();return q[1]
end
local snow=one('SNOW_LIGHT');ck(snow and snow.kind=='snow','ordinary snow front remains a dedicated snow precipitation family')
local bliz=one('BLIZZARD');ck(bliz and bliz.kind=='blizzard','BLIZZARD becomes dedicated wind-driven snowstorm front morphology')
ck(bliz and (bliz.gust or 0)>.9 and (bliz.veil or 0)>.2,'blizzard descriptor carries severe wind/whiteout authority')
local ts=one('THUNDERSNOW');ck(ts and ts.kind=='blizzard' and (ts.lightning or 0)>.02,'THUNDERSNOW uses blizzard precipitation plus real remote lightning authority')
local rain=one('STORM');ck(rain and rain.kind=='rain','rain/thunder front remains separate from snowstorm presentation')
local Seasons={id='WINTER'}
function Seasons.current() return Seasons.id end
function V.require(n) if n=='Types' then return Types elseif n=='StormCells' then return StormCells elseif n=='Settings' then return {is=function() return false end} end error(n,0) end
-- Catalogue proof: winter storm families are natural schedulable weathers, not
-- debug-only effects, and have spatial snow channels the StormCells engine owns.
local b,t=Types.get('BLIZZARD'),Types.get('THUNDERSNOW')
ck(b and b.natural~=false and (b.ch.snow or 0)>4 and (b.ch.gust or 0)>.8,'blizzard is a naturally schedulable spatial snowstorm')
ck(t and t.natural~=false and (t.ch.snow or 0)>4 and (t.ch.strike or 0)>0,'thundersnow is a naturally schedulable electrical snowstorm')
print(string.format('winter snow fronts 8.1.42: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
