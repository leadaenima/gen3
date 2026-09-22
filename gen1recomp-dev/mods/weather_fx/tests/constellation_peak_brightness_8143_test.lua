-- Weather FX 8.1.43 exact constellation peak-brightness regression.
local pass,fail=0,0
local function check(v,n) if v then pass=pass+1 else fail=fail+1;print('FAIL '..n) end end
local C=assert(loadfile('lib/Constellations.lua'))({})
local function luma(s) return .2126*(s.r or 0)+.7152*(s.g or 0)+.0722*(s.b or 0) end
local target=assert(C.PEAK_LUMA_TARGET)
check(#C.NAMES==25,'all 25 constellations are audited')
check(math.abs(target-.82)<1e-12,'shared peak colour-luminance target is 0.82')
local minPrimary,maxPrimary=1e9,-1
local minSecondary,maxSecondary=1e9,-1
local allPrimary,allSecondary=0,0
for _,name in ipairs(C.NAMES) do
  local bag=C.BY_NAME[name] or {}
  local localPrim,localSec=0,0
  check(math.abs((C.BRIGHTNESS_GAINS[name] or -1)-1)<1e-12,name..' has exact 1.0 constellation gain')
  for _,s in ipairs(bag) do
    check(math.abs(luma(s)-target)<1e-9,name..' star display luma is normalized')
    check((s.sourceR~=nil and s.sourceG~=nil and s.sourceB~=nil),name..' retains authored source colour for audit')
    check(math.abs((s.constGain or -1)-1)<1e-12,name..' star has no density brightness trim')
    local peak=(s.a or 0)*(s.constGain or 1)*luma(s)
    if s.primary then
      localPrim=localPrim+1; allPrimary=allPrimary+1
      check(math.abs((s.a or 0)-.96)<1e-12,name..' primary alpha is shared .96')
      if peak<minPrimary then minPrimary=peak end; if peak>maxPrimary then maxPrimary=peak end
    else
      localSec=localSec+1; allSecondary=allSecondary+1
      check(math.abs((s.a or 0)-.73)<1e-12,name..' secondary alpha is shared .73')
      if peak<minSecondary then minSecondary=peak end; if peak>maxSecondary then maxSecondary=peak end
    end
  end
  check(localPrim>0,name..' has at least one primary landmark star')
  check(localSec>0,name..' has at least one secondary trace star')
end
check(allPrimary>0 and allSecondary>0,'both brightness hierarchy tiers are populated')
check((maxPrimary-minPrimary)<1e-9,'all 25 constellations have identical unobstructed primary peak brightness')
check((maxSecondary-minSecondary)<1e-9,'all 25 constellations have identical unobstructed secondary peak brightness')
check(math.abs(minPrimary-(.96*target))<1e-9,'primary peak resolves to exact shared target')
check(math.abs(minSecondary-(.73*target))<1e-9,'secondary peak resolves to exact shared target')
print(string.format('constellation peak brightness 8.1.43: %d passed, %d failed; primary=%.9f secondary=%.9f stars=%d',pass,fail,minPrimary,minSecondary,allPrimary+allSecondary))
os.exit(fail==0 and 0 or 1)
