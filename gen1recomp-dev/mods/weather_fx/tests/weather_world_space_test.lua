local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1 else fail=fail+1;print('FAIL '..n) end end
local W=assert(loadfile(ROOT..'lib/WeatherWorldSpace.lua'))({})
local A,B,C={id='MAP_A'},{id='MAP_B'},{id='MAP_C'}
W.observeVoxelState({map=A,neighbors={{map=B,ox=512,oy=0}}})
local ax,az=W.toWorld(500,100,'MAP_A');ck(ax==500 and az==100,'root map starts canonical')
local bx,bz=W.toWorld(4,100,'MAP_B');ck(bx==516 and bz==100,'neighbor maps into same canonical frame')
W.observeVoxelState({map=B,neighbors={{map=A,ox=-512,oy=0}}})
local bx2,bz2=W.toWorld(4,100,'MAP_B');ck(bx2==516 and bz2==100,'connected root rebase keeps canonical position')
ck(W.continuous()==true,'connected map transition marked continuous')
local lx,lz=W.toLocal(516,100,'MAP_B');ck(lx==4 and lz==100,'canonical converts back to destination local')
W.observeVoxelState({map=C,neighbors={}});ck(W.continuous()==false,'unproved warp starts disconnected weather space')
ck(W.epoch()==1,'disconnected warp advances weather-space epoch')
local cx,cz=W.toWorld(0,0,'MAP_C')
ck(math.abs(cx)>10000 and cz==0,'disconnected root is isolated instead of overlapping prior overworld')
local axStill,azStill=W.toWorld(500,100,'MAP_A')
ck(axStill==500 and azStill==100,'disconnected map does not erase learned overworld origin')
W.observeVoxelState({map=A,neighbors={{map=B,ox=512,oy=0}}})
local axReturn,azReturn=W.toWorld(500,100,'MAP_A')
ck(axReturn==500 and azReturn==100,'returning to prior map resumes exact persistent weather space')
print(string.format('weather world space: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
