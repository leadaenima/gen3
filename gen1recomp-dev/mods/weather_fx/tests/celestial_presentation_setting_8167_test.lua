local ROOT=(arg and arg[0] and arg[0]:match('^(.*[/\\])')) or 'tests/';ROOT=ROOT:gsub('tests[/\\]$','')
local pass,fail=0,0;local function ck(v,n)if v then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n)end end
local values={present='2d',celestialRendering='match'}
local mod={id='weather_fx',options={get=function(_,k)return values[k]end},events={on=function()end,once=function()end},hooks={wrap=function()end},content={screens={register=function()end}},log={warn=function()end,info=function()end}}
local Types={PINNED={}};function Types.get()return nil end;Types.byId={}
local V={mod=mod,require=function(name) if name=='Types' then return Types end error('optional '..tostring(name)) end}
local S=assert(loadfile(ROOT..'lib/Settings.lua'))(V)
ck(S.use3dCelestial()==false,'MATCH WEATHER follows forced 2D weather presentation')
values.celestialRendering='3d';ck(S.use3dCelestial()==true,'3D WORLD celestial remains enabled while weather rendering stays 2D')
ck(S.force2dPresent()==true,'3D celestial choice does not silently change 2D weather rendering')
values.present='3d';values.celestialRendering='2d';ck(S.use3dCelestial()==false,'2D SKY celestial can remain screen-space under 3D weather')
values.celestialRendering='match';ck(S.use3dCelestial()==true,'MATCH WEATHER follows forced 3D weather presentation')
print(('celestial presentation setting 8.1.67: %d passed, %d failed'):format(pass,fail));os.exit(fail==0 and 0 or 1)
