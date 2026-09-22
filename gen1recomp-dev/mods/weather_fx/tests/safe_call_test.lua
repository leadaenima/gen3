local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

local warnings={}
local V={mod={log={warn=function(self,fmt,...)
  warnings[#warnings+1]=string.format(fmt,...)
end}}}
local Safe=assert(loadfile('lib/SafeCall.lua'))(V)
Safe.reset()
local call=Safe.bind('test')

local ok,a,b,c=call(function() return 7,nil,'tail' end)
check(ok==true and a==7 and b==nil and c=='tail','success preserves multiple returns including nil')
local ok2,err=call(function() error('boom',0) end)
check(ok2==false and tostring(err):find('boom',1,true)~=nil,'failure preserves protected-call false/error contract')
local st=Safe.stats()
check(st.calls==2 and st.failures==1,'global health counters record calls/failures')
check(st.scopes.test and st.scopes.test.calls==2 and st.scopes.test.failures==1,'per-scope health counters record failure')
check(st.lastScope=='test' and tostring(st.lastError):find('boom',1,true)~=nil,'last failure is diagnosable')
check(#warnings==1,'first failure is logged once')
call(function() error('boom',0) end)
check(#warnings==2,'second failure is logged at power-of-two threshold')
call(function() error('boom',0) end)
check(#warnings==2,'third repeated failure is rate-limited')
call(function() error('boom',0) end)
check(#warnings==3,'fourth repeated failure is logged at next power-of-two threshold')
local ok3,e3=call(nil)
check(ok3==false and tostring(e3):find('non%-function')~=nil,'non-function misuse fails closed and is recorded')

print(('safe call: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
