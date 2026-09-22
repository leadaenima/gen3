#!/usr/bin/env python3
from pathlib import Path
import subprocess, sys
R=Path(__file__).resolve().parents[1]
checks=[
 ('lua','tests/player_settings_8149_complete_test.lua'),
 ('lua','tests/settings_runtime_test.lua'),
 ('lua','tests/settings_advanced_pipeline_test.lua'),
 ('lua','tests/settings_menu_test.lua'),
 ('lua','tests/settings_description_complete_test.lua'),
 ('lua','tests/settings_live_chain_test.lua'),
 ('py','tools/test_settings_runtime.py'),
 ('py','tools/test_818_settings_time_contract.py'),
 ('lua','tests/quality_presets_8146_test.lua'),
 ('lua','tests/quality_live_3d_test.lua'),
 ('lua','tests/quality_immediate_3d_test.lua'),
 ('lua','tests/render_pipeline_test.lua'),
 ('lua','tests/weather_state_authority_test.lua'),
 ('lua','tests/intensity_control_response_test.lua'),
 ('lua','tests/snow_intensity_pipeline_test.lua'),
 ('py','tools/test_fog_intensity.py'),
 ('lua','tests/timeofday_setting_test.lua'),
 ('lua','tests/season_cycle_leaf_sync_test.lua'),
 ('lua','tests/cloudbank_persistence_pitch_test.lua'),
 ('lua','tests/storm_front_scale_render_8141_test.lua'),
 ('lua','tests/water_style_8131_test.lua'),
 ('lua','tests/battle_features_test.lua'),
 ('lua','tests/battle_visual_authority_test.lua'),
 ('lua','tests/battle_art_test.lua'),
 ('lua','tests/audio_realtime_authority_test.lua'),
 ('lua','tests/audio_indoor_muffle_test.lua'),
 ('lua','tests/npc_lightning_test.lua'),
 ('lua','tests/tornado_3d_test.lua'),
 ('lua','tests/tornado_safe_destination_test.lua'),
 ('lua','tests/mesoscale_weather_test.lua'),
 ('lua','tests/storm_front_reachability_8141_test.lua'),
 ('lua','tests/wind_player_test.lua'),
 ('lua','tests/rainbow_test.lua'),
 ('lua','tests/smooth_sky_test.lua'),
 ('lua','tests/celestial_engine_test.lua'),
 ('lua','tests/winter_aurora_8142_test.lua'),
 ('lua','tests/gameplay_features_test.lua'),
 ('lua','tests/debug_hud_test.lua'),
 ('lua','tests/strict_3d_compositor_test.lua'),
 ('lua','tests/procedural_precip_field_test.lua'),
 ('lua','tests/precip_virtualization_test.lua'),
 ('lua','tests/world_precip_worldspace_test.lua'),
 ('lua','tests/world_precip_spawn_proof.lua'),
 ('lua','tests/weather_2d_style_test.lua'),
 ('py','tools/test_8121_player_controls.py'),
 ('py','tools/test_3d_pipeline_integrity.py'),
 ('py','tools/test_voxel_host_compat.py'),
 ('py','tools/test_strict_3d_present.py'),
 ('py','tools/test_camera_modes.py'),
]
results=[]
for kind,rel in checks:
    cmd=['texlua',str(R/rel)] if kind=='lua' else [sys.executable,str(R/rel)]
    
    try:
        p=subprocess.run(cmd,cwd=R,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=20)
    except subprocess.TimeoutExpired as e:
        out=((e.stdout or b'').decode(errors='ignore') if isinstance(e.stdout,(bytes,bytearray)) else (e.stdout or ''))
        class P: pass
        p=P(); p.returncode=124; p.stdout=out+'\nTIMEOUT after 20 seconds'

    tail=' | '.join([x.strip() for x in p.stdout.splitlines()[-3:] if x.strip()])
    results.append((rel,p.returncode,tail))
    print(('PASS' if p.returncode==0 else 'FAIL'),rel,tail,flush=True)
failed=[x for x in results if x[1]!=0]
print(f'\n8.1.49 player-settings executable suite: {len(results)-len(failed)}/{len(results)} test programs passed')
if failed:
    print('Failures:')
    for rel,rc,out in failed: print(' -',rel,'rc=',rc,out)
sys.exit(1 if failed else 0)
