local function fmt(v)
  if type(v)=='number' then
    if v~=v then return 'nan' end
    return string.format('%.12g',v)
  elseif type(v)=='boolean' then return v and 'true' or 'false'
  elseif v==nil then return 'nil' end
  return tostring(v)
end
local function line(...) local t={...}; for i=1,#t do t[i]=fmt(t[i]) end; io.write(table.concat(t,'|')..'\n') end
local function keys(t) local a={}; for k in pairs(t or {}) do a[#a+1]=k end; table.sort(a,function(x,y)return tostring(x)<tostring(y)end); return a end

local Types=assert(loadfile('lib/Types.lua'))()
for _,id in ipairs(Types.ids()) do
  local d=Types.get(id)
  line('TYPE',id,d.label,d.natural,d.weight,d.dayWeight,d.nightWeight,d.minMin,d.maxMin,d.battle,d.chipType,d.wet,d.frozen,d.sunny,d.sandy)
  for _,k in ipairs(keys(d.ch)) do line('CH',id,k,d.ch[k]) end
  for _,k in ipairs(keys(d.follows)) do line('FOLLOW',id,k,d.follows[k]) end
end

local cfg={celestial={latitude=35,verticalOrbit=true,pairedMoonOrbit=true},time={cycleMinutes=24},seasons={daysPerSeason=15}}
local TOD={hour=12,source='accelerated',elapsed=0}
local V={require=function(n) if n=='Config' then return {get=function() return cfg end} elseif n=='TimeOfDay' then return TOD end end}
local S=assert(loadfile('lib/CelestialSim.lua'))(V)
local days={0,15,45,90,135,180,225,270,315,364}
local hours={0,1,3,5,6,7,9,12,15,17,18,19,21,23}
for _,d in ipairs(days) do
  local rise,set=S.sunriseSunset(d); line('RISESET',d,rise,set,set-rise,S.solarDeclination(d))
  for _,h in ipairs(hours) do
    local x=S.sample(h,d); local a=x.sun; local m=x.moon
    line('CELEST',d,h,x.twilight,x.starVisibility,a.dx,a.dy,a.dz,a.alpha,a.horizonFraction,a.intensity,a.color[1],a.color[2],a.color[3],m.dx,m.dy,m.dz,m.alpha,m.horizonFraction,m.phase,m.illumination,m.intensity,m.phaseName,x.siderealAngle)
  end
end
for i=-40,40 do local alt=i/8; line('HORIZON',alt,S.discHorizonFraction(alt,3.24),S.sunHorizonHalo(alt,3.24),S.horizonFade(math.sin(alt*math.pi/180))) end
for d=0,60 do local phase,angle,illum,age,name=S.lunarPhase(0,d); line('LUNAR',d,phase,angle,illum,age,name,phase<0.5) end

local Wind=assert(loadfile('lib/WindEngine.lua'))()
for _,id in ipairs(Types.ids()) do
  local gust=Types.channel(Types.get(id),'gust'); local key,p=Wind.profileFor(id,gust)
  line('WPROF',id,key,p.speed[1],p.speed[2],p.floor,p.gust,p.turn,p.dir[1],p.dir[2],p.str[1],p.str[2],p.response,p.advect,p.sway)
  Wind._reset(424242); local st={id=id,ch=Types.get(id).ch}
  local dts={1/60,1/30,.1,.2,.5,2.0}
  for r=1,24 do Wind.update(dts[(r-1)%#dts+1],st); if r%6==0 then local w=Wind.state(); line('WSTATE',id,r,w.profile,w.angle,w.x,w.z,w.strength,w.envelope,w.advectX,w.advectZ,w.audio,w.pitch,w.serial) end end
end

local player={x=0,y=0}
local map={id='SEMANTIC_TOWN',width=128,height=128,warps={{x=0,y=0,warp=true}}}
local Scene={now={playerPosKnown=true,playerWorldX=0,playerWorldY=0},overworld=function() return {map=map} end}
local TOD2={pin='NIGHT',tod='NIGHT',isNight=function() return true end}
local V2={require=function(n) if n=='Scene' then return Scene elseif n=='TimeOfDay' then return TOD2 end end}
local B=assert(loadfile('lib/BuildingLight.lua'))(V2)
for _,d in ipairs({0,2,4,6,8,12,16,24,32,40,48,56,64}) do
  Scene.now.playerWorldX=d*16; Scene.now.playerWorldY=0
  for i=1,160 do B.update(.25) end
  local q=B.debugInfo(); line('BLIGHT',d,q.dist,q.factor,q.factorRaw,q.starMul,q.ambientMul,B.starScale(),B.nightAmbientScale())
end
