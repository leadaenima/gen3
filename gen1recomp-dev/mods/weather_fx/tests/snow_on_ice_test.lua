local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0;local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end
local frozen=false
local CW={isLoadBearingAt=function() return frozen end,surfaceYAt=function() return -2 end}
local V={require=function(n) if n=="ConnectedWater" then return CW end error(n,0) end}
local SP=assert(loadfile(ROOT.."lib/SnowPack.lua"))(V)
local map={id="W",widthCells=1,heightCells=1,isWaterCell=function() return true end,cellTile=function() return 0 end,tileAt=function() return 0 end}
local VS={groundAt=function() return 0 end};local TS={forMap=function() return {[0]={class="water",art="water",h=-2}} end,at=function() return {class="water",art="water",h=-2} end}
local state={map=map,neighbors={},player={px=0,py=0}};local ctx=SP.beginFrame({map=map,neighbors={},state=state,player=state.player},0,VS,TS)
local y,k=SP.surfaceAt(ctx,8,8);check(k=="water","liquid cartridge water still rejects snow")
frozen=true;y,k=SP.surfaceAt(ctx,8,8);check(k=="ice" and math.abs(y+2)<.01,"load-bearing water exposes real ice support to SnowPack")
local c,p=SP.deposit(ctx,8,8,y,1);check(c~=nil and p~=nil,"snow can accumulate on frozen connected water")
local d=SP.depthAtPoint(ctx,8,8);check(d>0,"snow depth persists on ice")
frozen=false;y,k=SP.surfaceAt(ctx,8,8);check(k=="water","thawed surface immediately returns to liquid classification")
print(string.format("snow on ice 8.1.29: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
