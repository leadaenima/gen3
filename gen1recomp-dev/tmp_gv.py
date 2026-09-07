path="src/core/GameVersion.lua"
text=open(path,encoding="utf-8",errors="replace").read()
for i,line in enumerate(text.splitlines(),1):
    if "cache" in line.lower() or "prefix" in line.lower() or "ruby" in line.lower():
        if i<200 or "cachePrefix" in line or "ruby" in line:
            print(f"{i}:{line}")
