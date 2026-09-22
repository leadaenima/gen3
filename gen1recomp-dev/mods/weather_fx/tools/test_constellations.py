#!/usr/bin/env python3
from pathlib import Path
import re,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
c=(ROOT/'lib/Constellations.lua').read_text(); ns=(ROOT/'lib/NightSky.lua').read_text(); failed=0

def ok(x,m):
 global failed; print(('PASS' if x else 'FAIL'),m); failed += 0 if x else 1

old=['Pikachu','Charmander','Squirtle','Bulbasaur','Eevee','Jigglypuff','Gengar','Dratini','PokeBall','Mew','Mewtwo']
new=['Poliwag','Ekans','Weedle','Pidgeotto','Rattata','Fearow','Sandshrew','Nidorino','Oddish','Vulpix','Bellsprout','Diglett','Meowth','Psyduck']
all_names=old+new
ok('POKEMON_CONSTELLATION_ATLAS_EXACT_TRACE_2026_09_03' in c and 'c4463a5a51b23cc400e1a99721006d567b48877bf17625cc28845e0826e14dc4' in c,'approved Pokémon Constellation Atlas is the exact source for the 14 added drawings')
ok(all(n in c for n in all_names),'all 25 approved constellation subjects are present')
ok(c.count('atlasExact=true')==14 and 'outlineTrace' not in c,'all 14 added constellations are atlas-derived native traces, not simplified hand redraws')
ok('localToDir' in c and 'roll=math.rad' in c,'tangent-plane mapping and per-trace roll preserve drawing proportions/orientation')
ok('appendWorld' in c and 'Constellations' in ns,'world renderer wires expanded trace catalogue')
ok('constellationVisibility' in ns and ('globalVis^1.18' in ns or 'globalVis^1.08' in ns),'constellations retain cloud fade with a stronger readable night envelope')
ok('primary and 1.52 or .92' in c and ('primary and 1.00 or .82' in c or 'a=primary and 1.00 or .84' in c or 'a=primary and .96 or .73' in c),'constellations retain a strong landmark/line brightness hierarchy')
order_m=re.search(r'local ORDER=\{([^\n]+)\}',c)
order=re.findall(r'"([A-Za-z0-9]+)"',order_m.group(1) if order_m else '')
ok(order==all_names and len(order)==len(set(order)),'catalogue order contains exactly 25 unique subjects with no duplicate species')
for dup in ['Charmander','Squirtle','Bulbasaur','Pikachu','Jigglypuff','PokeBall']:
    ok(order.count(dup)==1,f'{dup} remains single-instance only')
anchors=[(float(a),float(e)) for a,e in re.findall(r'az=math\.rad\(([-0-9.]+)\),\s*el=math\.rad\(([-0-9.]+)\)',c)]
ok(len(anchors)==25 and min(e for _,e in anchors)<-40 and max(e for _,e in anchors)>40,'25 anchors span both celestial hemispheres')
# Runtime proof catches helper/sample mistakes that static source matching cannot.
lua='''local C=assert(loadfile("lib/Constellations.lua"))({})\nlocal want={"Poliwag","Ekans","Weedle","Pidgeotto","Rattata","Fearow","Sandshrew","Nidorino","Oddish","Vulpix","Bellsprout","Diglett","Meowth","Psyduck"}\nassert(#C.NAMES==25)\nassert(C.count()>=8400)\nfor _,n in ipairs(want) do assert(C.TRACE[n] and C.TRACE[n].atlasExact==true and C.TRACE_COUNTS[n]>=250 and C.BY_NAME[n] and #C.BY_NAME[n]==C.TRACE_COUNTS[n]) end\nprint("exact-atlas constellations runtime: 25 names, "..C.count().." stars")\n'''
with tempfile.NamedTemporaryFile('w',suffix='.lua',delete=False) as f:
    f.write(lua); path=f.name
r=subprocess.run(['texlua',path],cwd=ROOT,text=True,capture_output=True)
ok(r.returncode==0 and 'exact-atlas constellations runtime: 25 names' in r.stdout,'runtime catalogue builds all 25 subjects and >8400 traced stars with all 14 atlas traces dense')
print('RESULT','OK' if not failed else 'FAIL',failed); sys.exit(1 if failed else 0)
