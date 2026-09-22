local pass,fail=0,0
local function check(v,n) if v then pass=pass+1 else fail=fail+1;print('FAIL '..n) end end
local C=assert(loadfile('lib/Constellations.lua'))({})
local new={'Poliwag','Ekans','Weedle','Pidgeotto','Rattata','Fearow','Sandshrew','Nidorino','Oddish','Vulpix','Bellsprout','Diglett','Meowth','Psyduck'}
local seen={}
for _,n in ipairs(C.NAMES) do seen[n]=(seen[n] or 0)+1 end
check(#C.NAMES==25,'expanded catalogue has 25 constellations')
check(C.count()>=3000,'expanded catalogue remains dense enough to read as traced outlines')
for _,n in ipairs(new) do
  check(seen[n]==1,n..' appears exactly once')
  check(C.TRACE[n] and C.TRACE_COUNTS[n]>=80,n..' has dense native trace geometry')
  check(C.ANCHORS[n]~=nil,n..' has world-space celestial anchor')
  local prim=0
  for _,s in ipairs(C.BY_NAME[n] or {}) do if s.primary then prim=prim+1 end end
  check(prim>=4,n..' has bright landmark stars')
end
for _,n in ipairs({'Charmander','Squirtle','Bulbasaur','Pikachu','Jigglypuff','PokeBall'}) do check(seen[n]==1,n..' was not duplicated') end
-- Prove new catalogue goes through the same world append path.
local verts={};local function push(v,n,x,y,z,half,ar,au,r,g,b,a) v[n+1]={x,y,z,a};return n+1 end
local n=C.appendWorld(verts,0,push,{1,0,0},{0,1,0},{0,0,0},280,nil,nil,1,function() return 1 end,function() return 1 end,0)
-- appendWorld emits one quad call per star plus a second landmark call for primaries;
-- exact vertex topology belongs to NightSky's pushQuad, so only require all stars emitted.
check(n>=C.count(),'expanded catalogue submits every traced star to world renderer')
print(('expanded constellations: %d passed, %d failed'):format(pass,fail));os.exit(fail==0 and 0 or 1)
