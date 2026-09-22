local root=(arg[0]:match('(.*/)') or './'):gsub('tests/$','')
local cfg={celestial={verticalOrbit=true,pairedMoonOrbit=true,events=false},time={cycleMinutes=24},seasons={daysPerSeason=15}}
local V={require=function(name)
  if name=='Config' then return {get=function() return cfg end} end
  if name=='TimeOfDay' then return {hour=12,elapsed=0,source='internal'} end
  error(name)
end}
local Sim=assert(loadfile(root..'lib/CelestialSim.lua'))(V)
local day=80
local noon=Sim.sample(12,day)
local rise=noon.sunset
local nightLen=(24-noon.sunset)+noon.sunrise
local function vis(progress) return Sim.sample((rise+nightLen*progress)%24,day).starVisibility end
local v0=vis(0); local vEarly=vis(.02); local vQ=vis(.25); local vHalf=vis(.50); local vLate=vis(.90); local vEnd=vis(1.0)
local n,f=0,0
local function ck(x,m) n=n+1;if not x then f=f+1;io.stderr:write('FAIL '..m..'\n') end end
ck(v0<=.001,'moonrise begins from zero/near-zero alpha')
ck(vEarly>v0,'stars begin appearing immediately after moonrise')
ck(vQ>.995,'stars reach full brightness at quarter-night')
ck(vHalf<vQ and vHalf>.65,'stars remain visible but soften after quarter-night')
ck(vLate>0 and vLate<vHalf,'stars fade toward moonset/sunrise')
ck(vEnd<=.001,'stars are gone at end of night')
io.write(string.format('moonrise star visibility: %d passed, %d failed\n',n-f,f))
os.exit(f==0 and 0 or 1)
