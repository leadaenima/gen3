local passed,failed=0,0
local function check(v,n) if v then passed=passed+1 else failed=failed+1;print('FAIL '..n) end end
local values={cloudHeight='raised'}
local mod={id='weather_fx',options={get=function(_,k)return values[k] end,define=function()return true end},events={on=function()end},log={info=function()end,warn=function()end},save={set=function()end,get=function(_,_,d)return d end}}
local Types={DEFAULT='CLEAR',PINNED={}}; Types.byId={CLEAR={id='CLEAR',ch={},sunny=true},STORM={id='STORM',ch={rain=1,strike=10,gust=1}}}; function Types.get(id)return Types.byId[id] or Types.byId.CLEAR end
local modules={Types=Types,WindEngine={peek=function()return{x=1,z=0,strength=.5}end}}
local V={mod=mod}; function V.require(name) if modules[name] then return modules[name] end local p='lib/'..name..'.lua'; local f=loadfile(p); if not f then error(name) end local m=f(V);modules[name]=m;return m end
local S=V.require('Settings'); modules.Settings=S
check(S.cloudHeightScale()==1.5,'RAISED is 150 percent')
values.cloudHeight='original';check(S.cloudHeightScale()==1.0,'ORIGINAL is exact historical height')
local SC=V.require('StormCells');modules.StormCells=SC
check(SC.enabled()==true,'storm cells start enabled')
SC.setEnabled(false);check(SC.enabled()==false,'front master disables storm cells')
local q=SC.sampleAt(0,0,'STORM');check(q.precip==0 and q.cloud==0 and q.weather==nil and q.stage=='disabled','disabled storm cells cannot leave localized precipitation/clouds')
SC.setEnabled(true);check(SC.enabled()==true,'front master can re-enable fresh storm cells')
local T=V.require('Tornado');modules.Tornado=T
values.cloudHeight='raised';check(math.abs(T.cloudBase()-183)<.001,'raised tornado fallback reaches 183')
values.cloudHeight='original';check(math.abs(T.cloudBase()-122)<.001,'original tornado fallback returns to 122')
print(('8.1.23 spatial fallback: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
