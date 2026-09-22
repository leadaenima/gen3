local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

local TOD={tod='NITE',pin=nil,isNight=function() return true end}
local map={id='TEST_TOWN',widthCells=64,heightCells=64,def={environment='TOWN',warps={{x=10,y=10,type='door'}}}}
local player={px=10*16,py=10*16}
local ow={map=map,player=player}
local Scene={now={isTown=true,playerPosKnown=true,playerWorldX=player.px,playerWorldY=player.py},overworld=function() return ow end}
local Atmos={_lastMap=nil}
local V={}
function V.require(name)
  local t={TimeOfDay=TOD,Scene=Scene,DramalessAtmos=Atmos}
  if t[name] then return t[name] end
  error('unexpected require '..tostring(name))
end
local B=assert(loadfile('lib/BuildingLight.lua'))(V)

-- Near a known door/building: stars dim, ambient stays brighter.
for _=1,24 do B.update(0.25) end
check((B.dist or 999)<=5,'building distance resolves from live map entrance metadata')
check(B.starScale()<0.50,'night stars dim near buildings')
check(B.nightAmbientScale()>0.85,'night ambient stays brighter near buildings')

-- Moving the PLAYER, not the camera, drives the distance field.
player.px,player.py=40*16,40*16
Scene.now.playerWorldX,Scene.now.playerWorldY=player.px,player.py
for _=1,40 do B.update(0.25) end
check((B.dist or 0)>=20,'player world movement reaches wild-distance threshold')
check(B.starScale()>0.90,'full stars return far from buildings')
check(B.nightAmbientScale()<0.60,'wild night ambient becomes darker')

-- A map change must not carry a near-door distance into metadata-free wilderness.
map={id='EMPTY_ROUTE',widthCells=64,heightCells=64,def={environment='ROUTE'}}
ow.map=map; ow.player=player
Scene.now.isTown=false; Scene.now.playerPosKnown=true
player.px,player.py=5*16,5*16
Scene.now.playerWorldX,Scene.now.playerWorldY=player.px,player.py
B.update(0.25)
check((B.dist or 0)>=20,'map change clears stale previous-map building distance')
for _=1,32 do B.update(0.25) end
check(B.starScale()>0.90,'metadata-free route settles to wild star brightness')

-- An unsampleable player frame must hold, not snap brightness.
local before=B.starScale()
Scene.now.playerPosKnown=false
ow.player=nil
for _=1,4 do B.update(0.25) end
check(math.abs(B.starScale()-before)<0.06,'unknown player position holds building-light state')

-- Day is neutral regardless of proximity.
TOD.tod='DAY'; TOD.isNight=function() return false end
B.update(0.25)
check(B.starScale()>0 and B.starScale()<=1,'daytime keeps live building-distance star multiplier ready for dusk')
check(B.nightAmbientScale()==1,'daytime ambient multiplier is neutral')

print(('building light: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
