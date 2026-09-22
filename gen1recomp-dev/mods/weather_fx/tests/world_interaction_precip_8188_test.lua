local pass,fail=0,0
local function ok(v,msg) if v then pass=pass+1;print('PASS '..msg) else fail=fail+1;print('FAIL '..msg) end end
local WI={peek=function() return {roofDrip=.9,canopyDrip=.8} end}
local V={safeCall=function(fn,...) local a={pcall(fn,...)};local yes=table.remove(a,1);return yes,unpack(a) end,require=function(n) if n=='WeatherWorldInteraction' then return WI end error(n,0) end}
local P=assert(loadfile('lib/voxel_atmos/WorldInteractionPrecip.lua'))(V)
local m,style,sm,life=P.impactProfile('water','water','flat');ok(m=='water' and style==4 and sm>1 and life>.4,'water impacts use broad long-lived ripple response')
m,style,sm,life=P.impactProfile('grass','grass','grass');ok(m=='grass' and style==2 and sm<.7 and life<.3,'grass absorbs into a small short impact')
m,style=P.impactProfile('raised','metal','top');ok(m=='metal' and style==3,'hard raised metal uses sharp hard-surface response')
m,style=P.impactProfile('ice','ice','flat');ok(m=='ice' and style==5,'ice receives its own impact response')
local ctx={fallbackGroundY=0}
local SP={surfaceAt=function(ctx,x,z)
  if math.abs(x)<=15 and math.abs(z)<=15 then return 20,'raised','roof','top','full' end
  return 0,'ground','ground','flat','full'
end}
P.update(.016,ctx,SP,0,0,function() return true end)
ok(P.spawnRoof(ctx,SP,8,20,8,17,true)==true,'roof hit resolves a stable nearby eave drip')
ok(P.spawnCanopy(ctx,4,18,4,true)==true,'canopy hit creates a delayed branch drip')
local st=P.stats();ok(st.active>=2 and st.active<=st.max,'secondary drip pool is bounded')
local landed=0
local function impact(...) landed=landed+1;return true end
for i=1,120 do P.update(.05,ctx,SP,0,0,impact) end
ok(landed>0,'delayed drips fall to the support plane and emit real impact callbacks')
st=P.stats();ok(st.max==128 and st.active<=128,'secondary precipitation remains capped at 128 live beads')
print(string.format('world interaction precipitation 8.1.88: %d passed, %d failed',pass,fail))
os.exit(fail==0 and 0 or 1)
