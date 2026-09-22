local V = ...

-- Weather FX 7 whole-world climate grid.
-- Keeps a low-frequency, bounded coarse simulation independent from the camera.
-- Cells are lazy and deterministic so distant regions can be queried/forecast
-- without allocating the entire game world. Macro WeatherSimulation remains the
-- authoritative weather selector; this layer gives that weather spatial memory.
--
-- 8.1.24 performance note: cell identity is stored in nested numeric tables,
-- target state uses one scratch object, and the nine identical smoothing
-- coefficients are calculated once per update instead of once per cell. The
-- climate equations, active radius, cell count and update timing are unchanged.
local C={}
local CELL=1024
local RADIUS=5
local MAX_CELLS=256
local cells={}
local elapsed=0
local serial=0
local centreX,centreZ=0,0
local lastBase={pressure=1013,temperature=14,humidity=.45,cloud=.15,storm=0,wind=.12,precip=0,visibility=1,aerosol=.05}
local baseNum={pressure=1013,temperature=14,humidity=.45,cloud=.15,storm=0,wind=.12,precip=0,visibility=1,aerosol=.05}
local targetScratch={}
local BASE_KEYS={'pressure','temperature','humidity','cloud','storm','wind','precip','visibility','aerosol'}

local abs,floor,sin,exp,pi=math.abs,math.floor,math.sin,math.exp,math.pi
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function hash(x,z,s)
  local n=sin(x*127.17+z*311.71+s*73.13)*43758.5453
  return n-floor(n)
end
local function copy(t) local o={}; for k,v in pairs(t or {}) do o[k]=v end; return o end
local function refreshBase(src)
  if src and src~=lastBase then
    for k in pairs(lastBase) do lastBase[k]=nil end
    for k,v in pairs(src) do lastBase[k]=v end
  end
  baseNum.pressure=tonumber(lastBase.pressure) or 1013
  baseNum.temperature=tonumber(lastBase.temperature) or 14
  baseNum.humidity=tonumber(lastBase.humidity) or .45
  baseNum.cloud=tonumber(lastBase.cloud) or .15
  baseNum.storm=tonumber(lastBase.storm) or 0
  baseNum.wind=tonumber(lastBase.wind) or .12
  baseNum.precip=tonumber(lastBase.precip) or 0
  baseNum.visibility=tonumber(lastBase.visibility) or 1
  baseNum.aerosol=tonumber(lastBase.aerosol) or .05
end
local function makeCell(cx,cz)
  local h=hash(cx,cz,1)-.5
  local c={cx=cx,cz=cz,pressure=1013+h*4,temperature=14+h*3,humidity=clamp(.45+(hash(cx,cz,2)-.5)*.18,0,1),cloud=.15,storm=0,wind=.12,precip=0,visibility=1,aerosol=.05,front=hash(cx,cz,3)*pi*2,age=0,lastSeen=elapsed}
  local row=cells[cx]; if not row then row={}; cells[cx]=row end
  row[cz]=c
  return c
end
local function cell(cx,cz)
  local row=cells[cx]; local c=row and row[cz]
  return c or makeCell(cx,cz)
end
local function targetForInto(c,out)
  local adv=elapsed*.006*baseNum.wind
  local n=hash(c.cx+adv,c.cz-adv*.63,4)-.5
  local n2=hash(c.cx-adv*.42,c.cz+adv*.91,5)-.5
  local front=sin(c.front+elapsed*.008+(c.cx+c.cz)*.41)
  local storm=clamp(baseNum.storm+math.max(0,-front)*.18+math.max(0,n2)*.10,0,1)
  local humid=clamp(baseNum.humidity+n2*.16+storm*.08,0,1)
  out.pressure=baseNum.pressure+n*5-front*4.5
  out.temperature=baseNum.temperature+n*3.8-front*.9
  out.humidity=humid
  out.cloud=clamp(baseNum.cloud+n*.14+humid*.08+storm*.10,0,1)
  out.storm=storm
  out.wind=clamp(baseNum.wind+abs(n)*.10+storm*.12,0,1.3)
  out.precip=clamp(baseNum.precip*(0.72+humid*.45)+storm*.06,0,1)
  out.visibility=clamp(baseNum.visibility-storm*.06+(-math.max(0,humid-.75)*.18),0,1)
  out.aerosol=clamp(baseNum.aerosol+abs(n)*.04,0,1)
  return out
end
local function prune()
  local n=0
  for _,row in pairs(cells) do for _ in pairs(row) do n=n+1 end end
  if n<=MAX_CELLS then return end
  local list={}
  for cx,row in pairs(cells) do for cz,c in pairs(row) do
    list[#list+1]={cx=cx,cz=cz,d=math.max(math.abs(c.cx-centreX),math.abs(c.cz-centreZ)),seen=c.lastSeen or 0}
  end end
  table.sort(list,function(a,b) if a.d==b.d then return a.seen<b.seen end return a.d>b.d end)
  for i=1,n-MAX_CELLS do
    local q=list[i]; local row=cells[q.cx]
    if row then row[q.cz]=nil; if next(row)==nil then cells[q.cx]=nil end end
  end
end

function C.update(dt,base,x,z)
  dt=math.max(0,tonumber(dt) or 0); elapsed=elapsed+dt; serial=serial+1
  refreshBase(base)
  centreX,centreZ=floor((tonumber(x) or 0)/CELL),floor((tonumber(z) or 0)/CELL)
  -- Same exponential smoothing as 8.1.23, calculated once because dt/tau are
  -- identical for all 121 active cells this update.
  local fP,fT,fH,fC=1-exp(-dt/42),1-exp(-dt/55),1-exp(-dt/38),1-exp(-dt/30)
  local fS,fW,fR,fV,fA=1-exp(-dt/26),1-exp(-dt/24),1-exp(-dt/22),1-exp(-dt/28),1-exp(-dt/40)
  for dz=-RADIUS,RADIUS do for dx=-RADIUS,RADIUS do
    local c=cell(centreX+dx,centreZ+dz); c.lastSeen=elapsed; c.age=(c.age or 0)+dt
    local t=targetForInto(c,targetScratch)
    c.pressure=c.pressure+(t.pressure-c.pressure)*fP
    c.temperature=c.temperature+(t.temperature-c.temperature)*fT
    c.humidity=c.humidity+(t.humidity-c.humidity)*fH
    c.cloud=c.cloud+(t.cloud-c.cloud)*fC
    c.storm=c.storm+(t.storm-c.storm)*fS
    c.wind=c.wind+(t.wind-c.wind)*fW
    c.precip=c.precip+(t.precip-c.precip)*fR
    c.visibility=c.visibility+(t.visibility-c.visibility)*fV
    c.aerosol=c.aerosol+(t.aerosol-c.aerosol)*fA
    c.front=(c.front+dt*(.002+.006*c.wind))%(pi*2)
  end end
  prune()
end

function C.sampleAt(x,z)
  local cx,cz=floor((tonumber(x) or 0)/CELL),floor((tonumber(z) or 0)/CELL)
  local c=cell(cx,cz); c.lastSeen=elapsed; return c
end
function C.peek() local c=cell(centreX,centreZ); c.lastSeen=elapsed; return c end
function C.sample()
  local c=C.peek(); local o=copy(c); o.cellSize=CELL; o.serial=serial; return o
end
function C.forecastAt(x,z,seconds)
  seconds=math.max(0,tonumber(seconds) or 0)
  local c=C.sampleAt(x,z); local t=targetForInto(c,targetScratch); local f=clamp(seconds/600,0,1)
  local o={}
  for i=1,#BASE_KEYS do local k=BASE_KEYS[i]; o[k]=(tonumber(c[k]) or 0)+((tonumber(t[k]) or 0)-(tonumber(c[k]) or 0))*f end
  o.seconds=seconds; o.trendPressure=(tonumber(t.pressure) or 0)-(tonumber(c.pressure) or 0)
  if o.storm>.62 then o.summary='severe storm likely' elseif o.precip>.55 then o.summary='precipitation likely' elseif o.cloud>.62 then o.summary='mostly cloudy' elseif o.visibility<.55 then o.summary='low visibility' else o.summary='stable' end
  return o
end
function C.snapshot(limit)
  limit=math.max(1,tonumber(limit) or MAX_CELLS); local out={version=1,elapsed=elapsed,cells={}}
  for _,row in pairs(cells) do for _,c in pairs(row) do if #out.cells>=limit then return out end; out.cells[#out.cells+1]=copy(c) end end
  return out
end
function C.restore(s)
  if type(s)~='table' or type(s.cells)~='table' then return false end
  cells={}; elapsed=tonumber(s.elapsed) or elapsed
  for i=1,math.min(#s.cells,MAX_CELLS) do
    local c=copy(s.cells[i]); if c.cx and c.cz then local row=cells[c.cx]; if not row then row={};cells[c.cx]=row end; row[c.cz]=c end
  end
  return true
end
function C.ready() return serial>0 end
function C.stats() local n=0; for _,row in pairs(cells) do for _ in pairs(row) do n=n+1 end end; return {cells=n,cellSize=CELL,radius=RADIUS,maxCells=MAX_CELLS,serial=serial} end
function C.reset() cells={}; elapsed=0; serial=0 end
return C
