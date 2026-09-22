#!/usr/bin/env python3
from pathlib import Path
import json,re,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.49','manifest 8.1.49')
ck((R/'BASELINE').read_text().strip()=='8.1.49','BASELINE 8.1.49')
for f in [
 'RELEASE-NOTES-8.1.49.md','PLAYER-SETTINGS-AUDIT-8.1.49.md',
 'tools/test_8149_runtime_delta.py','tools/test_8149_runtime_freeze.py','tools/test_8149_package_surface.py',
 'tools/run_8149_player_settings_audit.py','tests/player_settings_8149_complete_test.lua',
 'tools/baselines/8.1.48-runtime-sha256.json','tools/baselines/8.1.49-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
settings=(R/'lib/Settings.lua').read_text(); menu=(R/'lib/SettingsMenu.lua').read_text()
ck('Settings.GROUPS' in settings and settings.count('id="')>=11,'grouped settings schema present')
ck('AUTO ADJUSTMENT' in settings,'plain-language AUTO label present')
ck('WX ENCOUNTERS' not in settings+menu,'WX ENCOUNTERS removed from player surface')
ck('SFX' not in '\n'.join(re.findall(r'label\s*=\s*"([^"]+)"',settings)),'SFX removed from setting labels')
ck('{ \"DEFAULT\", \"config\" }' in settings and 'DEFAULT' in settings,'internal config value is player-labeled DEFAULT')
ck('description=row.help' in menu and 'desc=row.help' in menu,'descriptions published to premium UI fields')
ck('Gen 2-capable games' in settings and 'Raikou' in settings and 'Celebi' in settings,'Legendary Events description matches Gen 2 support')
# Schema should expose exactly 68 unique setting keys.
keys=re.findall(r'key\s*=\s*"([A-Za-z0-9_]+)"',settings)
# Restrict to first definition of each key; Settings.lua also references key strings later.
schema_start=settings.find('Settings.SCHEMA')
groups_start=settings.find('Settings.GROUPS')
schema=settings[schema_start:groups_start]
schema_keys=re.findall(r'key\s*=\s*"([A-Za-z0-9_]+)"',schema)
ck(len(schema_keys)==68 and len(set(schema_keys))==68,'68 unique player settings')
groups=settings[groups_start:settings.find('function Settings.row',groups_start)]
group_ids=re.findall(r'\{\s*id="([^"]+)"',groups)
ck(len(group_ids)==11 and len(set(group_ids))==11,'11 shallow setting categories')
rn=(R/'RELEASE-NOTES-8.1.49.md').read_text(); audit=(R/'PLAYER-SETTINGS-AUDIT-8.1.49.md').read_text()
ck('68/68' in audit and '314/314' in audit and '49 / 49' in audit,'audit records complete setting and real-host coverage')
ck('ALSA' in audit and 'does **not** claim a human listening test' in audit,'audio honesty boundary documented')
print(f'8.1.49 package surface: {sum(checks)}/{len(checks)} passed')
sys.exit(0 if all(checks) else 1)
