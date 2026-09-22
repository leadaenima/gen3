local V = ...

-- Public low-allocation event layer for companion mods / NPC / encounter logic.
-- Weather FX publishes environmental transitions; consumers opt in through
-- subscribe() instead of Weather FX permanently editing another mod.
local E={serial=0}
local listeners={}; local queue={}; local last={storm=false,freeze=false,heat=false,heavyRain=false,fog=false}
local MAX=128
local function emit(kind,data)
  E.serial=E.serial+1; local row={serial=E.serial,kind=kind,data=data}; queue[#queue+1]=row; if #queue>MAX then table.remove(queue,1) end
  local ls=listeners[kind]; if ls then for i=1,#ls do pcall(ls[i],row) end end
  local any=listeners['*']; if any then for i=1,#any do pcall(any[i],row) end end
end
function E.subscribe(kind,fn)
  if type(fn)~='function' then return false end; kind=tostring(kind or '*'); listeners[kind]=listeners[kind] or {}; listeners[kind][#listeners[kind]+1]=fn; return true
end
function E.update(dt,climate,surface,scene)
  climate=climate or {}; surface=surface or {}; scene=scene or {}
  local now={
    storm=(tonumber(climate.storm) or 0)>=.55,
    freeze=(tonumber(climate.temperature) or 10)<=0,
    heat=(tonumber(climate.temperature) or 10)>=28,
    heavyRain=(tonumber(climate.precip) or 0)>=.68 and (tonumber(climate.temperature) or 10)>1,
    fog=(tonumber(climate.visibility) or 1)<=.55,
  }
  for k,v in pairs(now) do if v~=last[k] then emit(k..(v and '_begin' or '_end'),{climate=climate,surface=surface,mapId=scene.mapId,indoors=scene.indoors}); last[k]=v end end
end
function E.recent(since,out)
  since=tonumber(since) or 0; out=out or {}; for i=#out,1,-1 do out[i]=nil end
  for i=1,#queue do if queue[i].serial>since then out[#out+1]=queue[i] end end; return out
end
function E.publish(kind,data) emit(tostring(kind),data); return E.serial end
function E.stats() local n=0; for _,ls in pairs(listeners) do n=n+#ls end; return {serial=E.serial,queued=#queue,listeners=n} end
return E
