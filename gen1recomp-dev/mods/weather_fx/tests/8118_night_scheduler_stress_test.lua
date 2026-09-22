math.randomseed(811817)
local passed,failed=0,0
local function ck(v,m) if v then passed=passed+1 else failed=failed+1; if failed<=25 then io.write('FAIL '..m..'\n') end end end
local TOD={hour=12,pin=nil,hostMode=nil}
local V={require=function(n) if n=='TimeOfDay' then return TOD end error('stub has no '..tostring(n)) end}
local NS=assert(loadfile('lib/NightSky.lua'))(V)
local showerNights=0
local N=1000
for night=1,N do
  TOD.hour=12; NS.update(.1)
  TOD.hour=19.9; NS.update(.1); TOD.hour=20.0; NS.update(.1)
  local maxActive=0
  for minute=0,479 do
    TOD.hour=(20+minute/60)%24; NS.update(1.0)
    local p=NS.celestialEventProof(); if #p.active>maxActive then maxActive=#p.active end
    ck((p.singlesFired or 0)<=4,'never exceeds four singles in night '..night)
  end
  local p=NS.celestialEventProof()
  ck(p.singlesFired==4,'exactly four singles in night '..night)
  ck(maxActive<=7,'bounded active meteor population night '..night)
  if p.showerFired then showerNights=showerNights+1 end
  TOD.hour=4; NS.update(.1); TOD.hour=12; NS.update(.1)
end
-- A seeded 10% Bernoulli process over 1000 nights should stay comfortably in this band.
ck(showerNights>=65 and showerNights<=135,'1000-night shower frequency remains consistent with one 10% roll/night: '..showerNights)
print(string.format('8.1.18 night scheduler stress: %d passed, %d failed; shower nights=%d/%d',passed,failed,showerNights,N))
os.exit(failed>0 and 1 or 0)
