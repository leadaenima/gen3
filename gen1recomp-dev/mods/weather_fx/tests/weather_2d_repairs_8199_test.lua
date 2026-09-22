-- Weather FX 8.1.99: regressions for 2D snow startup, 2D celestial camera
-- anchoring, and the 2D-weather-only 2D/3D lightning bolt selector.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end

local function slurp(rel)
  local f=assert(io.open(ROOT..rel,'rb'));local s=f:read('*a');f:close();return s
end

-- Player-facing setting and semantics.
do
  local values={present='2d',weather2dLightning='2d'}
  local mod={id='weather_fx',options={get=function(_,k)return values[k]end},events={on=function()end,once=function()end},hooks={wrap=function()end},content={screens={register=function()end}},log={warn=function()end,info=function()end}}
  local Types={PINNED={},byId={}};function Types.get()return nil end
  local V={mod=mod,require=function(n)if n=='Types'then return Types end error(n)end}
  local S=assert(loadfile(ROOT..'lib/Settings.lua'))(V)
  local row=S.row('weather2dLightning')
  ck(row and row.label=='2D WEATHER LIGHTNING','2D-weather lightning selector is exposed')
  ck(row and row.default=='2d' and row.choices[1][2]=='2d' and row.choices[2][2]=='3d','selector defaults to existing 2D bolts and offers 3D bolts')
  local mode=S.weather2dLightningMode and S.weather2dLightningMode() or nil
  local wants=S.wants3dLightningWith2dWeather and S.wants3dLightningWith2dWeather() or false
  ck(mode=='2d' and not wants,'default 2D weather keeps existing 2D lightning')
  values.weather2dLightning='3d'
  mode=S.weather2dLightningMode and S.weather2dLightningMode() or nil
  wants=S.wants3dLightningWith2dWeather and S.wants3dLightningWith2dWeather() or false
  ck(mode=='3d' and wants,'3D BOLTS opt-in is active only with forced 2D weather')
  values.present='3d'
  wants=S.wants3dLightningWith2dWeather and S.wants3dLightningWith2dWeather() or false
  ck(not wants,'2D-weather bolt override does not alter normal 3D weather')
end

-- Fresh 2D snow must begin phase-distributed through the visible fall path,
-- while recycled flakes must still enter from above.
do
  math.randomseed(8199)
  local V={require=function() error('optional') end}
  local P=assert(loadfile(ROOT..'lib/Particles.lua'))(V)
  P.setRect(160,144,1)
  P.update(0.001,{snow=1,snowSpeed=1,snowDrift=.55},{rain=0,snow=256,grain=0,splash=0},0,0,0,false)
  local snow
  for i=1,60 do local n,v=debug.getupvalue(P.update,i);if not n then break end;if n=='snow'then snow=v;break end end
  ck(snow and snow.n==256 and snow.active==256,'2D snow startup fills the requested pool')
  local lower=0
  if snow then for i=1,snow.n do if (snow.y[i] or -999)>36 then lower=lower+1 end end end
  ck(lower>50,'fresh 2D snow is distributed through normal visible lifetimes instead of one top strip')
  if snow then snow.y[1]=(snow.pathH[1] or 100)+10 end
  P.update(0.01,{snow=1,snowSpeed=1,snowDrift=.55},{rain=0,snow=256,grain=0,splash=0},0,0,0,false)
  ck(snow and snow.y[1]<0,'recycled 2D snow still re-enters naturally from above')
end

-- A fixed world direction must respond to live camera orientation even when a
-- host also exposes a bogus/static eye->focus player anchor.
do
  local cache={};local V={}
  function V.require(n) if cache[n] then return cache[n] end;local m=assert(loadfile(ROOT..'lib/'..n..'.lua'))(V);cache[n]=m;return m end
  local N=V.require('NightSky')
  local ya,yb=math.rad(-20),math.rad(20)
  local a={eye={0,40,0},focus={0,0,0},camera={forward={math.sin(ya),0,math.cos(ya)},fovY=math.rad(65)}}
  local b={eye={0,40,0},focus={0,0,0},camera={forward={math.sin(yb),0,math.cos(yb)},fovY=math.rad(65)}}
  local ax,ay=N.projectDirection(a,0,.15,1,320,288)
  local bx,by=N.projectDirection(b,0,.15,1,320,288)
  ck(ax and bx and math.abs(ax-bx)>40,'2D celestial projection follows live camera yaw instead of static player focus')
  ck(ay and by,'camera-aware 2D sun/moon projection remains visible for both headings')
end

-- Mixed renderer wiring: selecting 3D bolts under 2D weather must wake only
-- world lightning, not full 3D weather.
do
  local draw=slurp('lib/Draw.lua')
  local da=slurp('lib/DramalessAtmos.lua')
  local cin=slurp('lib/voxel_atmos/CinematicAtmos.lua')
  ck(draw:find('Settings.wants3dLightningWith2dWeather',1,true)~=nil,'2D compositor consults the mixed lightning choice')
  ck(da:find('local function lightning3dWanted()',1,true)~=nil and da:find('policy.lightning3d=lightningWeather',1,true)~=nil,'voxel bridge carries independent lightning-only policy')
  ck(cin:find('local lightning3d=weather3d or (policy and policy.lightning3d==true)',1,true)~=nil,'3D atmosphere separates lightning ownership from full weather ownership')
  ck(cin:find('if lightning3d then',1,true)~=nil,'world-lightning pass can run without enabling 3D precipitation')
end

print(('8.1.99 2D weather repair regression: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
