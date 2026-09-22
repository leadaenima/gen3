-- Weather FX 8.1.69 snow accumulation menu/runtime regression.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end

local values={snowAccumulation='on'}
local Types={PINNED={'CLEAR'},byId={CLEAR={id='CLEAR',label='Clear'}}}; function Types.get(id) return Types.byId[id] end
local defined
local mod={id='weather_fx',options={define=function(_,rows) defined=rows;return true end,get=function(_,k)return values[k]end},events={on=function()end},log={info=function()end,warn=function()end}}
local modules={Types=Types}
local V={mod=mod}
function V.require(name)
  if modules[name] then return modules[name] end
  if name=='ConnectedWater' or name=='Microclimate' then return nil end
  local m=assert(loadfile(ROOT..'lib/'..name..'.lua'))(V);modules[name]=m;return m
end
V.safeCall=pcall
local S=V.require('Settings');S.define()
local row=S.row('snowAccumulation')
ck(row and row.label=='SNOW ACCUMULATION' and row.default=='on','SNOW ACCUMULATION row is exposed and defaults ON')
ck(row and row.choices and row.choices[1][2]=='on' and row.choices[2][2]=='off','SNOW ACCUMULATION exposes ON/OFF choices')
ck(S.snowAccumulationEnabled()==true,'default/ON setting enables accumulation')
values.snowAccumulation='off';S.beginFrame();ck(S.snowAccumulationEnabled()==false,'OFF setting disables accumulation')
values.snowAccumulation='on';S.beginFrame();ck(S.snowAccumulationEnabled()==true,'ON setting re-enables accumulation')

local map={id='FLAT_8169',def={width=16,height=16},cellTile=function() return 1 end,isWaterCell=function() return false end,tileAt=function() return 1 end}
local TS={forMap=function() return {[1]={class='ground',art='flat',h=0}} end,at=function(_,sh,t) return sh[t] end}
local VS={groundAt=function() return 0 end}
local SP=V.require('SnowPack');SP._reset();SP.setEnabled(true)
local player={px=32,py=32};local ctx=SP.beginFrame({map=map,state={map=map,player=player},player=player},0,VS,TS)
for _=1,12 do SP.depositAggregate(ctx,40,40,1.0) end
local c1,_,_,_,p1=SP.stats();ck(c1>0 and p1>0,'enabled SnowPack creates persistent bank state')
SP.setEnabled(false)
local c2,f2,_,_,p2=SP.stats();ck(c2==0 and f2==0 and p2==0,'turning accumulation OFF immediately clears banks and footprints')
local c,p=SP.depositAggregate(ctx,40,40,1.0);ck(c==nil and p==nil,'OFF blocks new accumulation deposits')
local hit=SP.resolveFlake(ctx,40,4,40,40,-1,40,0.5)
ck(hit~=nil and hit.patch==nil,'OFF keeps exact terrain collision for falling snow without depositing a bank')
SP.setEnabled(true);c,p=SP.depositAggregate(ctx,40,40,1.0);ck(c~=nil and p~=nil,'turning accumulation ON starts clean accumulation again')
ck(math.abs((SP.MAX_GROUND_HEIGHT or 0)-3.60)<1e-9,'8.1.69 setting does not change approved snow-bank height')

local fh=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb'));local wp=fh:read('*a');fh:close()
ck(wp:find('S.snowAccumulationEnabled',1,true)~=nil and wp:find('SP.setEnabled,accumulationOn',1,true)~=nil,'WorldPrecip consumes the live setting every frame')
ck(wp:find('if accumulationOn and snowCtx and snowCtx.collisionEnabled',1,true)~=nil,'OFF prevents aggregate bank/footprint staging while snowfall remains active')
print(('snow accumulation setting 8.1.69: %d passed, %d failed'):format(pass,fail));os.exit(fail==0 and 0 or 1)
