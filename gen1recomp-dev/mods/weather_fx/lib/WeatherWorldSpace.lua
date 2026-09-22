local V = ...

-- Canonical continuous X/Z space for outdoor Weather FX simulation.
-- Voxel hosts re-base local coordinates whenever a connected map becomes the
-- render root. Neighbor offsets tell us how those local frames touch. This
-- module converts every current-map coordinate into one stable weather-world
-- coordinate so cloud/storm fields can physically straddle map boundaries.
local W={}
local origins={}
local currentMap=nil
local originX,originZ=0,0
local epoch=0
local serial=0
local continuous=true
local lastTransition="boot"
local neighborOrigins={}
-- Disconnected roots (interiors, warps, fly destinations, unsupported seams)
-- get their own far-separated coordinate island instead of destroying the
-- origins already learned for the overworld. This lets persistent storm/front
-- entities keep living in their original world space and resume exactly when
-- the player returns, while preventing unrelated maps from overlapping them.
local ISLAND_STRIDE=65536

local function mapIdOf(m) return m and m.id and tostring(m.id) or nil end
local function clear(t) for k in pairs(t) do t[k]=nil end end

function W.observeVoxelState(state)
  if type(state)~="table" then return false end
  local id=mapIdOf(state.map); if not id then return false end
  local changed=currentMap and id~=currentMap
  if not origins[id] then
    if currentMap and neighborOrigins[id] then
      origins[id]={neighborOrigins[id][1],neighborOrigins[id][2]}
      continuous=true;lastTransition="connected"
    elseif not currentMap then
      origins[id]={0,0}; continuous=true;lastTransition="initial"
    else
      -- No proved spatial seam (warp/fly/interior/new disconnected root). Keep
      -- every previously learned origin alive and place this root on a distant
      -- coordinate island. Older code erased `origins` here; StormCells then
      -- saw the epoch change and deleted every live front/cloud entity. A door
      -- or warp must change only the observer's space, never destroy weather.
      epoch=epoch+1
      origins[id]={epoch*ISLAND_STRIDE,0}
      continuous=false;lastTransition="disconnected"
    end
  elseif changed then
    continuous=neighborOrigins[id]~=nil
    lastTransition=continuous and "connected" or "known"
  end
  currentMap=id; originX,originZ=origins[id][1] or 0,origins[id][2] or 0

  clear(neighborOrigins)
  for _,nb in ipairs(state.neighbors or {}) do
    local nid=mapIdOf(nb and nb.map)
    if nid then
      local ox=tonumber(nb.ox) or tonumber(nb.offsetX) or 0
      local oz=tonumber(nb.oy) or tonumber(nb.offsetZ) or 0
      local nx,nz=originX+ox,originZ+oz
      origins[nid]=origins[nid] or {nx,nz}
      neighborOrigins[nid]={nx,nz}
    end
  end
  serial=serial+1
  return true
end

function W.toWorld(x,z,mapId)
  local ox,oz=originX,originZ
  if mapId and origins[tostring(mapId)] then ox,oz=origins[tostring(mapId)][1],origins[tostring(mapId)][2] end
  return (tonumber(x) or 0)+(tonumber(ox) or 0),(tonumber(z) or 0)+(tonumber(oz) or 0)
end
function W.toLocal(x,z,mapId)
  local ox,oz=originX,originZ
  if mapId and origins[tostring(mapId)] then ox,oz=origins[tostring(mapId)][1],origins[tostring(mapId)][2] end
  return (tonumber(x) or 0)-(tonumber(ox) or 0),(tonumber(z) or 0)-(tonumber(oz) or 0)
end
function W.currentOrigin() return originX,originZ,currentMap end
function W.epoch() return epoch end
function W.serial() return serial end
function W.continuous() return continuous end
function W.describe() return string.format("map=%s origin=(%.0f,%.0f) epoch=%d %s",tostring(currentMap or "-"),originX,originZ,epoch,lastTransition) end
function W.reset() origins={};neighborOrigins={};currentMap=nil;originX,originZ=0,0;epoch=0;serial=0;continuous=true;lastTransition="reset" end
return W
