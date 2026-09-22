local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end
local created={};local draws={};local invalid=0
love={image={newImageData=function(w,h)
  local d={w=w,h=h,pixels={},alphas={}}
  function d:setPixel(x,y,r,g,b,a)
    self.pixels[#self.pixels+1]={r,g,b,a};self.alphas[a or 1]=true
  end
  created[#created+1]=d;return d
end},graphics={
 newImage=function(d) return {data=d,setFilter=function() end,setWrap=function() end,release=function() end} end,
 newMesh=function(fmt,data,usage,mode) local m={data=data};function m:setTexture() end;function m:setVertices(r,s,n) self.n=n end;function m:setDrawRange(a,n) self.range=n end;function m:release() end;return m end}}
local V3={FORMAT={{"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexShade","float",1}},draw=function(m,t,tr) draws[#draws+1]={m=m,t=t,tr=tr} end}
local Mat4={translate=function(x,y,z) return {x=x,y=y,z=z} end}
local Water={WAVE_TRAINS={{.15,.06,1.6,.6},{.05,.13,-1,.29},{-.04,.03,.55,.11}},WAVE_HEIGHT=5,invalidate=function() invalid=invalid+1 end}
local partial={signature="partial",rects={{x0=0,z0=0,x1=160,z1=160}},area=100,loadBearing=false,tide=.18,wave=.55,ice=.47}
local full={signature="full",rects={{x0=192,z0=0,x1=352,z1=160}},area=100,loadBearing=true,tide=0,wave=0,ice=1}
local CW={observed=true,bodies={partial,full},sample=function() return {windX=1,windZ=0} end,rippleState=function() return {} end}
local modules={ConnectedWater=CW,Voxel3D=V3,Mat4=Mat4,Water=Water}
local V={require=function(n) if modules[n] then return modules[n] end error(n,0) end}
local R=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))(V)
local liquid,owned=R.prepare({{nil,{}}})
check(owned and #liquid==1,"partial-freeze body remains in reflective liquid pass")
R.drawAfterWater()
check(#draws==2,"partial skim ice plus load-bearing ice draw as bounded overlays")
local iceData=nil;local skinData=nil
for _,d in ipairs(created) do if d.w==128 and not iceData then iceData=d elseif d.w==128 then skinData=d end end
check(iceData and iceData.w==128 and iceData.h==128,"full ice material is upgraded to 128x128 seamless source")
check(skinData and skinData.w==128,"progressive skim-ice stage material is generated")
local function alphaStats(d)
  local zero,mid,opaque=0,0,0
  for _,p in ipairs(d and d.pixels or {}) do local a=p[4] or 1;if a<=0.001 then zero=zero+1 elseif a<0.94 then mid=mid+1 else opaque=opaque+1 end end
  return zero,mid,opaque
end
local iz,im,io=alphaStats(iceData);local sz,sm,so=alphaStats(skinData)
check(im>0 and io>0,"full ice contains clear/translucent and frosted/fracture material classes")
check(sz>0 and sm>0,"skim ice has transparent liquid gaps plus translucent frozen coverage")
local colors={};for _,p in ipairs(iceData and iceData.pixels or {}) do colors[string.format("%.2f/%.2f/%.2f/%.2f",p[1],p[2],p[3],p[4])]=true end
local n=0;for _ in pairs(colors) do n=n+1 end
check(n>64,"ice material has broad deterministic color/opacity variation rather than a tiny stripe palette")
local skinDraw=draws[1];check(skinDraw and skinDraw.tr and math.abs((skinDraw.tr.y or 0)-.225)<.001,"skim ice tracks body tide just above live water")
print(string.format("realistic progressive ice 8.1.30: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
