local passed,failed=0,0
local function check(v,n) if v then passed=passed+1 else failed=failed+1;print('FAIL '..n) end end
local quality='max';local optCalls=0
local settings={quality='max'}
local mod={id='weather_fx',options={get=function(_,k)optCalls=optCalls+1;return settings[k]end},log={warn=function()end}}
local cache={}
local V={mod=mod};function V.require(n)if cache[n]then return cache[n]end;if n=='Config'then cache[n]={get=function()return{quality='auto',maxParticles=9999999}end};return cache[n]end;local f=assert(loadfile('lib/'..n..'.lua'));local m=f(V);cache[n]=m;return m end
local S=V.require('Settings');S.beginFrame();local a=S.get('quality');local b=S.get('quality');check(a=='max'and b=='max'and optCalls==1,'same-frame settings cache removes duplicate option boundary calls')
local G=V.require('PerformanceGovernor');G.reset();for _=1,300 do G.update(.04)end;check(G.auto()==false and G.scale()==1 and G.particleScale()==1,'MAX ignores reactive/predictive trimming under severe frame pressure')
local Q=V.require('Quality');local q=Q.budget(1);check(q.worldPrecip==1 and q.worldRainCap==12000 and q.worldSnowCap==100000 and q.worldBlizzardCap==200000,'MAX preserves rain/snow/blizzard authored caps')
check(q.worldHailCap==45000 and q.worldSandCap==43200 and q.worldDebrisCap==3600 and q.worldAshCap==10800,'MAX preserves hail/sand/debris/ash authored caps')
local c=Q.celestial();check(c.starStep==1 and c.maxPlanets==9 and c.twinkle and c.meteors,'all quality API preserves complete celestial identity')
print(('MAX no-quality-loss performance contract: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
