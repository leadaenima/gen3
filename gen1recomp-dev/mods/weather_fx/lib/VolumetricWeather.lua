local V = ...
-- Weather FX 8.1.47: render-equivalent analytic volume summary.
--
-- The production voxel renderer never consumes the historical 5x5x3 table;
-- it consumes only the aggregate cloud/precipitation/transmission descriptors.
-- Keep those equations exact while avoiding 75 persistent Lua cell tables and
-- the charge/table writes on ordinary gameplay frames. The public cells() API
-- remains available: the first consumer opts the detailed table back in, after
-- which it is refreshed exactly as before.
local W={}
local NX,NZ,NY=5,5,3; local CELL=160
local cells={}
local state={cloudVolume=0,precipVolume=0,farPrecipScale=1,shadowScale=1,lightTransmission=1,cells=NX*NZ*NY,materializedCells=0}
local mesoScratch={}
local wantCells=false
local last={x=0,z=0,climate={},cloud={}}
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function hash(x,z,y) local n=math.sin(x*37.1+z*91.7+y*17.3)*43758.5453; return n-math.floor(n) end
local function copyScalars(src,dst)
  for k in pairs(dst) do dst[k]=nil end
  for k,v in pairs(src or {}) do if type(v)=="number" or type(v)=="boolean" or type(v)=="string" then dst[k]=v end end
end
local function mesoModule()
  local ok,m=pcall(V.require,"MesoscaleField")
  if ok and m and m.sampleInto and (not m.ready or m.ready()) then return m end
end
local function compute(x,z,climate,cloud,materialize)
  climate=climate or {}; cloud=cloud or {}
  local ix0,iz0=math.floor((tonumber(x) or 0)/CELL),math.floor((tonumber(z) or 0)/CELL)
  local MF=mesoModule()
  local n,sumC,sumP=0,0,0
  for iz=1,NZ do for ix=1,NX do
    local dx=ix-math.ceil(NX/2); local dz=iz-math.ceil(NZ/2)
    local wx,wz=(ix0+dx+.5)*CELL,(iz0+dz+.5)*CELL
    local localClimate=climate
    if MF then localClimate=MF.sampleInto(wx,wz,mesoScratch) end
    local cloudBase=tonumber(localClimate.cloud) or tonumber(cloud.density) or tonumber(climate.cloud) or 0
    local precipBase=tonumber(localClimate.precip) or tonumber(climate.precip) or 0
    local chargeBase=materialize and (tonumber(localClimate.storm) or tonumber(cloud.charge) or tonumber(climate.storm) or 0) or 0
    for iy=1,NY do
      n=n+1
      local noise=.82+.30*hash(ix0+dx,iz0+dz,iy); local altitude=(iy-1)/(NY-1)
      local qCloud=clamp(cloudBase*noise*(1-.18*math.abs(altitude-.5)),0,1)
      local qPrecip=clamp(precipBase*(qCloud^.72)*(1-altitude*.22),0,1)
      sumC=sumC+qCloud; sumP=sumP+qPrecip
      if materialize then
        local q=cells[n] or {}; cells[n]=q
        q.x,q.z,q.layer=wx,wz,iy
        q.cloud,q.precip=qCloud,qPrecip
        q.charge=clamp(chargeBase*qCloud*(.6+.4*hash(ix0+dx,iz0+dz,iy+9)),0,1)
      end
    end
  end end
  if materialize then for i=n+1,#cells do cells[i]=nil end end
  state.cloudVolume=sumC/math.max(1,n)
  state.precipVolume=sumP/math.max(1,n)
  state.farPrecipScale=clamp(.72+state.precipVolume*.55,.72,1.25)
  state.shadowScale=clamp(.82+state.cloudVolume*.35,.82,1.18)
  state.lightTransmission=clamp(math.exp(-state.cloudVolume*1.35),.04,1)
  state.cells=n
  state.materializedCells=materialize and n or 0
end
function W.update(dt,x,z,climate,cloud,world)
  last.x,last.z=tonumber(x) or 0,tonumber(z) or 0
  copyScalars(climate,last.climate); copyScalars(cloud,last.cloud)
  compute(last.x,last.z,last.climate,last.cloud,wantCells)
end
function W.peek() return state end
function W.sample() local o={}; for k,v in pairs(state) do o[k]=v end; return o end
function W.cells()
  if not wantCells then
    wantCells=true
    compute(last.x,last.z,last.climate,last.cloud,true)
  end
  return cells
end
function W.stats() return W.sample() end
return W
