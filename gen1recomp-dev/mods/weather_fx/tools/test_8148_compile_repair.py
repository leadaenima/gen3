#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys,tempfile
R=Path(__file__).resolve().parents[1]; p=R/'lib/EngineRuntime.lua'; txt=p.read_text(); checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
ck('--   * Advisory SDK-only systems are computed on demand' in txt,'line-10 advisory bullet is a Lua comment')
ck('\n  * Advisory SDK-only systems are computed on demand' not in txt,'malformed uncommented bullet absent')
with tempfile.NamedTemporaryFile('w',suffix='.lua',delete=False) as sf:
    sf.write("local p=arg[1]; local f,e=loadfile(p); if not f then io.stderr:write(tostring(e)..'\\n'); os.exit(1) end\n")
    checker=sf.name
def comp(q): return subprocess.run(['texlua',checker,str(q)],capture_output=True,text=True)
r=comp(p); ck(r.returncode==0,'EngineRuntime.lua compiles')
bad=txt.replace('--   * Advisory SDK-only systems are computed on demand','  * Advisory SDK-only systems are computed on demand',1)
with tempfile.NamedTemporaryFile('w',suffix='.lua',delete=False) as f: f.write(bad); q=f.name
r2=comp(q); ck(r2.returncode!=0,'break-it-again malformed bullet is rejected by Lua compiler')
print(f'8.1.48 compile repair contract: {sum(checks)}/{len(checks)} passed'); sys.exit(0 if all(checks) else 1)
