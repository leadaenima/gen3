#!/usr/bin/env python3
from concurrent.futures import ThreadPoolExecutor, as_completed
import subprocess, sys, os
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
LUA=['cloud_pitch_stability_829_test.lua', 'weather_strength_particle_count_829_test.lua', 'cloud_zenith_repeat_8208_test.lua', 'celestial_cloud_gaps_8208_test.lua', 'all_weather_performance_8206_test.lua', 'snow_density_multipliers_8205_test.lua', 'snow_full_path_8204_test.lua', 'snow_lod_performance_8203_test.lua', 'snow_systems_performance_8203_test.lua', 'mobile_snow_sky_8202_test.lua', 'snow_mobile_performance_8201_test.lua', 'weather_cloud_rave_snow_8200_test.lua', 'snow_native_instance_id_8199_test.lua', 'weather_2d_repairs_8199_test.lua', 'rave_snow_continuity_8198_test.lua', 'pause_menu_weather_8196_test.lua', 'rave_fog_strobe_8195_test.lua', 'rave_music_8194_test.lua', 'rave_song_show_8194_test.lua', 'npc_lightning_battle_art_8193_test.lua', 'snow_render_distance_8192_test.lua', 'snow_fountain_guard_8191_test.lua', 'battle_art_current_water_8191_test.lua', 'feature_aware_gating_8190_test.lua', 'block_cloud_coherence_8190_test.lua', 'snow_fountain_guard_8190_test.lua', 'rave_show_8190_test.lua', 'weather_2d_restart_8189_test.lua', 'weather_world_interaction_8188_test.lua', 'world_interaction_precip_8188_test.lua', 'terrarium_integration_contract_8188_test.lua', 'weather_2d_options_sync_8188_test.lua', 'rave_weather_8186_test.lua', 'rave_laser_worldspace_8187_test.lua', 'battle_3d_weather_persistence_8187_test.lua', 'cloud_bank_style_8185_test.lua', 'weather_dual_selector_8184_test.lua', 'weather_catalogue_matrix_test.lua', '8118_weather_catalog_exhaustive_test.lua', 'weather_catalog_test.lua', 'typed_weather_test.lua', 'weather_2d_style_test.lua', 'render_pipeline_test.lua', 'strict_3d_compositor_test.lua', 'present_3d_test.lua', 'world_precip_worldspace_test.lua', 'world_precip_spawn_proof.lua', 'precip_virtualization_test.lua', 'feature_integrity_8183_test.lua', 'fronts_off_world_precip_8170_test.lua', 'fronts_off_render_distance_8171_test.lua', 'weather_render_distance_setting_8172_test.lua', 'fronts_off_continuous_precip_8174_test.lua', 'rain_walk_continuity_8175_test.lua', 'rain_ledge_continuity_8176_test.lua', 'rain_map_edge_turn_continuity_8177_test.lua', 'rain_rendered_world_8178_test.lua', 'snow_virtualization_test.lua', 'procedural_far_snow_test.lua', 'snow_motion_8155_test.lua', 'snow_intensity_pipeline_test.lua', 'snow_accumulation_setting_8169_test.lua', 'cloudbank_persistence_pitch_test.lua', 'rain_cloudbank_visibility_test.lua', 'storm_cloudbank_integration_8137_test.lua', 'front_audio_motion_cloud_8152_test.lua', 'front_entity_realism_8152_test.lua', 'lightning_burst_test.lua', 'world_lightning_worldspace_test.lua', 'npc_lightning_test.lua', 'npc_lightning_2d_8160_test.lua', 'tornado_3d_test.lua', 'tornado_waterspout_8158_test.lua', 'tornado_pickup_semantics_8163_test.lua', 'tornado_real_transfer_8161_test.lua', 'tornado_safe_destination_test.lua', 'tornado_remote_map_roam_8165_test.lua', 'tornado_remote_render_cull_8165_test.lua', 'celestial_engine_test.lua', 'celestial_star_field_test.lua', 'host_night_star_spawn_test.lua', '8124_night_geometry_equivalence_test.lua', 'celestial_motion_smoothing_test.lua', 'celestial_zenith_quality_test.lua', 'celestial_horizon_handoff_test.lua', 'celestial_sun_submission_test.lua', 'celestial_occlusion_brightness_test.lua', 'battle_art_public_water_8144_test.lua', 'voxel_nexus_water_8145_test.lua', 'connected_water_3d_test.lua', 'connected_water_test.lua', 'professional_water_8133_test.lua', 'complete_water_ownership_8136_test.lua', 'water_hotpath_8132_test.lua', 'water_player_safety_8136_test.lua', 'water_style_8131_test.lua', 'wind_engine_test.lua', 'wind_player_test.lua', 'audio_realtime_authority_test.lua', 'audio_indoor_test.lua', 'audio_thunder_voice_test.lua', 'battle_features_test.lua', 'battle_visual_authority_test.lua', 'battle_precip_continuity_8156_test.lua', 'season_cycle_leaf_sync_test.lua', 'leaf_collision_season_test.lua', 'rainbow_test.lua', 'gameplay_features_test.lua', 'debug_hud_test.lua', 'player_settings_8182_additions_test.lua', 'settings_runtime_test.lua', 'settings_live_chain_test.lua', 'player_settings_8149_complete_test.lua', 'player_settings_dedup_rave_8197_test.lua', 'settings_description_complete_test.lua', 'settings_menu_test.lua', 'settings_advanced_pipeline_test.lua']
PYTOOLS=['test_8208_celestial_3d_ownership.py', 'test_8208_snow_distance_taper.py', 'test_8207_private_3d_namespace.py', 'test_8207_battle_art_wet_compat.py', 'test_8207_procedural_snow_uniform.py', 'test_snow_hash_quality_8201.py', 'test_rave_song_bpm_sync_8194.py', 'test_sunset_halo.py', 'test_settings_runtime.py', 'revision_gate.py', 'test_performance_invariants.py', 'test_3d_pipeline_integrity.py', 'feature_audit.py', 'test_voxel_host_compat.py', 'test_love_sandbox.py']
def one(kind,name):
    if kind=='lua': cmd=['texlua',str(ROOT/'tests'/name)]
    elif kind=='py': cmd=[sys.executable,str(ROOT/'tools'/name)]
    else: cmd=[sys.executable,str(ROOT/'tools'/'test_mod.py'),'--lua']
    try:
        r=subprocess.run(cmd,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=90)
        return name,r.returncode,r.stdout
    except subprocess.TimeoutExpired as e:
        o=e.stdout or ''
        if isinstance(o,bytes):o=o.decode(errors='replace')
        return name,124,'TIMEOUT\n'+o
def main():
    jobs=[('lua',x) for x in LUA]+[('py',x) for x in PYTOOLS]+[('mod','test_mod.py --lua')]
    results=[]
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs={ex.submit(one,*j):j for j in jobs}
        for f in as_completed(futs):
            name,rc,o=f.result(); results.append((name,rc,o))
            print(('PASS ' if rc==0 else 'FAIL ')+name,flush=True)
            if rc!=0: print(o[-5000:],flush=True)
    fail=[r for r in results if r[1]!=0]
    print(f'8.2.9 parallel maintained developer sweep: {len(results)-len(fail)}/{len(results)} programs PASS',flush=True)
    return 1 if fail else 0
if __name__=='__main__':raise SystemExit(main())
