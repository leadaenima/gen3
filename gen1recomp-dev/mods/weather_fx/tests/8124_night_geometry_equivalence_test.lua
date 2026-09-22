local passed,failed=0,0
local function ok(c,msg) if c then passed=passed+1 else failed=failed+1;io.stderr:write('FAIL '..msg..'\n') end end
local function near(a,b,eps) eps=eps or 1e-12; return math.abs(a-b)<=eps*math.max(1,math.abs(a),math.abs(b)) end
local V={}
function V.safeBind(_) return pcall end
function V.require(name)
  if name=='Constellations' then return {appendWorld=function(_,n) return n end,STARS={}} end
  return {}
end
local N=assert(loadfile('lib/NightSky.lua'))(V)
local function up(fn,name)
  for i=1,120 do local n,v=debug.getupvalue(fn,i); if not n then break end;if n==name then return v end end
end
local planets=assert(up(N.drawWorld,'PLANETS'))
local pushPlanet=assert(up(N.drawWorld,'pushPlanetDisc'))
local planetTpl=assert(up(pushPlanet,'planetDiscTemplate'))
local satTpl=assert(up(N.drawWorld,'saturnRingTemplate'))
local xTpl=assert(up(N.drawWorld,'xRingTemplate'))
local milky=assert(up(N.drawWorld,'milkyWayPoints'))

local function phash(v) local x=math.sin(v*91.731+17.113)*43758.5453;return x-math.floor(x) end
local function pcolor(p,x,y)
  local d2=x*x+y*y; local mu=math.sqrt(math.max(0,1-d2)); local id=tonumber(p.id) or 1
  local r,g,b=p.r or .7,p.g or .7,p.b or .8
  local lr,lg,lb=p.limbR or r*.42,p.limbG or g*.42,p.limbB or b*.42
  local hr,hg,hb=p.hiR or math.min(1,r*1.15),p.hiG or math.min(1,g*1.12),p.hiB or math.min(1,b*1.10)
  local limb=.44+.56*mu; local light=.80+.20*math.max(0,math.min(1,.5+x*.38-y*.26))
  local grain=1+math.sin(x*19.7+y*13.1+id*2.73)*.045+math.sin(x*41.1-y*29.3+id*1.37)*.025
  local shade=limb*light*grain; local f=p.feature or ''
  if f=='band' or f=='rings' then shade=shade*(.94+.06*math.sin((y*11+id)*math.pi))
  elseif f=='storm' then shade=shade*(.93+.07*math.sin((x*8+y*15+id)*math.pi))
  elseif f=='pole' or f=='cap' or f=='ice' then shade=shade*(.95+.05*math.cos((y*7-id*.3)*math.pi)) end
  local craterStrength=(f=='band' or f=='storm') and .55 or .92
  for k=1,4 do
    local cx=-.58+phash(id*31.7+k*7.1)*1.16; local cy=-.56+phash(id*47.3+k*11.9)*1.12
    if cx*cx+cy*cy<.68 then
      local cr=.105+phash(id*59.9+k*13.7)*.115; local dx,dy=x-cx,y-cy; local q=math.sqrt(dx*dx+dy*dy)/cr
      if q<.68 then shade=shade*(1-craterStrength*(.18-.08*q/.68)) elseif q<1 then shade=shade*(1+craterStrength*.10*(1-(q-.68)/.32)) end
    end
  end
  shade=math.max(.30,math.min(1.15,shade)); local edge=math.max(0,math.min(1,(1-mu)*1.20))
  local pr=(r*(1-edge)+lr*edge)*shade;local pg=(g*(1-edge)+lg*edge)*shade;local pb=(b*(1-edge)+lb*edge)*shade
  if mu>.82 then local t=(mu-.82)/.18*.16;pr=pr*(1-t)+hr*t;pg=pg*(1-t)+hg*t;pb=pb*(1-t)+hb*t end
  return math.min(1,pr),math.min(1,pg),math.min(1,pb)
end
local function refDisc(p)
  local out={};local function emit(x,y)local r,g,b=pcolor(p,x,y);out[#out+1]={x,y,r,g,b} end
  local function tri(a,b,c,d,e,f)emit(a,b);emit(c,d);emit(e,f)end
  local rings,seg=7,40;local first=1/rings
  for j=0,seg-1 do local a0=j/seg*math.pi*2;local a1=(j+1)/seg*math.pi*2;tri(0,0,math.cos(a0)*first,math.sin(a0)*first,math.cos(a1)*first,math.sin(a1)*first)end
  for ri=1,rings-1 do local r0,r1=ri/rings,(ri+1)/rings;for j=0,seg-1 do local a0=j/seg*math.pi*2;local a1=(j+1)/seg*math.pi*2;local x00,y00=math.cos(a0)*r0,math.sin(a0)*r0;local x01,y01=math.cos(a1)*r0,math.sin(a1)*r0;local x10,y10=math.cos(a0)*r1,math.sin(a0)*r1;local x11,y11=math.cos(a1)*r1,math.sin(a1)*r1;tri(x00,y00,x10,y10,x11,y11);tri(x00,y00,x11,y11,x01,y01)end end
  return out
end
for _,p in ipairs(planets) do
  local a,b=refDisc(p),planetTpl(p);ok(#a==#b and #b==1560,'planet template vertex count')
  local same=#a==#b
  if same then for i=1,#a do for k=1,5 do if not near(a[i][k],b[i][k]) then same=false;break end end;if not same then break end end end
  ok(same,'planet template exact normalized geometry/color')
end
local function refSat()
  local cells=22;local rc,rs=math.cos(math.rad(30)),math.sin(math.rad(30));local back,front={},{}
  for iy=-cells,cells do for ix=-cells,cells do local u,v=ix/cells,iy/cells;local fx=u*rc-v*rs;local fy=u*rs+v*rc;local ed=math.sqrt(fx*fx+(fy/.58)^2);if ed>=.52 and ed<=1 then local t=(ed-.52)/.48;local gap=1;if t>.38 and t<.55 then gap=.10 end;if t>.70 and t<.78 then gap=.40 end;local q={fx,fy,gap};if fy>=0 then front[#front+1]=q elseif math.sqrt((fx*2.55)^2+(fy*1.20)^2)>=1.20 then back[#back+1]=q end end end end
  return {back=back,front=front}
end
local function cmpLists(a,b,nv)
  if #a~=#b then return false end
  for i=1,#a do for k=1,nv do if not near(a[i][k],b[i][k]) then return false end end end;return true
end
local sa,sb=refSat(),satTpl();ok(cmpLists(sa.back,sb.back,3) and cmpLists(sa.front,sb.front,3),'Saturn cached ring points exact')
local function refX(angle,scale)
  local cells=20;local rc,rs=math.cos(angle),math.sin(angle);local back,front={},{};local hide=scale*1.04
  for iy=-cells,cells do for ix=-cells,cells do local u,v=ix/cells,iy/cells;local fx=u*rc-v*rs;local fy=u*rs+v*rc;local ed=math.sqrt(fx*fx+(fy/.54)^2);if ed>=.54 and ed<=1 then local q={fx,fy};if fy>=0 then front[#front+1]=q elseif math.sqrt((fx*2.45)^2+(fy*1.08)^2)>=hide then back[#back+1]=q end end end end
  return {back=back,front=front}
end
for _,ang in ipairs{math.rad(45),math.rad(-45)} do local a,b=refX(ang,1.42),xTpl(ang,1.42);ok(cmpLists(a.back,b.back,2) and cmpLists(a.front,b.front,2),'Planet-X cached ring points exact') end
local mp=milky();ok(#mp==220,'Milky Way point count unchanged')
local same=true;local ct,st=math.cos(1.0821),math.sin(1.0821)
for j=1,220 do local lon=(j/220)*math.pi*2;local band=(math.sin(j*91.71)*43758.5453)%1;local off=(band-.5)*.18;local dx=math.cos(lon)*math.cos(off);local dy=math.sin(off);local dz=math.sin(lon)*math.cos(off);local ty=dy*ct-dz*st;local tz=dy*st+dz*ct;local a=.035+((j*37)%17)/17*.055;local q=mp[j];if not(near(q[1],dx) and near(q[2],ty) and near(q[3],tz) and near(q[4],a)) then same=false;break end end
ok(same,'Milky Way cached base points exact')
print(('8.1.24 night geometry equivalence: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
