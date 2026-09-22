local V = ...
-- Small capability registry for companion mods. Registrations are in-memory only
-- and namespaced by owner; Weather FX never edits another mod's files.
local R={version=1}; local providers={}
function R.register(owner,capability,fn)
  owner=tostring(owner or 'anonymous'); capability=tostring(capability or '')
  if capability=='' or type(fn)~='function' then return false end
  providers[capability]=providers[capability] or {}; providers[capability][owner]=fn; return true
end
function R.unregister(owner,capability) local p=providers[tostring(capability or '')]; if p then p[tostring(owner or 'anonymous')]=nil end; return true end
function R.call(capability,...)
  local p=providers[tostring(capability or '')]; if not p then return {} end; local out={}
  for owner,fn in pairs(p) do local ok,v=pcall(fn,...); if ok then out[#out+1]={owner=owner,value=v} end end; return out
end
function R.list() local o={}; for cap,p in pairs(providers) do local n=0; for _ in pairs(p) do n=n+1 end; o[cap]=n end; return o end
return R
