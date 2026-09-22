local V = ...

local C={_serial=0,_owner="weather_fx.celestial2"}
local function req(n) local ok,m=pcall(V.require,n); if ok then return m end end

function C.update(dt,weather)
  local CE=req("CelestialEngine")
  if CE and CE.update then pcall(CE.update,dt,weather) end
  local NS=req("NightSky")
  if NS and NS.update then pcall(NS.update,dt) end
  C._serial=C._serial+1
end

function C.state()
  local CE=req("CelestialEngine"); if CE and CE.state then local ok,s=pcall(CE.state); if ok then return s end end
  return nil
end

function C.applySkyBands(bands,atmosphere)
  local CE=req("CelestialEngine")
  local out=bands
  if CE and CE.applySkyBands then local ok,v=pcall(CE.applySkyBands,bands); if ok and v then out=v end end
  if atmosphere and atmosphere.applyBands then local ok,v=pcall(atmosphere.applyBands,out); if ok and v then out=v end end
  return out
end

function C.projectBodies(w,h,edge)
  local Voxel3D=nil
  local DA=req("DramalessAtmos")
  if DA and DA.voxel3d then local ok,v=pcall(DA.voxel3d);if ok then Voxel3D=v end end
  local CB=req("CelestialBodies")
  if CB and CB.projectBoth then
    local ok,s,m=pcall(CB.projectBoth,w,h,edge,nil,Voxel3D)
    if ok then return s,m end
  end
  return nil,nil
end

function C.drawSky(w,h,edge,t)
  local NS=req("NightSky"); if not NS then return false end
  local vis=0; pcall(function() vis=NS.computeNightVisibility and NS.computeNightVisibility() or 0 end)
  if vis>.01 and NS.draw then local ok=pcall(NS.draw,w,h,edge,nil,t or 0); return ok end
  return false
end


-- Single-owner strict-3D background entry. Host adapters call this once per
-- scene instead of separately invoking deep-sky and body fallbacks.
function C.drawProjected(Voxel3D,t,w,h)
  local NS=req("NightSky"); if not NS then return false end
  local deep=false; local bodies=false
  if NS.drawProjectedWorld then local ok,v=pcall(NS.drawProjectedWorld,Voxel3D,t or 0,w,h); deep=ok and v==true end
  if NS.drawSunMoonProjectedWorld then local ok,v=pcall(NS.drawSunMoonProjectedWorld,Voxel3D,w,h); bodies=ok and v==true end
  C._lastProjected={deep=deep,bodies=bodies,serial=C._serial}
  return deep or bodies
end

function C.drawWorld(Voxel3D,t)
  local NS=req("NightSky"); if not NS then return false end
  local deep=false; local bodies=false
  if NS.drawWorld then local ok,v=pcall(NS.drawWorld,Voxel3D,t or 0); deep=ok and v==true end
  if NS.drawSunMoonWorld then local ok,v=pcall(NS.drawSunMoonWorld,Voxel3D); bodies=ok and v==true end
  return deep or bodies
end

function C.invalidate()
  local NS=req("NightSky"); if NS and NS.invalidate then pcall(NS.invalidate) end
  local CB=req("CelestialBodies"); if CB and CB.invalidate then pcall(CB.invalidate) end
end

function C.describe() return string.format("owner=%s serial=%d",C._owner,C._serial) end
return C
