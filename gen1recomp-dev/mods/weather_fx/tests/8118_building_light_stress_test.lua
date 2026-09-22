local passed,failed=0,0
local function ck(v,m) if v then passed=passed+1 else failed=failed+1; if failed<=30 then io.write('FAIL '..m..'\n') end end end
local function newLight(px,py)
  local map={id='TEST_TOWN',width=128,height=128,warps={{x=0,y=0,warp=true}}}
  local Scene={now={playerPosKnown=true,playerWorldX=px*16,playerWorldY=py*16},overworld=function() return {map=map} end}
  local TOD={pin='NIGHT',tod='NIGHT',isNight=function() return true end}
  local V={require=function(n) if n=='Scene' then return Scene elseif n=='TimeOfDay' then return TOD end end}
  return assert(loadfile('lib/BuildingLight.lua'))(V),Scene,map
end
local scales={}; local amb={}
for d=0,64 do
  local B=newLight(d,0); for i=1,160 do B.update(0.25) end
  local s=B.starScale(); local info=B.debugInfo(); scales[d]=s; amb[d]=info.ambientMul
  ck(s>=0.35 and s<=1.0,'star scale bounds d'..d); ck(info.factor>=0 and info.factor<=1,'factor bounds d'..d); ck(info.factorRaw>=0 and info.factorRaw<=1,'raw factor bounds d'..d)
  ck(B.nightAmbientScale()==info.ambientMul,'night ambient authority d'..d)
  if d>0 then ck(scales[d]+1e-10>=scales[d-1],'star brightness monotonic away from building d'..d) end
end
ck(math.abs(scales[0]-0.35)<1e-8,'near-building star floor is 0.35'); ck(math.abs(scales[64]-1.0)<1e-8,'far-wilderness star scale reaches 1.0')
-- Star-scale API clamps corrupt external values rather than leaking invalid alpha.
do local B=newLight(10,0); B.starMul=-9; ck(B.starScale()==0.35,'starScale clamps low'); B.starMul=9; ck(B.starScale()==1,'starScale clamps high'); B.starMul=0/0; ck(B.starScale()==1,'starScale rejects NaN') end
-- Temporal easing must not snap when crossing the whole pollution field.
do
  local B,S=newLight(64,0); for i=1,160 do B.update(0.25) end; local far=B.starScale();
  S.now.playerWorldX=0; B.update(0.25); local one=B.starScale(); ck(one<far and one>0.35,'approach begins gradually, not snap');
  local prev=one; for i=1,80 do B.update(0.25); local cur=B.starScale(); ck(cur<=prev+1e-12,'approach monotonic'); prev=cur end
  S.now.playerWorldX=64*16; local before=B.starScale(); B.update(0.25); local leave=B.starScale(); ck(leave>before and leave<1,'retreat begins gradually, not snap')
end
print(string.format('8.1.18 BuildingLight stress: %d passed, %d failed',passed,failed))
os.exit(failed>0 and 1 or 0)
