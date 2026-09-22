local V = ...
-- 8.1.47: analytic compatibility probe.
-- The old runtime maintained 49 pseudo-occlusion cells continuously even though
-- no Weather FX voxel renderer sampled them. Preserve the public sample formula
-- on demand from the live UnifiedLighting state, with zero resident grid.
local L={}; local CELL=96; local serial=0; local manual=nil
local out={ambient=.7,diffuse=.7,specular=0}
local function hash(x,z) local n=math.sin(x*81.7+z*173.1)*43758.5453; return n-math.floor(n) end
local function lighting()
  if manual then return manual end
  local ok,U=pcall(V.require,"UnifiedLighting")
  if ok and U then return U.peek and U.peek() or (U.sample and U.sample()) end
  return nil
end
function L.update(dt,x,z,q) manual=q or manual; serial=serial+1 end
function L.sampleAt(x,z)
  local cx,cz=math.floor((tonumber(x) or 0)/CELL),math.floor((tonumber(z) or 0)/CELL)
  local q=lighting() or {}
  local ambient,diffuse,specular=tonumber(q.finalAmbient) or .7,tonumber(q.finalDiffuse) or .7,tonumber(q.specular) or 0
  out.ambient=ambient*(.86+.14*hash(cx,cz))
  out.diffuse=diffuse*(.90+.10*hash(cx+9,cz-3))
  out.specular=specular
  return out
end
function L.stats() return {cells=0,virtualCells=49,cellSize=CELL,radius=3,serial=serial,mode="analytic-on-demand"} end
return L
