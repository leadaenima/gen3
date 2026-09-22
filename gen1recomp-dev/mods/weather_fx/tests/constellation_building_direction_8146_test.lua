-- Weather FX 8.1.46 constellation/building-direction regression.
local pass,fail=0,0
local function check(v,n) if v then pass=pass+1 else fail=fail+1;print((v and 'PASS ' or 'FAIL ')..n) end end
-- A metadata-free town with one real visible voxel building. This specifically
-- catches the retired fake town-centre/corner emitters that could invert the
-- player's apparent approach/retreat relative to the building on screen.
local map={id='REAL_BUILDING_TOWN',widthCells=64,heightCells=64,def={environment='TOWN'}}
function map:cellTile(cx,cz) if cx>=7 and cx<=11 and cz>=7 and cz<=11 then return 1 end return 0 end
function map:isWaterCell() return false end
local TS={forMap=function() return {[0]={class='ground',h=0},[1]={class='building',art='volume',h=24}} end}
local F=assert(loadfile('lib/FlatWorldInteraction.lua'))({})
F.observeVoxel({map=map,neighbors={}},nil,TS)
check(F.ready(),'voxel interaction field is ready')
local nearD=F.nearestBuiltDistance(9*16+8,9*16+8,48)
local midD=F.nearestBuiltDistance(20*16+8,9*16+8,48)
local farD=F.nearestBuiltDistance(55*16+8,55*16+8,48)
check(nearD and nearD<1,'visible building footprint resolves as near')
check(midD and midD>nearD,'physical distance increases while walking away from visible building')
check(farD==nil or farD>midD,'far wilderness never becomes physically nearer than mid-distance')
local px,py=9,9
local Scene={now={isTown=true,playerPosKnown=true,playerWorldX=px*16,playerWorldY=py*16},overworld=function() return {map=map} end}
local TOD={tod='NITE',isNight=function() return true end}
local Atmos={_lastMap=nil,_lastNeighbors=nil}
local V={require=function(n)
  if n=='Scene' then return Scene elseif n=='TimeOfDay' then return TOD elseif n=='DramalessAtmos' then return Atmos elseif n=='FlatWorldInteraction' then return F end
  error('unexpected require '..tostring(n),0)
end}
local B=assert(loadfile('lib/BuildingLight.lua'))(V)
local function settle(x,y)
  Scene.now.playerWorldX,Scene.now.playerWorldY=x*16,y*16
  for _=1,120 do B.update(.25) end
  return B.constellationScale(),B.debugInfo().dist
end
local near,nd=settle(9,9)
local mid,md=settle(20,9)
local far,fd=settle(55,55)
check(nd<md and md<=fd,'building-light authority distance increases near -> mid -> far')
check(near<mid and mid<far,'constellation brightness strictly increases while moving away from the building')
check(near>=.35 and far>.99,'constellation multiplier spans near-building dimming to unobstructed maximum')
-- A metadata-free town is no longer assigned invisible centre/corner lights.
local list=B._testNeighborhoodBuildings(map)
check(type(list)=='table' and #list==0,'metadata-free town no longer invents fake light emitters')
local src=assert(io.open('lib/NightSky.lua','rb')):read('*a')
check(src:find('BL.constellationScale',1,true)~=nil,'NightSky uses the explicit monotonic constellation building-light seam')
print(string.format('8.1.46 constellation building direction: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
