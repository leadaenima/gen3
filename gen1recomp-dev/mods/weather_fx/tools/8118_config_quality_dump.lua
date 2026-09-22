local function fmt(v)
 if type(v)=='number' then return string.format('%.12g',v) end
 if type(v)=='boolean' then return v and 'true' or 'false' end
 if v==nil then return 'nil' end
 return tostring(v)
end
local function ks(t) local a={}; for k in pairs(t or {}) do a[#a+1]=k end; table.sort(a,function(x,y)return tostring(x)<tostring(y)end); return a end
local function flat(prefix,t)
 for _,k in ipairs(ks(t)) do
  local v=t[k]; local p=prefix=='' and tostring(k) or prefix..'.'..tostring(k)
  if type(v)=='table' then flat(p,v) else io.write('CFG|'..p..'|'..fmt(v)..'\n') end
 end
end
local Types=assert(loadfile('lib/Types.lua'))()
local V={mod={log=function() end},require=function(n) if n=='Types' then return Types end end}
local C=assert(loadfile('lib/Config.lua'))(V)
flat('',C.get())
local VQ={require=function(n) if n=='Settings' then return {} elseif n=='Config' then return C end end}
local Q=assert(loadfile('lib/Quality.lua'))(VQ)
for _,tier in ipairs({'potato','low','medium','high','max'}) do
 for _,k in ipairs(ks(Q.TIERS[tier])) do io.write('QUALITY|'..tier..'|'..tostring(k)..'|'..fmt(Q.TIERS[tier][k])..'\n') end
end
for i,k in ipairs(Q.ORDER) do io.write('QORDER|'..i..'|'..k..'\n') end
