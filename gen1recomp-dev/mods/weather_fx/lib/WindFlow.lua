local V = ...
-- Local flow-field derived from the authoritative WindEngine. It bends/slows
-- flow according to scene context while remaining camera-independent.
-- 8.1.24: numeric nested cells replace per-update string keys, deterministic
-- cell noise is cached once, and rotation terms are recomputed only if local
-- drag changes. The flow equations and 9x9 field are unchanged.
local F={}
local CELL=64; local R=4; local cells={}; local cx0,cz0=0,0; local serial=0; local flatScratch={}; local fallback={x=0,z=0,speed=0,shelter=0}
local _Wind=nil; local _FW=nil
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function hash(x,z,s) local n=math.sin(x*71.3+z*131.7+s*17.9)*43758.5453; return n-math.floor(n) end
local function sceneDrag(scene)
  local id=tostring(scene and (scene.mapId or scene.map or scene.name) or ''):lower()
  if scene and scene.indoors then return .08 end
  if id:find('forest',1,true) then return .58 end
  if id:find('city',1,true) or id:find('town',1,true) then return .72 end
  if id:find('cave',1,true) then return .14 end
  return .90
end
local function getCell(cx,cz)
  local row=cells[cx]; local c=row and row[cz]
  if c then return c end
  if not row then row={}; cells[cx]=row end
  local n,n2=hash(cx,cz,1)-.5,hash(cx,cz,2)-.5
  c={x=0,z=0,cx=cx,cz=cz,_n=n,_n2=n2,_drag=false,_cs=1,_sn=0,_amp=1,_seen=0}
  row[cz]=c; return c
end
local function windModule()
  if not _Wind then local ok,W=pcall(V.require,'WindEngine'); if ok and W then _Wind=W end end
  return _Wind
end
local function flatWorldModule()
  if not _FW then local ok,W=pcall(V.require,'FlatWorldInteraction'); if ok and W then _FW=W end end
  return _FW
end
function F.update(dt,x,z,scene)
  local W=windModule(); local w=W and W.peek and W.peek() or {}
  cx0,cz0=math.floor((tonumber(x) or 0)/CELL),math.floor((tonumber(z) or 0)/CELL); serial=serial+1
  local sceneBase=sceneDrag(scene); local bx,bz=tonumber(w.x) or 0,tonumber(w.z) or 0
  local FW=flatWorldModule(); local fwReady=FW and FW.ready and FW.ready() and FW.sampleAt
  local f=1-math.exp(-math.max(0,tonumber(dt) or 0)/1.2)
  for dz=-R,R do for dx=-R,R do
    local cx,cz=cx0+dx,cz0+dz; local c=getCell(cx,cz); c._seen=serial
    local n,n2=c._n,c._n2; local drag=sceneBase
    if fwReady then
      local q=FW.sampleAt(cx*CELL+CELL*.5,cz*CELL+CELL*.5,flatScratch,bx,bz)
      if q then
        local exposure=clamp(tonumber(q.windExposure) or 1,.05,1.18)
        drag=drag*(tonumber(q.drag) or 1)*(.82+.18*exposure)
      end
    end
    if c._drag~=drag then
      local turn=n*.42*(1-drag*.35); c._cs,c._sn=math.cos(turn),math.sin(turn); c._amp=drag*(.86+n2*.18); c._drag=drag
    end
    local tx=(bx*c._cs-bz*c._sn)*c._amp; local tz=(bx*c._sn+bz*c._cs)*c._amp
    c.x=c.x+(tx-c.x)*f; c.z=c.z+(tz-c.z)*f
    c.speed=math.sqrt(c.x*c.x+c.z*c.z); c.shelter=clamp(1-drag+.12*math.abs(n),0,1)
  end end
  for cx,row in pairs(cells) do
    for cz,c in pairs(row) do if c._seen~=serial then row[cz]=nil end end
    if next(row)==nil then cells[cx]=nil end
  end
end
function F.sampleAt(x,z)
  local cx,cz=math.floor((tonumber(x) or 0)/CELL),math.floor((tonumber(z) or 0)/CELL)
  local row=cells[cx]; local c=row and row[cz]
  if c then return c end
  local W=windModule(); local w=W and W.peek and W.peek() or {}; fallback.x,fallback.z,fallback.speed,fallback.shelter=tonumber(w.x) or 0,tonumber(w.z) or 0,tonumber(w.strength) or 0,0; return fallback
end
function F.vector(x,z,scale) local c=F.sampleAt(x,z); scale=tonumber(scale) or 1; return c.x*scale,c.z*scale end
function F.stats() local n=0; for _,row in pairs(cells) do for _ in pairs(row) do n=n+1 end end; return {cells=n,cellSize=CELL,radius=R,serial=serial} end
return F
