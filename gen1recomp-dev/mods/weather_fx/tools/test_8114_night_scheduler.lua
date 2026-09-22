math.randomseed(8114)
local TOD={hour=19.9,pin=nil,hostMode=nil}
local V={}
function V.require(name)
  if name=="TimeOfDay" then return TOD end
  error("stub has no module "..tostring(name))
end
local chunk,err=loadfile("lib/NightSky.lua")
assert(chunk,err)
local NS=chunk(V)
local showerNights=0
for night=1,200 do
  TOD.hour=19.9; NS.update(0.1)
  TOD.hour=20.0; NS.update(0.1)
  local maxActive=0
  for minute=0,479 do
    TOD.hour=(20 + minute/60)%24
    NS.update(1.0)
    local p=NS.celestialEventProof()
    if #p.active>maxActive then maxActive=#p.active end
  end
  local p=NS.celestialEventProof()
  assert(p.singlesFired==4,"night "..night.." singles="..tostring(p.singlesFired))
  if p.showerFired then showerNights=showerNights+1 end
  assert(maxActive<=7,"events stacked beyond one shower")
  TOD.hour=4.0; NS.update(0.1)
  TOD.hour=12.0; NS.update(0.1)
end
assert(showerNights>=8 and showerNights<=32,"10% roll unreasonable over 200 nights: "..showerNights)
print("PASS 200-night scheduler: 4 singles/night, <=1 shower/night, shower nights="..showerNights)
