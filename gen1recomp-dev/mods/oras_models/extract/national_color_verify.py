from __future__ import annotations
import json
from pathlib import Path
from collections import defaultdict
from PIL import Image
import numpy as np

LIVE = Path(r"C:\Users\Feces\Desktop\backup pkmn\97 - Copy\gen1recomp-dev")
CACHE = Path(r"C:\Users\Feces\AppData\Roaming\Love\pokemon-love2d\oras_extract")
MESH_IDX = CACHE / "meshes" / "mesh_index.json"
TEX_ROOT = CACHE / "textures" / "a" / "0" / "0" / "8"
REPORT = LIVE / "tmp" / "oras_national_color_verify.txt"

SPOT = {
  1:"Bulbasaur",4:"Charmander",7:"Squirtle",16:"Pidgey",25:"Pikachu",
  43:"Oddish",44:"Gloom",45:"Vileplume",63:"Abra",74:"Geodude",92:"Gastly",
  129:"Magikarp",133:"Eevee",143:"Snorlax",144:"Articuno",145:"Zapdos",146:"Moltres",
  150:"Mewtwo",152:"Chikorita",155:"Cyndaquil",158:"Totodile",249:"Lugia",250:"Ho-Oh",
  252:"Treecko",255:"Torchic",258:"Mudkip",263:"Zigzagoon",280:"Ralts",
  303:"Mawile",334:"Altaria",382:"Kyogre",383:"Groudon",384:"Rayquaza",
  448:"Lucario",493:"Arceus",495:"Snivy",498:"Tepig",501:"Oshawott",
  643:"Reshiram",644:"Zekrom",
  716:"Xerneas",717:"Yveltal",718:"Zygarde",719:"Diancie",721:"Volcanion",
}
EXPECT_NOT_BLUE = {4,255,383,146,250,498,653}  # fire/red should not be blue
EXPECT_NOT_RED = {7,258,144}  # Kyogre BodyA is muted blue albedo (not BGR)  # water/ice should not be red-dominant BGR

def chroma(rgb):
  r,g,b=map(float,rgb); return abs(r-g)+abs(g-b)+abs(b-r)

def hue(rgb):
  r,g,b=[float(x)/255 for x in rgb]
  mx,mn=max(r,g,b),min(r,g,b)
  if mx<0.08: return "black"
  if mx-mn<0.08: return "white" if mx>0.85 else "grey"
  if r>=g and r>=b:
    if g>b*1.2 and g>0.35: return "orange" if r>g else "yellow"
    if b>g*1.15: return "pink" if r>0.5 else "purple"
    return "red" if r-max(g,b)>0.15 else "orange"
  if g>=r and g>=b: return "yellow" if r>0.45 else "green"
  if r>0.35 and b>0.4: return "purple"
  return "cyan" if g>0.35 else "blue"

def mean_opaque(path):
  im=np.array(Image.open(path).convert("RGBA"))
  op=im[im[:,:,3]>64][:,:3]
  if len(op)<16: return None
  return op.mean(0)

def sample_uv(im, uvs, n=32):
  h,w=im.shape[:2]
  if not uvs: return None
  if uvs and not isinstance(uvs[0], (list,tuple)):
    uvs=[(uvs[i],uvs[i+1]) for i in range(0,len(uvs)-1,2)]
  pts=uvs[::max(1,len(uvs)//n)][:n]
  cols=[]
  for u,v in pts:
    for vv in (v,1.0-v):
      x=int(max(0,min(w-1,round(float(u)*(w-1)))))
      y=int(max(0,min(h-1,round(float(vv)*(h-1)))))
      px=im[y,x]
      if px[3]>32:
        cols.append(px[:3].astype(np.float32)); break
  if len(cols)<4: return None
  return np.mean(cols,0)

def find_pm_sheet(pm, suffixes):
  # Prefer lower-numbered texture dirs (often the battle albedo pair)
  hits=[]
  for d in TEX_ROOT.iterdir():
    if not d.is_dir(): continue
    try: num=int(d.name)
    except: num=10**9
    for sfx in suffixes:
      p=d/f"{pm}_{sfx}"
      if p.is_file(): hits.append((num,p))
  hits.sort()
  return hits[0][1] if hits else None

def prefer_colorized(path: Path):
  for s in (path.with_name(path.stem+"_colorized.png"), path.with_name(path.stem+"_petal.png"), path):
    if s.is_file(): return s
  return path

def resolve_tex_path(hint: str):
  if not hint: return None
  # hints often like textures/a/0/0/8/0045/pm0004_00_Body1.png or absolute
  p=Path(hint)
  cands=[]
  if p.is_file(): cands.append(p)
  cands.append(CACHE/hint)
  cands.append(CACHE/"textures"/hint)
  # strip leading junk
  s=hint.replace("\\","/")
  if "textures/" in s:
    cands.append(CACHE/s[s.index("textures/"):])
  for c in cands:
    if c.is_file():
      return prefer_colorized(c)
  # by filename under known parent
  name=Path(hint).name
  parent=Path(hint).parent.name
  if parent and (TEX_ROOT/parent/name).is_file():
    return prefer_colorized(TEX_ROOT/parent/name)
  return None

def main():
  idx=json.loads(MESH_IDX.read_text(encoding="utf-8"))
  models=idx["models"]
  by=defaultdict(list)
  for r in models: by[r["national"]].append(r)

  lines=[]; flags=[]
  lines.append("=== ORAS national color VERIFY ===")
  lines.append(f"models_in_index={len(models)}")
  col=list(TEX_ROOT.glob("*/*_colorized.png")); pet=list(TEX_ROOT.glob("*/*_petal.png"))
  lines.append(f"sidecars colorized={len(col)} petal={len(pet)}")
  lines.append("")
  lines.append("=== Body albedo sheet means (form0) ===")

  for nat,name in sorted(SPOT.items()):
    rows=[r for r in by.get(nat,[]) if r.get("form",0)==0] or by.get(nat,[])
    if not rows:
      flags.append(f"MISSING_MESH nat={nat} {name}"); continue
    row=rows[0]
    pm=row.get("name") or f"pm{nat:04d}_00"
    sheet=find_pm_sheet(pm, ["Body1.png","BodyA1.png","BodyB1.png","BodyC1.png"])
    if not sheet:
      flags.append(f"NO_BODY_SHEET nat={nat} {name} pm={pm}"); continue
    m=mean_opaque(sheet)
    if m is None:
      flags.append(f"EMPTY_SHEET nat={nat} {name}"); continue
    hb=hue(m); ch=chroma(m)
    lines.append(f"  nat={nat:03d} {name:12s} mean=({int(m[0]):3d},{int(m[1]):3d},{int(m[2]):3d}) chroma={ch:5.1f} hue={hb:7s} {sheet.parent.name}/{sheet.name}")
    if nat in EXPECT_NOT_BLUE and hb in ("blue","cyan") and ch>40:
      flags.append(f"BGR_BLUE nat={nat} {name} hue={hb} mean={tuple(int(x) for x in m)} file={sheet}")
    if nat in EXPECT_NOT_RED and hb in ("red","orange") and m[0]>m[2]+50 and ch>40:
      flags.append(f"BGR_RED nat={nat} {name} hue={hb} mean={tuple(int(x) for x in m)} file={sheet}")

  lines.append("")
  lines.append("=== UV samples (key parts) ===")
  for nat,name in sorted(SPOT.items()):
    rows=[r for r in by.get(nat,[]) if r.get("form",0)==0] or by.get(nat,[])
    if not rows: continue
    row=rows[0]
    mp=Path(row["path"])
    if not mp.is_file():
      flags.append(f"NO_JSON nat={nat}"); continue
    md=json.loads(mp.read_text(encoding="utf-8"))
    for part in (md.get("meshes") or [])[:10]:
      pname=part.get("name") or "?"
      tex=part.get("texture") or ""
      tpath=part.get("texture_path") or ""
      is_petal=any(k in pname.lower() for k in ("petal","flower","blossom"))
      resolved=resolve_tex_path(tpath) or resolve_tex_path(tex)
      if resolved is None and tex:
        # search same pm folder via Body name
        pm=row.get("name") or f"pm{nat:04d}_00"
        base=Path(tex).name
        for d in TEX_ROOT.iterdir():
          if (d/base).is_file():
            resolved=prefer_colorized(d/base); break
      if resolved is None: continue
      # Body2 shadow fallback
      if "Body2" in resolved.name and not is_petal and "_colorized" not in resolved.name and "_petal" not in resolved.name:
        m2=mean_opaque(resolved)
        if m2 is not None and chroma(m2)<40:
          b1=resolved.with_name(resolved.name.replace("Body2","Body1"))
          if b1.is_file(): resolved=b1
      im=np.array(Image.open(resolved).convert("RGBA"))
      mean=sample_uv(im, part.get("uvs") or part.get("uv") or [])
      if mean is None: mean=mean_opaque(resolved)
      if mean is None: continue
      hb=hue(mean)
      lines.append(f"  nat={nat:03d} {name:12s} part={pname[:26]:26s} tex={resolved.name[:36]:36s} UV=({int(mean[0]):3d},{int(mean[1]):3d},{int(mean[2]):3d}) hue={hb}")
      if nat in EXPECT_NOT_BLUE and "Body" in resolved.name and "Nor" not in resolved.name and hb in ("blue","cyan") and chroma(mean)>50:
        flags.append(f"UV_BLUE nat={nat} part={pname} tex={resolved.name} mean={tuple(int(x) for x in mean)}")
      if nat in EXPECT_NOT_RED and "Body" in resolved.name and hb in ("red","orange") and mean[0]>mean[2]+50 and chroma(mean)>50:
        flags.append(f"UV_RED nat={nat} part={pname} tex={resolved.name} mean={tuple(int(x) for x in mean)}")

  lines.append("")
  lines.append(f"=== FLAGS ({len(flags)}) ===")
  if not flags: lines.append("  (none)")
  for f in flags: lines.append("  FLAG "+f)
  # sidecar sample
  lines.append("")
  lines.append("=== colorized/petal sample ===")
  for p in sorted(col+pet)[:50]:
    m=mean_opaque(p)
    if m is None: continue
    lines.append(f"  {p.parent.name}/{p.name} mean=({int(m[0])},{int(m[1])},{int(m[2])}) hue={hue(m)}")

  REPORT.write_text("\n".join(lines)+"\n", encoding="utf-8")
  print(f"wrote {REPORT}")
  print(f"flags={len(flags)} colorized={len(col)} petal={len(pet)}")
  for f in flags: print("FLAG", f)

if __name__=="__main__":
  main()
