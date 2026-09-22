local V = ...

local Surface = {}
local ChunkSim = V.require("ChunkSim")
local MaterialSystem = V.require("MaterialSystem")

local sim = ChunkSim.new({chunkSize=256,activeRadius=2,sleepRadius=5})
local tileSize=16
local lastX,lastZ=0,0
local accum=0
local compactAccum=0
local _FlatWorld=nil
local MATERIAL_IDS={soil=1,grass=2,stone=3,pavement=4,roof=5,wood=6,metal=7,sand=8,water=9,ice=10}
local ID_MATERIAL={}; for k,v in pairs(MATERIAL_IDS) do ID_MATERIAL[v]=k end

local function unpackChunk(chunk)
  local packed=chunk and chunk.data and chunk.data.__packed
  if type(packed)~="table" then return end
  chunk.data={}
  local stride=12
  for i=1,#packed,stride do
    local c={x=packed[i],z=packed[i+1],wet=packed[i+2],snow=packed[i+3],leaves=packed[i+4],scorch=packed[i+5],ice=packed[i+6],temp=packed[i+7],puddle=packed[i+8],mud=packed[i+9],frost=packed[i+10],material=ID_MATERIAL[packed[i+11]] or "soil"}
    chunk.data[tostring(c.x)..":"..tostring(c.z)]=c
  end
end

local function packChunk(chunk)
  if not chunk or chunk.active or not chunk.data or chunk.data.__packed then return 0 end
  local flat={}; local n=0
  for k,c in pairs(chunk.data) do
    if k~="__packed" and type(c)=="table" then
      n=n+1; local b=#flat
      flat[b+1],flat[b+2]=c.x,c.z; flat[b+3],flat[b+4],flat[b+5]=c.wet or 0,c.snow or 0,c.leaves or 0
      flat[b+6],flat[b+7],flat[b+8]=c.scorch or 0,c.ice or 0,c.temp or 0
      flat[b+9],flat[b+10],flat[b+11]=c.puddle or 0,c.mud or 0,c.frost or 0
      flat[b+12]=MATERIAL_IDS[MaterialSystem.normalize(c.material)] or 1
    end
  end
  if n>0 then chunk.data={__packed=flat} end
  return n
end

local function clamp01(v) if v<0 then return 0 elseif v>1 then return 1 end return v end
local function flatWorld()
  if _FlatWorld~=nil then return _FlatWorld or nil end
  local ok,m=pcall(V.require,"FlatWorldInteraction");_FlatWorld=(ok and m) or false;return _FlatWorld or nil
end
local function exposureAt(x,z)
  local F=flatWorld()
  if F and F.ready and F.ready() then
    if F.waterAt and F.waterAt(x,z) then return 0,true end
    if F.exposureAt then return clamp01(F.exposureAt(x,z)),false end
  end
  return 1,false
end
local function cellKey(x,z)
  local lx=math.floor((tonumber(x) or 0)/tileSize)
  local lz=math.floor((tonumber(z) or 0)/tileSize)
  return tostring(lx)..":"..tostring(lz),lx,lz
end

local function getCell(x,z,create)
  local chunk=sim:at(x,z,create)
  if not chunk then return nil end
  if chunk.data and chunk.data.__packed then unpackChunk(chunk) end
  local k,lx,lz=cellKey(x,z); local c=chunk.data[k]
  if not c and create~=false then c={x=lx,z=lz,wet=0,snow=0,leaves=0,scorch=0,ice=0,temp=0,puddle=0,mud=0,frost=0,material="soil"}; chunk.data[k]=c end
  return c,chunk,k
end

function Surface.depositWet(x,z,amount,material)
  local exposure,water=exposureAt(x,z)
  if water or exposure<=.06 then return false end
  local c=getCell(x,z,true); if not c then return false end
  if material then c.material=MaterialSystem.normalize(material) end
  local p=MaterialSystem.profile(c.material)
  local a=(tonumber(amount) or .08)*(1-(p.drainage or 0)*.28)*exposure
  c.wet=clamp01((c.wet or 0)+a)
  if c.temp and c.temp<0 then c.ice=clamp01((c.ice or 0)+a*.35) end
  return true
end

function Surface.depositSnow(x,z,amount,material)
  local exposure,water=exposureAt(x,z)
  if water then return false end
  local c=getCell(x,z,true); if not c then return false end
  if material then c.material=MaterialSystem.normalize(material) end
  local p=MaterialSystem.profile(c.material)
  local canopyFloor=.34
  local retained=math.max(canopyFloor,exposure)
  c.snow=clamp01((c.snow or 0)+(tonumber(amount) or .04)*(p.snowRetention or 1)*retained); c.wet=math.max(c.wet or 0,c.snow*.12)
  return true
end

function Surface.depositLeaves(x,z,amount)
  local c=getCell(x,z,true); if not c then return end
  c.leaves=clamp01((c.leaves or 0)+(tonumber(amount) or .03))
end

function Surface.scorch(x,z,amount)
  local c=getCell(x,z,true); if not c then return end
  c.scorch=clamp01((c.scorch or 0)+(tonumber(amount) or .35)); c.snow=(c.snow or 0)*.2; c.wet=(c.wet or 0)*.65
end

function Surface.setTemperature(x,z,temp)
  local c=getCell(x,z,true); if c then c.temp=tonumber(temp) or 0 end
end

function Surface.setMaterial(x,z,material)
  local c=getCell(x,z,true); if c then c.material=MaterialSystem.normalize(material); return c.material end
end

function Surface.materialAt(x,z)
  local c=getCell(x,z,false); return MaterialSystem.normalize(c and c.material or "soil")
end

function Surface.sampleInto(x,z,out)
  out=out or {}; local c=getCell(x,z,false)
  out.wet=c and (c.wet or 0) or 0; out.snow=c and (c.snow or 0) or 0; out.leaves=c and (c.leaves or 0) or 0; out.scorch=c and (c.scorch or 0) or 0; out.ice=c and (c.ice or 0) or 0
  out.temp=c and (c.temp or 0) or 0; out.puddle=c and (c.puddle or 0) or 0; out.mud=c and (c.mud or 0) or 0; out.frost=c and (c.frost or 0) or 0; out.material=MaterialSystem.normalize(c and c.material or "soil")
  return MaterialSystem.responseInto(out.material,out,out)
end
function Surface.sample(x,z) return Surface.sampleInto(x,z,{}) end

function Surface.update(dt,x,z,atmo)
  dt=math.max(0,tonumber(dt) or 0); lastX,lastZ=tonumber(x) or lastX,tonumber(z) or lastZ
  sim:updateCenter(lastX,lastZ); accum=accum+dt; compactAccum=compactAccum+dt
  if compactAccum>=4 then
    compactAccum=0
    for _,chunk in pairs(sim.chunks) do if not chunk.active then packChunk(chunk) end end
  end
  if accum<.25 then return end
  dt,accum=accum,0
  local temp=(atmo and tonumber(atmo.temperature)) or 10
  local humidity=(atmo and tonumber(atmo.humidity)) or .4
  sim:forActive(function(chunk)
    for k,c in pairs(chunk.data) do
      local mp=MaterialSystem.profile(c.material)
      c.temp=c.temp*.92+temp*.08
      local dry=math.max(0,.0026*(1-humidity)*dt*(1+math.max(0,c.temp)/25)*(mp.drainage or .5))
      c.wet=math.max(0,(c.wet or 0)-dry)
      if c.temp>1 then c.snow=math.max(0,(c.snow or 0)-(.0015+.003*c.temp/20)*dt*(1.12-(mp.snowRetention or .7)*.35)) end
      if c.temp<0 and c.wet>.08 then c.ice=clamp01((c.ice or 0)+.0018*dt*(1-(mp.heat or .8)*.22)) else c.ice=math.max(0,(c.ice or 0)-.0012*dt*(mp.heat or .8)) end
      -- Derived environmental materials: puddles on low-porosity wet surfaces,
      -- mud on porous soil/grass, and frost whenever cold moisture is present.
      local puddleTarget=(c.wet or 0)>.58 and clamp01(((c.wet or 0)-.58)/.42)*(1-(mp.porosity or .5)) or 0
      local mudTarget=((c.material=="soil" or c.material=="grass") and (c.wet or 0)>.40) and clamp01(((c.wet or 0)-.40)/.60) or 0
      local frostTarget=(c.temp<1 and ((c.wet or 0)>.05 or humidity>.72)) and clamp01((1-c.temp)/8)*math.max(.2,humidity) or 0
      local f=1-math.exp(-dt/2.5); c.puddle=(c.puddle or 0)+(puddleTarget-(c.puddle or 0))*f; c.mud=(c.mud or 0)+(mudTarget-(c.mud or 0))*f; c.frost=(c.frost or 0)+(frostTarget-(c.frost or 0))*f
      c.leaves=math.max(0,(c.leaves or 0)-.00016*dt)
      c.scorch=math.max(0,(c.scorch or 0)-.000035*dt)
      if c.wet<.001 and c.snow<.001 and c.leaves<.001 and c.scorch<.001 and c.ice<.001 and (c.puddle or 0)<.001 and (c.mud or 0)<.001 and (c.frost or 0)<.001 then chunk.data[k]=nil end
    end
  end)
end

function Surface.stats()
  local s=sim:stats(); local cells,packedChunks=0,0
  for _,c in pairs(sim.chunks) do
    if c.data and c.data.__packed then cells=cells+math.floor(#c.data.__packed/12); packedChunks=packedChunks+1
    else for _ in pairs(c.data or {}) do cells=cells+1 end end
  end
  s.cells=cells; s.packedChunks=packedChunks; return s
end

function Surface.snapshot(limit)
  limit=math.max(1,tonumber(limit) or 512); local out={}
  for _,chunk in pairs(sim.chunks) do
    if chunk.data and chunk.data.__packed then
      local q=chunk.data.__packed
      for i=1,#q,12 do
        if #out>=limit then return out end
        out[#out+1]={x=q[i],z=q[i+1],wet=q[i+2],snow=q[i+3],leaves=q[i+4],scorch=q[i+5],ice=q[i+6],temp=q[i+7],puddle=q[i+8],mud=q[i+9],frost=q[i+10],material=ID_MATERIAL[q[i+11]] or "soil"}
      end
    else
      for _,c in pairs(chunk.data or {}) do
        if #out>=limit then return out end
        out[#out+1]={x=c.x,z=c.z,wet=c.wet,snow=c.snow,leaves=c.leaves,scorch=c.scorch,ice=c.ice,temp=c.temp,puddle=c.puddle,mud=c.mud,frost=c.frost,material=c.material}
      end
    end
  end
  return out
end

function Surface.restore(rows)
  if type(rows)~="table" then return false end
  sim=ChunkSim.new({chunkSize=256,activeRadius=2,sleepRadius=5})
  for i=1,#rows do
    local q=rows[i]
    if type(q)=="table" and q.x~=nil and q.z~=nil then
      local c=getCell((tonumber(q.x) or 0)*tileSize,(tonumber(q.z) or 0)*tileSize,true)
      if c then for _,k in ipairs({"wet","snow","leaves","scorch","ice","temp","puddle","mud","frost","material"}) do if q[k]~=nil then c[k]=q[k] end end end
    end
  end
  return true
end

return Surface
