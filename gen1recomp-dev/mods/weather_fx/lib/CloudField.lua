local V = ...

-- Low-frequency volumetric-ready cloud state field. Rendering remains in the
-- proven CinematicAtmos path; this model supplies coherent density/thickness/
-- charge/transmission values shared by atmosphere, lightning and diagnostics.
-- 8.1.24: numeric cells remove transient "x:z" strings, static charge noise is
-- cached per cell, and the successful mesoscale module resolve is retained.
-- Cell count, equations, interpolation and cloud heights remain unchanged.
local C={}
local CELL=256
local RADIUS=3
local ACTIVE_CELLS=(RADIUS*2+1)^2
local cells={}; local centerX,centerZ=0,0; local elapsed=0; local serial=0
local mesoScratch={}
local current={density=.1,thickness=.2,charge=0,transmission=.9,baseY=120,topY=170,cells=0}
local _MF=nil
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function hash(x,z,s) local n=math.sin(x*91.7+z*137.3+s*31.1)*43758.5453; return n-math.floor(n) end
local function get(cx,cz)
  local row=cells[cx]; local c=row and row[cz]
  if c then return c end
  if not row then row={};cells[cx]=row end
  c={density=.05,thickness=.2,charge=0,cx=cx,cz=cz,_chargeNoise=.60+.40*hash(cx,cz,7),_seen=0}
  row[cz]=c; return c
end
local function meso()
  if not _MF then local ok,m=pcall(V.require,"MesoscaleField"); if ok and m and m.sampleInto then _MF=m end end
  return _MF
end
function C.update(dt,climate,x,z)
  dt=math.max(0,tonumber(dt) or 0); elapsed=elapsed+dt; serial=serial+1; climate=climate or {}
  centerX,centerZ=math.floor((tonumber(x) or 0)/CELL),math.floor((tonumber(z) or 0)/CELL)
  local sumD,sumT,sumQ,n=0,0,0,0
  -- 8.1.79: cache frame-invariant climate scalars once instead of re-parsing
  -- them in all 49 cells. Mesoscale overrides still win per cell exactly.
  local wind=tonumber(climate.wind) or .1
  local baseCloud=tonumber(climate.cloud) or .1
  local baseHumidity=tonumber(climate.humidity) or .4
  local baseStorm=tonumber(climate.storm) or 0
  local MF=meso(); if MF and MF.ready and not MF.ready() then MF=nil end
  local f=1-math.exp(-dt/4.5)
  for dz=-RADIUS,RADIUS do for dx=-RADIUS,RADIUS do
    local cx,cz=centerX+dx,centerZ+dz; local c=get(cx,cz); c._seen=serial
    local localClimate=climate
    if MF then localClimate=MF.sampleInto((cx+.5)*CELL,(cz+.5)*CELL,mesoScratch) or climate end
    local adv=elapsed*.012*wind
    local noise=hash(cx+adv,cz+adv*.61,3)
    local targetD=clamp((tonumber(localClimate.cloud) or baseCloud)*(.82+noise*.34),0,1)
    local targetT=clamp(.15+targetD*.72+(tonumber(localClimate.humidity) or baseHumidity)*.16,0,1)
    local targetQ=clamp((tonumber(localClimate.storm) or baseStorm)*targetD*c._chargeNoise,0,1)
    c.density=c.density+(targetD-c.density)*f; c.thickness=c.thickness+(targetT-c.thickness)*f; c.charge=c.charge+(targetQ-c.charge)*f
    c.transmission=clamp(math.exp(-c.density*(.75+c.thickness*1.4)),.02,1)
    if math.abs(dx)<=1 and math.abs(dz)<=1 then sumD=sumD+c.density;sumT=sumT+c.thickness;sumQ=sumQ+c.charge;n=n+1 end
  end end
  for cx,row in pairs(cells) do for cz,c in pairs(row) do if c._seen~=serial then row[cz]=nil end end;if next(row)==nil then cells[cx]=nil end end
  current.density=n>0 and sumD/n or 0; current.thickness=n>0 and sumT/n or 0; current.charge=n>0 and sumQ/n or 0
  current.transmission=clamp(math.exp(-current.density*(.75+current.thickness*1.4)),.02,1)
  current.baseY=(115+(1-baseHumidity)*42)*1.50
  current.topY=current.baseY+28+current.thickness*78; current.cells=ACTIVE_CELLS
end
function C.sampleAt(x,z)
  local cx,cz=math.floor((tonumber(x) or 0)/CELL),math.floor((tonumber(z) or 0)/CELL); local row=cells[cx]; local c=row and row[cz]
  return c or current
end
function C.peek() return current end
function C.sample() local o={}; for k,v in pairs(current) do o[k]=v end; return o end
function C.stats() local n=0; for _,row in pairs(cells) do for _ in pairs(row) do n=n+1 end end; return {cells=n,cellSize=CELL,radius=RADIUS,density=current.density,charge=current.charge,transmission=current.transmission} end
return C
