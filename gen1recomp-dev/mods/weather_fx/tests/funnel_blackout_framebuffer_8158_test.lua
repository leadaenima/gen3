-- 8.1.58 regression: relocation blackout must paint the final framebuffer,
-- not only an earlier weather canvas that the destination map can overwrite.
local calls={}
local function rec(name,...)
  calls[#calls+1]={name,...}
end
love={graphics={
  push=function(mode) rec('push',mode) end,
  pop=function() rec('pop') end,
  origin=function() rec('origin') end,
  setScissor=function(...) rec('scissor',...) end,
  setShader=function(...) rec('shader',...) end,
  setBlendMode=function(...) rec('blend',...) end,
  setColor=function(...) rec('color',...) end,
  rectangle=function(...) rec('rect',...) end,
  getDimensions=function() return 1024,768 end,
}, math={random=function() return .5 end}}
local V={}
local chunk=assert(loadfile('lib/Funnel.lua')); local F=chunk(V)
local passed,failed=0,0
local function check(ok,msg)
  if ok then passed=passed+1; print('PASS '..msg) else failed=failed+1; print('FAIL '..msg) end
end

F.start(2.5,nil,{mode='relocate2d'})
check(F.drawBlackoutOverlay({width=640,height=480})==false,'post-HUD blackout stays off outside blackout phase')
F.phase='blackout'; F.active=true; F.mode='relocate2d'
calls={}
check(F.blackoutActive()==true,'blackout state is explicit')
check(F.drawBlackoutOverlay({width=640,height=480})==true,'post-HUD blackout draws while relocation is blacked out')
local rect,color,push,pop,origin,scissor,shader=false,false,false,false,false,false,false
for _,c in ipairs(calls) do
  if c[1]=='rect' and c[2]=='fill' and c[3]==0 and c[4]==0 and c[5]==1024 and c[6]==768 then rect=true end
  if c[1]=='color' and c[2]==0 and c[3]==0 and c[4]==0 and c[5]==1 then color=true end
  if c[1]=='push' and c[2]=='all' then push=true end
  if c[1]=='pop' then pop=true end
  if c[1]=='origin' then origin=true end
  if c[1]=='scissor' and c[2]==nil then scissor=true end
  if c[1]=='shader' and c[2]==nil then shader=true end
end
check(rect,'blackout covers the complete live framebuffer dimensions')
check(color,'blackout is opaque true black')
check(push and pop,'graphics state is preserved around post-HUD blackout')
check(origin and scissor and shader,'inherited transform/scissor/shader cannot clip or recolour blackout')
F.phase='sweepin'
check(F.drawBlackoutOverlay({})==false,'blackout releases before destination sweep-in')
print(string.format('8.1.58 framebuffer blackout: %d passed, %d failed',passed,failed))
os.exit(failed==0 and 0 or 1)
