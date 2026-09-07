import re, os, json

ROOT = r"C:\Users\Feces\Desktop\pkmn gen1recomp\gen1recomp-dev"
PR = os.path.join(ROOT, r"misc\pokeruby-master\pokeruby-master")
OUT = os.path.join(ROOT, r"src\data\battle_tower.lua")

def parse_defines(path, prefixes):
    defs = {}
    text = open(path, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"#define\s+(\w+)\s+(0x[0-9A-Fa-f]+|\d+)", text):
        name, val = m.group(1), int(m.group(2), 0)
        if any(name.startswith(p) for p in prefixes):
            defs[name] = val
    return defs

def parse_enum(path, start_token):
    text = open(path, encoding="utf-8", errors="replace").read()
    idx = text.find(start_token)
    if idx < 0:
        raise SystemExit("enum start not found: " + start_token)
    # find preceding "enum {"
    brace = text.rfind("enum", 0, idx)
    start = text.find("{", brace)
    end = text.find("};", start)
    body = text[start+1:end]
    out = {}
    i = 0
    for line in body.splitlines():
        line = line.strip().rstrip(",")
        if not line or line.startswith("//") or line.startswith("/*"):
            continue
        if "=" in line:
            name, rhs = line.split("=", 1)
            name = name.strip()
            rhs = rhs.strip().split()[0].rstrip(",")
            i = int(rhs, 0) if re.match(r"0x|[0-9]", rhs) else out.get(rhs, i)
        else:
            name = line.split()[0]
        out[name] = i
        i += 1
    return out

species = parse_defines(os.path.join(PR, r"include\constants\species.h"), ["SPECIES_"])
moves = parse_defines(os.path.join(PR, r"include\constants\moves.h"), ["MOVE_"])
items = parse_defines(os.path.join(PR, r"include\constants\items.h"), ["ITEM_"])
facility = parse_enum(os.path.join(PR, r"include\constants\trainers.h"), "FACILITY_CLASS_AQUA_LEADER")
objgfx = parse_defines(os.path.join(PR, r"include\constants\event_objects.h"), ["OBJ_EVENT_GFX_"])
bt_items = parse_enum(os.path.join(PR, r"include\battle_tower.h"), "BATTLE_TOWER_ITEM_NONE")
ev = parse_enum(os.path.join(PR, r"include\battle_tower.h"), "F_EV_SPREAD_HP")

# held item table from battle_tower.c
bt_c = open(os.path.join(PR, r"src\battle_tower.c"), encoding="utf-8", errors="replace").read()
m = re.search(r"sBattleTowerHeldItems\[\]\s*=\s*\{([^}]+)\}", bt_c)
held = []
for name in re.findall(r"(ITEM_\w+)", m.group(1)):
    held.append(items[name])

# male/female class + gfx tables
def parse_u8_table(name):
    mm = re.search(rf"{name}\[\]\s*=\s*\{{([^}}]+)\}}", bt_c)
    return [x.strip() for x in re.findall(r"(FACILITY_CLASS_\w+|OBJ_EVENT_GFX_\w+)", mm.group(1))]

male_classes = [facility[n] for n in parse_u8_table("sMaleTrainerClasses")]
female_classes = [facility[n] for n in parse_u8_table("sFemaleTrainerClasses")]
male_gfx = [objgfx[n] for n in parse_u8_table("sMaleTrainerGfxIds")]
female_gfx = [objgfx[n] for n in parse_u8_table("sFemaleTrainerGfxIds")]

FACILITY_NAMES = {
    "FACILITY_CLASS_YOUNGSTER": "YOUNGSTER",
    "FACILITY_CLASS_BIRD_KEEPER": "BIRD KEEPER",
    "FACILITY_CLASS_LADY": "LADY",
    "FACILITY_CLASS_BLACK_BELT": "BLACK BELT",
    "FACILITY_CLASS_NINJA_BOY": "NINJA BOY",
    "FACILITY_CLASS_SCHOOL_KID_F": "SCHOOL KID",
    "FACILITY_CLASS_SCHOOL_KID_M": "SCHOOL KID",
    "FACILITY_CLASS_RICH_BOY": "RICH BOY",
    "FACILITY_CLASS_BUG_CATCHER": "BUG CATCHER",
    "FACILITY_CLASS_FISHERMAN": "FISHERMAN",
    "FACILITY_CLASS_CAMPER": "CAMPER",
    "FACILITY_CLASS_PICNICKER": "PICNICKER",
    "FACILITY_CLASS_TUBER_M": "TUBER",
    "FACILITY_CLASS_TUBER_F": "TUBER",
    "FACILITY_CLASS_HIKER": "HIKER",
    "FACILITY_CLASS_LASS": "LASS",
    "FACILITY_CLASS_BEAUTY": "BEAUTY",
    "FACILITY_CLASS_AROMA_LADY": "AROMA LADY",
    "FACILITY_CLASS_HEX_MANIAC": "HEX MANIAC",
    "FACILITY_CLASS_RUIN_MANIAC": "RUIN MANIAC",
    "FACILITY_CLASS_POKEMANIAC": "POKeMANIAC",
    "FACILITY_CLASS_SWIMMER_M": "SWIMMER",
    "FACILITY_CLASS_SWIMMER_F": "SWIMMER",
    "FACILITY_CLASS_GUITARIST": "GUITARIST",
    "FACILITY_CLASS_KINDLER": "KINDLER",
    "FACILITY_CLASS_BUG_MANIAC": "BUG MANIAC",
    "FACILITY_CLASS_PSYCHIC_M": "PSYCHIC",
    "FACILITY_CLASS_PSYCHIC_F": "PSYCHIC",
    "FACILITY_CLASS_GENTLEMAN": "GENTLEMAN",
    "FACILITY_CLASS_POKEFAN_M": "POKeFAN",
    "FACILITY_CLASS_POKEFAN_F": "POKeFAN",
    "FACILITY_CLASS_EXPERT_M": "EXPERT",
    "FACILITY_CLASS_EXPERT_F": "EXPERT",
    "FACILITY_CLASS_COOL_TRAINER_M": "COOLTRAINER",
    "FACILITY_CLASS_COOL_TRAINER_F": "COOLTRAINER",
    "FACILITY_CLASS_CYCLING_TRIATHLETE_M": "TRIATHLETE",
    "FACILITY_CLASS_CYCLING_TRIATHLETE_F": "TRIATHLETE",
    "FACILITY_CLASS_RUNNING_TRIATHLETE_M": "TRIATHLETE",
    "FACILITY_CLASS_RUNNING_TRIATHLETE_F": "TRIATHLETE",
    "FACILITY_CLASS_SWIMMING_TRIATHLETE_M": "TRIATHLETE",
    "FACILITY_CLASS_SWIMMING_TRIATHLETE_F": "TRIATHLETE",
    "FACILITY_CLASS_DRAGON_TAMER": "DRAGON TAMER",
    "FACILITY_CLASS_BATTLE_GIRL": "BATTLE GIRL",
    "FACILITY_CLASS_PARASOL_LADY": "PARASOL LADY",
    "FACILITY_CLASS_SAILOR": "SAILOR",
    "FACILITY_CLASS_COLLECTOR": "COLLECTOR",
    "FACILITY_CLASS_POKEMON_BREEDER_M": "PKMN BREEDER",
    "FACILITY_CLASS_POKEMON_BREEDER_F": "PKMN BREEDER",
    "FACILITY_CLASS_POKEMON_RANGER_M": "PKMN RANGER",
    "FACILITY_CLASS_POKEMON_RANGER_F": "PKMN RANGER",
}
facility_name_by_id = {}
for k,v in facility.items():
    facility_name_by_id[v] = FACILITY_NAMES.get(k, k.replace("FACILITY_CLASS_", "").replace("_", " "))

def parse_trainers(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    trainers = []
    for block in re.finditer(r"\{\s*\.trainerClass\s*=\s*(FACILITY_CLASS_\w+)\s*,\s*\.name\s*=\s*_\(\"([^\"]+)\"\)\s*,\s*\.teamFlags\s*=\s*(0x[0-9A-Fa-f]+|\d+)\s*,\s*\.greeting\s*=\s*\{([^}]+)\}\s*,\s*\}", text, re.S):
        cls, name, flags, greet = block.groups()
        trainers.append({
            "trainerClass": facility[cls],
            "name": name,
            "teamFlags": int(flags, 0),
            "className": facility_name_by_id[facility[cls]],
        })
    return trainers

def parse_mons(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    mons = []
    # split on species entries
    for block in re.finditer(
        r"\{\s*\.species\s*=\s*(SPECIES_\w+)\s*,\s*\.heldItem\s*=\s*(BATTLE_TOWER_ITEM_\w+)\s*,\s*\.teamFlags\s*=\s*(0x[0-9A-Fa-f]+|\d+)\s*,\s*\.moves\s*=\s*\{([^}]+)\}\s*,\s*\.evSpread\s*=\s*([^,\n]+),\s*\.nature\s*=\s*(NATURE_\w+)\s*,\s*\}",
        text, re.S):
        sp, hi, flags, moves_body, evs, nature = block.groups()
        mv = []
        for tok in re.findall(r"MOVE_\w+", moves_body):
            mv.append(moves[tok])
        while len(mv) < 4:
            mv.append(0)
        # evaluate evSpread expression
        expr = evs.strip()
        val = 0
        for part in expr.split("|"):
            part = part.strip()
            if part in ev:
                val |= ev[part]
            elif part.startswith("F_EV_SPREAD"):
                raise SystemExit("unknown ev " + part)
            else:
                val |= int(part, 0)
        mons.append({
            "species": species[sp],
            "heldItem": bt_items[hi],  # index into held table
            "teamFlags": int(flags, 0),
            "moves": mv,
            "evSpread": val,
        })
    return mons

trainers = parse_trainers(os.path.join(PR, r"src\data\battle_tower\trainers.h"))
mons50 = parse_mons(os.path.join(PR, r"src\data\battle_tower\level_50_mons.h"))
mons100 = parse_mons(os.path.join(PR, r"src\data\battle_tower\level_100_mons.h"))
print("trainers", len(trainers), "mons50", len(mons50), "mons100", len(mons100))
assert len(trainers) >= 100, len(trainers)
assert len(mons50) >= 300, len(mons50)

def lua_list(nums):
    return "{" + ", ".join(str(int(n)) for n in nums) + "}"

def emit_trainer(t):
    return ("  { trainerClass = %d, teamFlags = %d, name = %s, className = %s }"
            % (t["trainerClass"], t["teamFlags"], json.dumps(t["name"]), json.dumps(t["className"])))

def emit_mon(m):
    return ("  { species = %d, heldItem = %d, teamFlags = %d, evSpread = %d, moves = %s }"
            % (m["species"], m["heldItem"], m["teamFlags"], m["evSpread"], lua_list(m["moves"])))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("-- Generated from misc/pokeruby-master battle_tower data. DO NOT EDIT BY HAND.\n")
    f.write("-- Used by Game3 Battle Tower lobby specials.\n")
    f.write("return {\n")
    f.write("  EREADER_TRAINER_ID = 200,\n")
    f.write("  RECORD_MIXING_BASE_ID = 100,\n")
    f.write("  heldItems = %s,\n" % lua_list(held))
    f.write("  maleClasses = %s,\n" % lua_list(male_classes))
    f.write("  femaleClasses = %s,\n" % lua_list(female_classes))
    f.write("  maleGfx = %s,\n" % lua_list(male_gfx))
    f.write("  femaleGfx = %s,\n" % lua_list(female_gfx))
    f.write("  trainers = {\n")
    # 0-based; Lua arrays are 1-based so store explicitly with [0]= via hash? 
    # Use 1-based with id field, or use [0] syntax in Lua.
    for i, t in enumerate(trainers):
        f.write("    [%d] = %s,\n" % (i, emit_trainer(t).strip()))
    f.write("  },\n")
    f.write("  level50Mons = {\n")
    for i, m in enumerate(mons50):
        f.write("    [%d] = %s,\n" % (i, emit_mon(m).strip()))
    f.write("  },\n")
    f.write("  level100Mons = {\n")
    for i, m in enumerate(mons100):
        f.write("    [%d] = %s,\n" % (i, emit_mon(m).strip()))
    f.write("  },\n")
    f.write("}\n")
print("wrote", OUT, "bytes", os.path.getsize(OUT))
