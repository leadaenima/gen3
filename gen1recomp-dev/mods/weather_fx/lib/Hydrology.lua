local V = ...
-- Sparse coarse runoff model. It complements EnvironmentSurface: the latter owns
-- per-material wet/snow/ice state; this layer models water collection/runoff.
-- 8.1.28: world-cell identity stays numeric, but drainage is explicitly flat-
-- world. Small deterministic basin/outlet differences model curb/soil/drainage
-- irregularity without inventing terrain elevation; voxel shelter and real water
-- cells control collection. The active field remains the same bounded 9x9 grid.
local H={}
local CELL=64; local R=4; local cells={}; local cx0,cz0=0,0; local elapsed=0; local serial=0
local deltaScratch={}; local flatScratch={}; local DX={1,-1,0,0}; local DZ={0,0,1,-1}; local ZERO={water=0,flow=0,depth=0}; local _FlatWorld=nil
local function clear(t) for k in pairs(t) do t[k]=nil end end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function hash(x,z,s) local n=math.sin(x*51.7+z*89.3+s*23.1)*43758.5453; return n-math.floor(n) end
local function get(cx,cz)
  local row=cells[cx]; local c=row and row[cz]
  if c then return c end
  if not row then row={}; cells[cx]=row end
  c={cx=cx,cz=cz,water=0,flow=0,depth=0,_basin=1-hash(cx,cz,4),_outlet=.30+.70*hash(cx,cz,7),_seen=0}
  row[cz]=c; return c
end

local function flatWorld()
  if _FlatWorld~=nil then return _FlatWorld or nil end
  local ok,m=pcall(V.require,"FlatWorldInteraction");_FlatWorld=(ok and m) or false;return _FlatWorld or nil
end
function H.update(dt,x,z,climate)
  dt=math.max(0,tonumber(dt) or 0); elapsed=elapsed+dt; serial=serial+1; cx0,cz0=math.floor((tonumber(x) or 0)/CELL),math.floor((tonumber(z) or 0)/CELL); climate=climate or {}
  local rain=clamp(tonumber(climate.precip) or 0,0,1); local temp=tonumber(climate.temperature) or 10
  local wind=tonumber(climate.wind) or 0
  local FW=flatWorld(); local fwReady=FW and FW.ready and FW.ready() and FW.sampleAt
  for dz=-R,R do for dx=-R,R do local cx,cz=cx0+dx,cz0+dz; local c=get(cx,cz); c._seen=serial
    local basin=c._basin; local shelter,waterCell=0,false
    if fwReady then
      local q=FW.sampleAt(cx*CELL+CELL*.5,cz*CELL+CELL*.5,flatScratch)
      shelter=clamp(tonumber(q and q.shelter) or 0,0,1);waterCell=q and q.water==true or false
    end
    -- Flat-world drainage: water collects according to tiny local basin/outlet
    -- differences, not invented terrain elevation. Roof/building shelter cuts
    -- direct rainfall; real water tiles absorb precipitation without becoming
    -- land puddles.
    local add=waterCell and 0 or rain*dt*.0028*(.55+basin*.9)*(1-shelter*.76); if temp<=0 then add=add*.15 end
    c.water=clamp(c.water+add,0,1)
    local evap=math.max(0,temp)*dt*.000035*(1-rain*.8)*(1-shelter*.35); c.water=math.max(0,c.water-evap)
    c.depth=waterCell and 0 or c.water*(.02+.18*basin); c.flow=waterCell and 0 or c.water*(.20+.45*c._outlet)*(.15+.5*wind)
  end end
  -- Conservative 4-neighbour exchange, bounded to the active field. Neighbour
  -- cells may sit just outside the active radius exactly as in 8.1.23.
  local delta=deltaScratch; clear(delta)
  for _,row in pairs(cells) do for _,c in pairs(row) do if c._seen==serial and c.water>.005 then
    local best,score=nil,-1
    for i=1,4 do local n=get(c.cx+DX[i],c.cz+DZ[i]); local drainage=(n._outlet-c._outlet)*.20+(c.water-n.water)*.35; if drainage>score then score,best=drainage,n end end
    if best and score>0 then local move=math.min(c.water*.06,score*.018)*math.min(1,dt); delta[c]=(delta[c] or 0)-move; delta[best]=(delta[best] or 0)+move end
  end end end
  for c,d in pairs(delta) do c.water=clamp(c.water+d,0,1) end
  for cx,row in pairs(cells) do
    for cz,c in pairs(row) do if c._seen~=serial and c.water<.003 then row[cz]=nil end end
    if next(row)==nil then cells[cx]=nil end
  end
end
function H.peekAt(x,z)
  local cx,cz=math.floor((tonumber(x) or 0)/CELL),math.floor((tonumber(z) or 0)/CELL); local row=cells[cx]; return (row and row[cz]) or ZERO
end
function H.sampleAt(x,z) local c=H.peekAt(x,z); return {water=c.water,flow=c.flow,depth=c.depth} end
function H.stats() local n,total=0,0; for _,row in pairs(cells) do for _,c in pairs(row) do n=n+1;total=total+c.water end end; return {cells=n,cellSize=CELL,water=total} end
return H
