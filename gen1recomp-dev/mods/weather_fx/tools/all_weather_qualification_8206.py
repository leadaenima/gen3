#!/usr/bin/env python3
from pathlib import Path
import subprocess, sys
ROOT=Path(__file__).resolve().parent.parent
checks=[
 ('lua','rave_removed_8214_test.lua'),
 ('lua','all_weather_performance_8206_test.lua'),
 ('lua','precip_virtualization_test.lua'),
 ('lua','snow_full_path_8204_test.lua'),
 ('lua','snow_lod_performance_8203_test.lua'),
 ('lua','fog_ownership_matrix_test.lua'),
 ('lua','water_hotpath_8132_test.lua'),
 ('lua','tornado_remote_render_cull_8165_test.lua'),
 ('lua','world_lightning_worldspace_test.lua'),
 ('lua','battle_3d_weather_persistence_8187_test.lua'),
 ('lua','cloudbank_persistence_pitch_test.lua'),
 ('lua','rain_cloudbank_visibility_test.lua'),
 ('lua','block_cloud_coherence_8190_test.lua'),
 ('lua','celestial_zenith_quality_test.lua'),
 ('lua','8118_celestial_stress_test.lua'),
 ('lua','rain_walk_continuity_8175_test.lua'),
 ('lua','rain_ledge_continuity_8176_test.lua'),
 ('lua','rain_map_edge_turn_continuity_8177_test.lua'),
 ('lua','rain_rendered_world_8178_test.lua'),
 ('lua','sand_pitch_invariance_test.lua'),
 ('lua','leaf_collision_season_test.lua'),
 ('py','test_performance_invariants.py'),
 ('py','test_3d_pipeline_integrity.py'),
 ('py','test_voxel_host_compat.py'),
]
passed=0
for kind,name in checks:
    cmd=['texlua',str(ROOT/'tests'/name)] if kind=='lua' else [sys.executable,str(ROOT/'tools'/name)]
    try:
        r=subprocess.run(cmd,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=180)
    except subprocess.TimeoutExpired as e:
        out=e.stdout or ''
        if isinstance(out,bytes): out=out.decode(errors='replace')
        print(f'FAIL {name} TIMEOUT')
        print(out[-3000:])
        continue
    if r.returncode==0:
        passed+=1
        last=[x for x in r.stdout.splitlines() if x.strip()]
        print(f'PASS {name}' + (f' :: {last[-1]}' if last else ''))
    else:
        print(f'FAIL {name} rc={r.returncode}')
        print(r.stdout[-5000:])
print(f'Weather FX 8.2.14 all-weather qualification: {passed}/{len(checks)} programs PASS')
raise SystemExit(0 if passed==len(checks) else 1)
