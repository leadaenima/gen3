-- Headless submission proof for the strict projected sun/moon path.
local here=(arg and arg[0]) or ''
local root=here:gsub('tests/celestial_sun_submission_test.lua$','')
local current={
  hour=12,
  sun={dx=0,dy=1,dz=0,alpha=1,horizonFraction=1,discTransmission=1,altitudeDeg=90,color={1,.97,.9},kind='sun'},
  moon={dx=0,dy=-1,dz=0,alpha=0,horizonFraction=0,discTransmission=1,altitudeDeg=-90,illumination=1,phase=.5,color={.73,.8,1},kind='moon'},
}
local meshDraws=0
love={graphics={}}
local G=love.graphics
function G.newShader(_) return {send=function() end} end
function G.newMesh(_,_,_) return {setVertices=function() return true end,setDrawRange=function() end,release=function() end} end
function G.draw(_) meshDraws=meshDraws+1 end
function G.getShader() return nil end
function G.setShader(_) end
function G.getDepthMode() return 'lequal',true end
function G.setDepthMode(_,_) end
function G.getBlendMode() return 'alpha','alphamultiply' end
function G.setBlendMode(_,_) end
function G.getColor() return 1,1,1,1 end
function G.setColor(_,_,_,_) end

local mods={
  Constellations={STARS={}},
  CelestialBodies={bodies=function() return current end},
}
local V={require=function(name) return mods[name] end}
local chunk=assert(loadfile(root..'lib/NightSky.lua'))
local NS=chunk(V)
local vox={eye={0,0,0},focus={0,1,0},fovY=math.rad(65),size=function() return 320,288 end}
local ok=NS.drawSunMoonProjectedWorld(vox,320,288)
local _,proof=NS.projectedProof()
assert(ok==true,'strict projected sun did not submit')
assert(proof and (proof.sunVertices or 0)>0,'visible noon sun generated zero vertices')
assert(meshDraws>0,'visible noon sun generated no draw call')
local sunVerts=proof.sunVertices

current={
  hour=0,
  sun={dx=0,dy=-1,dz=0,alpha=0,horizonFraction=0,discTransmission=1,altitudeDeg=-90,color={1,.97,.9},kind='sun'},
  moon={dx=0,dy=1,dz=0,alpha=1,horizonFraction=1,discTransmission=1,altitudeDeg=90,illumination=1,phase=.5,color={.73,.8,1},kind='moon',apparentScale=1.18,lunarEclipse=0},
}
meshDraws=0
ok=NS.drawSunMoonProjectedWorld(vox,320,288)
_,proof=NS.projectedProof()
assert(ok==true,'strict projected moon did not submit')
assert(proof and (proof.moonVertices or 0)>0,'visible full moon generated zero vertices')
assert(meshDraws>0,'visible moon generated no draw call')
print(string.format('strict projected body submission: sun=%d moon=%d vertices',sunVerts,proof.moonVertices))
