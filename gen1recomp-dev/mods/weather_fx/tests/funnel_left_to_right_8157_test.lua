local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/"
ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(ok,msg) if ok then passed=passed+1; print("PASS "..msg) else failed=failed+1; print("FAIL "..msg) end end
local rects={}
love={math={random=function() return .5 end},graphics={
  getColor=function() return 1,1,1,1 end,getBlendMode=function() return 'alpha','alphamultiply' end,
  setBlendMode=function() end,setColor=function() end,
  rectangle=function(mode,x,y,w,h) rects[#rects+1]={x=x,y=y,w=w,h=h} end,
}}
local F=assert(loadfile(ROOT..'lib/Funnel.lua'))({})
local pickup,done=0,0
F.start(2,function() done=done+1 end,{mode='carry2d',pickupAt=.55,onPickup=function() pickup=pickup+1 end})
local function bodyX()
  rects={}; assert(F.draw(0,0,640,480,4)==true); return rects[2] and rects[2].x or 0
end
F.update(.20); local x1=bodyX()
for _=1,3 do F.update(.20) end; local x2=bodyX()
check(x2>x1,'2D tornado moves rightward from left side toward screen centre')
check(pickup==0,'pickup does not fire before centre crossing')
for _=1,2 do F.update(.15) end; local x3=bodyX()
check(x3>x2,'2D tornado continues moving right through centre')
check(pickup==1,'pickup fires exactly once while tornado covers player near centre')
F.update(.25); local x4=bodyX()
check(x4>x3,'2D tornado continues toward right edge after relocation')
for _=1,5 do F.update(.25) end
check(not F.active and done==1,'2D tornado exits right and completes once')
check(pickup==1,'pickup callback never repeats after map transfer')
print(('left-to-right funnel 8.1.57: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
