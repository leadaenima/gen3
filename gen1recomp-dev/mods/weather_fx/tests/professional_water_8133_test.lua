local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end
local function cpRows(rows,n)
  local out={};n=n or #rows
  for i=1,n do local q={};for j=1,6 do q[j]=rows[i][j] end;out[i]=q end
  return out
end

local CWauth=assert(loadfile(ROOT.."lib/ConnectedWater.lua"))({mod={},require=function() error("optional") end})
local function cells(w,h)
  local out={};for z=0,h-1 do for x=0,w-1 do out[#out+1]={gx=x,gz=z} end end;return out
end
local lake=CWauth._bodyMorphology(cells(9,7),false)
local river=CWauth._bodyMorphology(cells(12,2),false)
local sea=CWauth._bodyMorphology(cells(10,8),true)
check(lake.kind=="LAKE","broad enclosed cartridge water classifies as lake")
check(river.kind=="RIVER" and river.rapidness>=0.35 and (river.flowX~=0 or river.flowZ~=0),"narrow elongated water classifies as flowing rapid-capable river")
check(sea.kind=="SEA","large boundary-connected water classifies as exposed sea")
local calmBody={id=99,signature="calm",cells={},rects={},area=63,touchesBoundary=false,kind="LAKE",ice=0,temp=18,tide=0,wave=0,loadBearing=false}
CWauth.bodies={calmBody};CWauth.update(.1,nil,{id="SUMMER"})
check(calmBody.wave>0.25,"calm lake retains visible natural heave instead of collapsing to tiny ripples")

local now=0;local meshes={};local draws={}
love={timer={getTime=function() return now end},image={newImageData=function(w,h) return {setPixel=function() end} end},graphics={
  newImage=function(d) return {setFilter=function() end,setWrap=function() end,release=function() end} end,
  newMesh=function(fmt,data,mode,usage)
    local initial=type(data)=="table" and cpRows(data) or nil
    local m={initial=initial,current=initial and cpRows(initial) or {},mode=mode,usage=usage}
    function m:setTexture() end
    function m:setVertexMap(v) self.map={};for i=1,#v do self.map[i]=v[i] end end
    function m:setVertices(r,s,n) self.current=cpRows(r,n);self.n=n end
    function m:setDrawRange(a,n) self.range=n end
    function m:release() end
    meshes[#meshes+1]=m;return m
  end
}}
local V3={FORMAT={{"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexShade","float",1}},draw=function(m,t,tr) draws[#draws+1]={m=m,t=t,tr=tr} end}
local Mat4={translate=function(x,y,z) return {x=x,y=y,z=z} end}
local Water={WAVE_TRAINS={{.15,.06,1.6,.6},{.05,.13,-1,.29},{-.04,.03,.55,.11}},WAVE_HEIGHT=5,
  WAVE_SWELL={.0325,.0134,.55,.35},WAVE_BEND={-.0138,.0333,.35,1.10},WAVE_FPS=12,WAVE_PIXELS_PER_STEP=1,WAVE_SLOPE=3.5,WAVE_SLOPE_LEAN=1.5,
  _waveTime=function() return now end,_trainSource=function() return "structured" end,invalidate=function() end}
local function mkBody(id,sig,x0,z0,w,d,kind,wave,rapid)
  local b={id=id,signature=sig,rects={{x0=x0*16,z0=z0*16,x1=(x0+w)*16,z1=(z0+d)*16}},cells={},area=w*d,loadBearing=false,tide=.20,wave=wave,ice=0,
    kind=kind,rapidness=rapid or 0,flowX=(w>=d and 1 or 0),flowZ=(d>w and 1 or 0)}
  for z=z0,z0+d-1 do for x=x0,x0+w-1 do b.cells[#b.cells+1]={gx=x,gz=z} end end
  return b
end
local ocean=mkBody(1,"rough-sea",0,0,16,16,"SEA",1.20,0)
local channel=mkBody(2,"rapid-river",18,0,2,12,"RIVER",.80,.82)
local CW={observed=true,bodies={ocean,channel},windX=1,windZ=.12,rippleState=function() return {} end}
function CW.bodyAt(x,z)
  local gx,gz=math.floor(x/16),math.floor(z/16)
  for _,b in ipairs(CW.bodies) do for _,c in ipairs(b.cells) do if c.gx==gx and c.gz==gz then return b end end end
end
local modules={ConnectedWater=CW,Voxel3D=V3,Mat4=Mat4,Water=Water}
local V={require=function(n) if modules[n] then return modules[n] end error(n,0) end}
local R=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))(V)
local liquid,owned=R.prepare({{nil,{}}});local st=R.physicalSurfaceStats()
check(owned and st.active and #liquid==2,"Weather FX owns a true tessellated physical water surface")
check(st.vertices>4000 and st.indices>20000,"physical water uses thousands of real 3D vertices/indices, not one flat quad")
check(Water.WAVE_HEIGHT==0 and st.waveHeight>6.5,"flat fragment relief is disabled when real wave geometry owns the silhouette")

local surf=nil
for _,m in ipairs(meshes) do if m.map and m.current and #m.current>1000 then surf=m;break end end
local mn,mx=1e9,-1e9;local horizontal=0;local boundaryShift=0
if surf then
  for i,v in ipairs(surf.current) do
    mn=math.min(mn,v[2]);mx=math.max(mx,v[2]);local q=surf.initial[i]
    if q then
      local d=math.sqrt((v[1]-q[1])^2+(v[3]-q[3])^2);horizontal=math.max(horizontal,d)
      if q[1]==0 or q[3]==0 or q[1]==256 or q[3]==256 then boundaryShift=math.max(boundaryShift,d) end
    end
  end
end
check(surf and (mx-mn)>5.0,"render mesh has substantial crest-to-trough vertical relief")
check(horizontal>0.15,"interior vertices receive Gerstner-style horizontal orbital motion for leaning crests")
check(boundaryShift<1e-6,"horizontal wave motion is pinned at authored shorelines")
check(st.foamVertices>300 and st.whitecaps>20,"rough open water generates broken whitecap geometry on wave crests")
check(st.curls>0,"strong crests generate raised folded foam lips that read as curling waves")
check(st.rapids>0,"river topology generates aligned white rapid streaks")
check(st.shoreFoam>0,"impact-facing shoreline edges generate breaking-wave foam")

local before=cpRows(surf.current);local meshCount=#meshes
now=.83;R.prepare({{nil,{}}});local moved=0
for i,v in ipairs(surf.current) do local q=before[i];if q then moved=math.max(moved,math.abs(v[2]-q[2])) end end
check(#meshes==meshCount,"steady waves update cached stream meshes instead of rebuilding water topology")
check(moved>0.25,"wave crests physically travel through the 3D mesh over time")

local bestX,bestZ,best=-1,-1,-1e9
for z=8,248,8 do for x=8,248,8 do local d=R.waveDisplacementAt(x,z,true);if d>best then best,bestX,bestZ=d,x,z end end end
local p={surfing=true,px=bestX-8,py=bestZ-8};local px0,py0=p.px,p.py
local bob=R.playerBob({player=p})
check(bob>0.5,"Surf/player presentation rides visibly upward on a real crest")
check(p.px==px0 and p.py==py0,"buoyancy bob never corrupts gameplay X/Y collision coordinates")

R.invalidate()
print(string.format("professional water 8.1.33: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
