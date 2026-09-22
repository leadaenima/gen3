#!/usr/bin/env python3
"""Run full Weather FX tool + test suite. Use after every revision."""
from __future__ import annotations
import subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def run(script, extra=None):
    print(f"\n===== {script} =====")
    cmd = [sys.executable, str(HERE / script)]
    if extra:
        cmd.extend(extra)
    r = subprocess.run(cmd)
    return r.returncode

def main():
    want_lua = "--lua" in sys.argv[1:]
    codes = []
    # 8.2.14: former RAVE weather and all of its runtime/assets/settings must stay removed.
    codes.append(("rave_removed_8214_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "rave_removed_8214_test.lua")], cwd=HERE.parent)))
    # 8.2.4: exhaustive snow path audit covers GPU success/failure plus accumulation OFF/ON.
    codes.append(("snow_full_path_8204_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_full_path_8204_test.lua")], cwd=HERE.parent)))
    # 8.2.3: mobile-first spatial snow LOD plus cached snow-only ground systems.
    codes.append(("snow_lod_performance_8203_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_lod_performance_8203_test.lua")], cwd=HERE.parent)))
    codes.append(("snow_systems_performance_8203_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_systems_performance_8203_test.lua")], cwd=HERE.parent)))
    # 8.1.99: dense GLSL3 snow/blizzard uses native instance ids so high-count
    # seed-window replay cannot collapse into a player-following fountain.
    codes.append(("snow_native_instance_id_8199_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_native_instance_id_8199_test.lua")], cwd=HERE.parent)))
    # 8.1.89: unchanged repeated WEATHER broadcasts must never reapply/restart
    # the active 2D pipeline. A real player change still applies exactly once.
    codes.append(("weather_2d_restart_8189_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "weather_2d_restart_8189_test.lua")], cwd=HERE.parent)))
    # Current 8.1.83 developer-sweep regression first: reversible OFF, smooth
    # 3D snow, rendered-world grain coverage, 3D battle ownership and sun glare.
    codes.append(("feature_integrity_8183_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "feature_integrity_8183_test.lua")], cwd=HERE.parent)))
    # 8.1.82 player-control additions remain mandatory.
    codes.append(("player_settings_8182_additions_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "player_settings_8182_additions_test.lua")], cwd=HERE.parent)))
    # 8.1.81 zero-quality-loss CPU/GPU/RAM/VRAM resource gate remains mandatory.
    codes.append(("resource_efficiency_8181_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "resource_efficiency_8181_test.lua")], cwd=HERE.parent)))
    # 8.1.80 frame-spatial/runtime reuse remains mandatory.
    codes.append(("performance_frame_reuse_8180_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "performance_frame_reuse_8180_test.lua")], cwd=HERE.parent)))
    # Current 8.1.76 rain ledge/draw/model continuity gate first.
    codes.append(("rain_ledge_continuity_8176_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "rain_ledge_continuity_8176_test.lua")], cwd=HERE.parent)))
    codes.append(("rain_walk_continuity_8175_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "rain_walk_continuity_8175_test.lua")], cwd=HERE.parent)))
    # 8.1.74 fronts-OFF uniform precipitation remains mandatory.
    codes.append(("fronts_off_continuous_precip_8174_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "fronts_off_continuous_precip_8174_test.lua")], cwd=HERE.parent)))
    # 8.1.73 streaming/map-entry/fountain behavior remains mandatory.
    codes.append(("precip_streaming_8173_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "precip_streaming_8173_test.lua")], cwd=HERE.parent)))
    codes.append(("snow_fountain_preflight_8173_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_fountain_preflight_8173_test.lua")], cwd=HERE.parent)))
    # Current 8.1.69 player-facing snow-accumulation toggle gates first.
    codes.append(("test_8169_runtime_delta.py", run("test_8169_runtime_delta.py")))
    codes.append(("test_8169_runtime_freeze.py", run("test_8169_runtime_freeze.py")))
    codes.append(("test_8169_package_surface.py", run("test_8169_package_surface.py")))
    codes.append(("test_8169_setting_contract.py", run("test_8169_setting_contract.py")))
    codes.append(("snow_accumulation_setting_8169_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_accumulation_setting_8169_test.lua"), str(HERE.parent)], cwd=HERE.parent)))

    # 8.1.68 distributed/coalesced snow-bank behavior remains mandatory.
    # Historical exact 8.1.68 delta/freeze/package gates are superseded by 8.1.69.
    codes.append(("test_8168_snowbank_contract.py", run("test_8168_snowbank_contract.py")))
    codes.append(("snow_bank_distribution_8168_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_bank_distribution_8168_test.lua"), str(HERE.parent)], cwd=HERE.parent)))

    # 8.1.67 live-ledges / tornado-frequency / independent-celestial behavior remains mandatory.
    # Historical exact 8.1.67 delta/freeze/package gates are superseded by 8.1.68.
    codes.append(("test_8167_contract.py", run("test_8167_contract.py")))
    for name in ["tornado_2d_frequency_8167_test.lua","celestial_2d_worldlock_8167_test.lua","celestial_presentation_setting_8167_test.lua","snow_live_surface_alignment_8167_test.lua"]:
        codes.append((name, subprocess.call(["texlua", str(HERE.parent / "tests" / name)], cwd=HERE.parent)))

    # 8.1.66 surface-conformal repaint and exact tree-hull behavior remain mandatory.
    # Historical 8.1.66 delta/freeze/package gates are superseded by 8.1.67.
    codes.append(("test_8166_snow_surface_repaint_contract.py", run("test_8166_snow_surface_repaint_contract.py")))
    codes.append(("snow_surface_repaint_8166_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_surface_repaint_8166_test.lua")], cwd=HERE.parent)))
    codes.append(("snow_exact_tree_hull_8166_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_exact_tree_hull_8166_test.lua")], cwd=HERE.parent)))

    # 8.1.65 persistent cross-map tornado behavior remains mandatory. Historical
    # exact-version delta/freeze/package gates are superseded by 8.1.66.
    codes.append(("test_8165_tornado_map_roam_contract.py", run("test_8165_tornado_map_roam_contract.py")))
    codes.append(("tornado_remote_map_roam_8165_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "tornado_remote_map_roam_8165_test.lua")], cwd=HERE.parent)))
    codes.append(("tornado_remote_render_cull_8165_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "tornado_remote_render_cull_8165_test.lua")], cwd=HERE.parent)))

    # 8.1.64 SnowPack behavior remains mandatory. Historical exact-version
    # delta/freeze/package gates are superseded by 8.1.65.
    codes.append(("test_8164_snowpack_restore_contract.py", run("test_8164_snowpack_restore_contract.py")))
    codes.append(("snowpack_live_restore_8164_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snowpack_live_restore_8164_test.lua"), str(HERE.parent)], cwd=HERE.parent)))

    # 8.1.63 tornado pickup ownership / committed seeker behavior remains mandatory.
    # Its exact delta/freeze/package gates are superseded by 8.1.65; retain the
    # behavioral contract and executable regression.
    codes.append(("test_8163_tornado_pickup_contract.py", run("test_8163_tornado_pickup_contract.py")))
    codes.append(("tornado_pickup_semantics_8163_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "tornado_pickup_semantics_8163_test.lua"), str(HERE.parent)], cwd=HERE.parent)))

    # 8.1.62 walk-in contact behavior remains inherited. Historical exact-version
    # delta/freeze/package gates are superseded by 8.1.63.
    codes.append(("test_8162_tornado_contact_contract.py", run("test_8162_tornado_contact_contract.py")))
    codes.append(("tornado_walk_contact_8162_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "tornado_walk_contact_8162_test.lua")], cwd=HERE.parent)))

    # 8.1.61 real tornado map-transfer behavior remains inherited. Historical
    # exact-version delta/freeze/package gates are superseded by 8.1.63.
    codes.append(("test_8161_tornado_transfer_contract.py", run("test_8161_tornado_transfer_contract.py")))
    codes.append(("tornado_real_transfer_8161_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "tornado_real_transfer_8161_test.lua")], cwd=HERE.parent)))
    # 8.1.60 NPC-lightning / visible-smoke behavior remains mandatory. Historical
    # exact-version delta/freeze/package gates are superseded by 8.1.62.
    codes.append(("test_8160_npc_lightning_contract.py", run("test_8160_npc_lightning_contract.py")))
    codes.append(("npc_lightning_2d_8160_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "npc_lightning_2d_8160_test.lua")], cwd=HERE.parent)))
    # 8.1.59 snow point-plume behavior remains mandatory. Historical exact-version
    # package/freeze gates are superseded, but the visual-ownership behavior stays.
    codes.append(("test_8159_snow_plume_contract.py", run("test_8159_snow_plume_contract.py")))
    codes.append(("snow_point_plume_8159_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_point_plume_8159_test.lua")], cwd=HERE.parent)))
    # 8.1.58 tornado relocation / waterspout behavior remains mandatory. Historical
    # exact-version package/freeze gates are not chained for superseded releases.
    codes.append(("test_8158_tornado_contract.py", run("test_8158_tornado_contract.py")))
    for name in ["tornado_2d_relocation_8158_test.lua","funnel_relocation_choreography_8158_test.lua","funnel_blackout_framebuffer_8158_test.lua","tornado_relocation_8158_test.lua","tornado_waterspout_8158_test.lua"]:
        codes.append((name, subprocess.call(["texlua", str(HERE.parent / "tests" / name)], cwd=HERE.parent)))
    # 8.1.56 battle precipitation continuity remains mandatory. Historical
    # exact-version freeze/package gates are not chained for superseded releases;
    # their still-valid behavioral contracts remain below.
    codes.append(("test_8156_battle_precip_continuity.py", run("test_8156_battle_precip_continuity.py")))
    codes.append(("battle_precip_continuity_8156_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "battle_precip_continuity_8156_test.lua")], cwd=HERE.parent)))
    # 8.1.55 smooth fixed-world snow motion remains mandatory.
    codes.append(("test_8155_performance_contract.py", run("test_8155_performance_contract.py")))
    codes.append(("snow_motion_8155_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_motion_8155_test.lua")], cwd=HERE.parent)))
    # 8.1.54 full-visual precipitation virtualization / collision-suspension
    # behavior remains mandatory beneath the snow-motion-only release.
    codes.append(("test_8154_performance_contract.py", run("test_8154_performance_contract.py")))
    codes.append(("near_precip_virtualization_8154_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "near_precip_virtualization_8154_test.lua")], cwd=HERE.parent)))
    codes.append(("max_precip_virtualization_8154_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "max_precip_virtualization_8154_test.lua")], cwd=HERE.parent)))
    # 8.1.53 cloud/sun behavior and low-cost lighting contract remain mandatory.
    codes.append(("test_8153_performance_contract.py", run("test_8153_performance_contract.py")))
    codes.append(("test_8153_cloud_sun_localization.py", run("test_8153_cloud_sun_localization.py")))
    # 8.1.52 storm-front/audio/persistence behavior remains mandatory.
    codes.append(("test_8152_performance_contract.py", run("test_8152_performance_contract.py")))
    codes.append(("test_8152_front_realism.py", run("test_8152_front_realism.py")))
    codes.append(("front_entity_realism_8152_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "front_entity_realism_8152_test.lua")], cwd=HERE.parent)))
    codes.append(("front_audio_motion_cloud_8152_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "front_audio_motion_cloud_8152_test.lua")], cwd=HERE.parent)))
    codes.append(("weather_authority_8152_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "weather_authority_8152_test.lua")], cwd=HERE.parent)))
    # 8.1.51 zero-upload front precipitation and max-settings contracts remain mandatory.
    codes.append(("distant_front_instancing_8151_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "distant_front_instancing_8151_test.lua")], cwd=HERE.parent)))
    codes.append(("max_settings_simultaneous_8151_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "max_settings_simultaneous_8151_test.lua")], cwd=HERE.parent)))
    codes.append(("front_precip_continuity_8150_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "front_precip_continuity_8150_test.lua")], cwd=HERE.parent)))
    # 8.1.49 professional player-settings behavior remains mandatory.
    codes.append(("run_8149_player_settings_audit.py", run("run_8149_player_settings_audit.py")))
    # 8.1.48 compile repair behavior remains mandatory beneath the settings-only release.
    codes.append(("test_8148_compile_repair.py", run("test_8148_compile_repair.py")))
    # 8.1.47 pruning behavior remains the inherited contract under the compile-only repair.
    codes.append(("test_8147_flat_voxel_prune_contract.py", run("test_8147_flat_voxel_prune_contract.py")))
    codes.append(("flat_voxel_prune_8147_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "flat_voxel_prune_8147_test.lua")], cwd=HERE.parent)))
    # 8.1.46 visual/settings behavior remains mandatory.
    codes.append(("voxel_nexus_water_continuity_8146_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "voxel_nexus_water_continuity_8146_test.lua")], cwd=HERE.parent)))
    codes.append(("quality_presets_8146_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "quality_presets_8146_test.lua")], cwd=HERE.parent)))
    codes.append(("constellation_building_direction_8146_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "constellation_building_direction_8146_test.lua")], cwd=HERE.parent)))
    # 8.1.45 exclusive Nexus tide ownership remains mandatory under the 8.1.46
    # matched-material far-water LOD.
    codes.append(("voxel_nexus_water_8145_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "voxel_nexus_water_8145_test.lua")], cwd=HERE.parent)))
    # 8.1.44 public Battle Art ownership remains mandatory.
    codes.append(("test_8144_public_battle_art_contract.py", run("test_8144_public_battle_art_contract.py")))
    codes.append(("battle_art_public_water_8144_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "battle_art_public_water_8144_test.lua")], cwd=HERE.parent)))
    # 8.1.43 constellation peak-brightness behavior remains mandatory.
    codes.append(("test_8143_constellation_contract.py", run("test_8143_constellation_contract.py")))
    codes.append(("constellation_peak_brightness_8143_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "constellation_peak_brightness_8143_test.lua")], cwd=HERE.parent)))
    # 8.1.42 winter snowstorm + researched aurora behavior remains mandatory.
    codes.append(("test_8142_winter_aurora_contract.py", run("test_8142_winter_aurora_contract.py")))
    codes.append(("winter_snow_front_8142_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "winter_snow_front_8142_test.lua")], cwd=HERE.parent)))
    codes.append(("winter_aurora_8142_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "winter_aurora_8142_test.lua")], cwd=HERE.parent)))
    # 8.1.41's world-scale/leading-edge geometry remains mandatory, but its
    # player-following interception steering is intentionally superseded by
    # 8.1.52's independent entity contract above.
    codes.append(("storm_front_scale_render_8141_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "storm_front_scale_render_8141_test.lua")], cwd=HERE.parent)))
    # 8.1.40 exclusive VOID-water handoff remains mandatory; exact-version
    # freeze gates are superseded but its behavior gate still runs.
    codes.append(("test_8140_void_underlay.py", run("test_8140_void_underlay.py")))
    # 8.1.39 universal VOID-water behavior remains mandatory.
    codes.append(("void_water_all_voxels_8139_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "void_water_all_voxels_8139_test.lua")], cwd=HERE.parent)))
    # 8.1.38 living ponds / outer-ocean behavior remains mandatory; only its
    # exact-version runtime/package freeze gates are superseded by 8.1.39.
    codes.append(("pond_void_water_8138_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "pond_void_water_8138_test.lua")], cwd=HERE.parent)))
    codes.append(("storm_cloudbank_integration_8137_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "storm_cloudbank_integration_8137_test.lua")], cwd=HERE.parent)))
    codes.append(("storm_handoff_volume_8136_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "storm_handoff_volume_8136_test.lua")], cwd=HERE.parent)))
    codes.append(("world_ecosystem_8136_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "world_ecosystem_8136_test.lua")], cwd=HERE.parent)))
    codes.append(("building_light_continuity_8136_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "building_light_continuity_8136_test.lua")], cwd=HERE.parent)))
    codes.append(("complete_water_ownership_8136_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "complete_water_ownership_8136_test.lua")], cwd=HERE.parent)))
    codes.append(("water_player_safety_8136_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "water_player_safety_8136_test.lua")], cwd=HERE.parent)))
    codes.append(("foam_persistence_8135_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "foam_persistence_8135_test.lua")], cwd=HERE.parent)))
    codes.append(("void_water_8134_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "void_water_8134_test.lua")], cwd=HERE.parent)))
    codes.append(("professional_water_8133_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "professional_water_8133_test.lua")], cwd=HERE.parent)))
    codes.append(("water_hotpath_8132_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "water_hotpath_8132_test.lua")], cwd=HERE.parent)))
    codes.append(("wave_realism_8131_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "wave_realism_8131_test.lua")], cwd=HERE.parent)))
    codes.append(("water_style_8131_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "water_style_8131_test.lua")], cwd=HERE.parent)))
    codes.append(("ice_realism_8130_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "ice_realism_8130_test.lua")], cwd=HERE.parent)))
    codes.append(("test_8129_connected_water.py", run("test_8129_connected_water.py")))
    codes.append(("test_8128_world_scale_realism.py", run("test_8128_world_scale_realism.py")))
    codes.append(("snow_accumulation_footprint_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_accumulation_footprint_test.lua")], cwd=HERE.parent)))
    codes.append(("snow_radial_surface_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_radial_surface_test.lua")], cwd=HERE.parent)))
    codes.append(("snow_3d_bank_water_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_3d_bank_water_test.lua")], cwd=HERE.parent)))
    # 8.1.27 real-host repairs and 8.1.26 celestial player experience remain mandatory.
    codes.append(("test_8127_live_host_repairs.py", run("test_8127_live_host_repairs.py")))
    codes.append(("test_8126_player_experience.py", run("test_8126_player_experience.py")))
    codes.append(("8126_celestial_fallback_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "8126_celestial_fallback_test.lua")], cwd=HERE.parent)))
    codes.append(("8126_sunrise_sky_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "8126_sunrise_sky_test.lua")], cwd=HERE.parent)))
    # 8.1.25 constellation presentation repair remains mandatory.
    codes.append(("test_8125_constellation_polish.py", run("test_8125_constellation_polish.py")))
    # 8.1.24 zero-quality-loss performance architecture remains mandatory.
    codes.append(("test_8124_zero_quality_perf.py", run("test_8124_zero_quality_perf.py")))
    codes.append(("8124_night_geometry_equivalence_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "8124_night_geometry_equivalence_test.lua")], cwd=HERE.parent)))
    # 8.1.23 player fallback behavior remains mandatory.
    codes.append(("test_8123_fallback_controls.py", run("test_8123_fallback_controls.py")))
    codes.append(("8123_spatial_fallback_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "8123_spatial_fallback_test.lua")], cwd=HERE.parent)))
    # 8.1.22: finite cross-map storm-cell engine on top of 8.1.21.
    codes.append(("test_8122_world_weather_contract.py", run("test_8122_world_weather_contract.py")))
    codes.append(("weather_world_space_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "weather_world_space_test.lua")], cwd=HERE.parent)))
    codes.append(("storm_cell_lifecycle_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "storm_cell_lifecycle_test.lua")], cwd=HERE.parent)))
    codes.append(("storm_cross_map_seam_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "storm_cross_map_seam_test.lua")], cwd=HERE.parent)))
    codes.append(("test_8121_player_controls.py", run("test_8121_player_controls.py")))
    codes.append(("test_8120_weather_duration.py", run("test_8120_weather_duration.py")))
    codes.append(("test_8119_shadow_engine.py", run("test_8119_shadow_engine.py")))
    codes.append(("weather_shadow_engine_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "weather_shadow_engine_test.lua")], cwd=HERE.parent)))
    codes.append(("shadow_projection_monotonic_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "shadow_projection_monotonic_test.lua")], cwd=HERE.parent)))
    codes.append(("test_8118_manifest_freeze.py", run("test_8118_manifest_freeze.py")))
    codes.append(("test_8118_semantic_snapshot.py", run("test_8118_semantic_snapshot.py")))
    # Historical 8.1.17 config/QUALITY exact snapshot is intentionally not
    # chained after the 8.1.46 whole-mod quality expansion. Current quality
    # behavior is guarded by quality_presets_8146_test.lua and settings gates.
    codes.append(("8118_weather_catalog_exhaustive_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "8118_weather_catalog_exhaustive_test.lua")], cwd=HERE.parent)))
    codes.append(("8118_celestial_stress_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "8118_celestial_stress_test.lua")], cwd=HERE.parent)))
    codes.append(("8118_wind_stress_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "8118_wind_stress_test.lua")], cwd=HERE.parent)))
    codes.append(("8118_building_light_stress_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "8118_building_light_stress_test.lua")], cwd=HERE.parent)))
    codes.append(("8118_night_scheduler_stress_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "8118_night_scheduler_stress_test.lua")], cwd=HERE.parent)))
    codes.append(("8118_weather_off_crossmodule_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "8118_weather_off_crossmodule_test.lua")], cwd=HERE.parent)))
    codes.append(("test_8122_package_surface.py", run("test_8122_package_surface.py")))
    codes.append(("revision_gate.py", run("revision_gate.py")))
    codes.append(("test_811_truth_contract.py", run("test_811_truth_contract.py")))
    codes.append(("test_812_safety_contract.py", run("test_812_safety_contract.py")))
    codes.append(("test_813_safecall.py", run("test_813_safecall.py")))
    codes.append(("test_8110_contract.py", run("test_8110_contract.py")))
    codes.append(("test_8111_player_runtime_contract.py", run("test_8111_player_runtime_contract.py")))
    codes.append(("test_8113_visual_runtime_contract.py", run("test_8113_visual_runtime_contract.py")))
    codes.append(("test_8115_celestial_optics_contract.py", run("test_8115_celestial_optics_contract.py")))
    codes.append(("test_8116_celestial_quality_contract.py", run("test_8116_celestial_quality_contract.py")))
    codes.append(("moonrise_star_visibility_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "moonrise_star_visibility_test.lua")], cwd=HERE.parent)))
    codes.append(("test_engine_architecture.py", run("test_engine_architecture.py")))
    codes.append(("test_environment_engine_2.py", run("test_environment_engine_2.py")))
    codes.append(("test_environment_engine_3.py", run("test_environment_engine_3.py")))
    codes.append(("environment_engine_3_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "environment_engine_3_test.lua")], cwd=HERE.parent)))
    codes.append(("mesoscale_weather_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "mesoscale_weather_test.lua")], cwd=HERE.parent)))
    codes.append(("test_tsnow_audio.py", run("test_tsnow_audio.py")))
    codes.append(("test_weather_thunder_authority.py", run("test_weather_thunder_authority.py")))
    codes.append(("test_wind_engine.py", run("test_wind_engine.py")))
    codes.append(("test_settings_runtime.py", run("test_settings_runtime.py")))
    codes.append(("settings_advanced_pipeline_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "settings_advanced_pipeline_test.lua")], cwd=HERE.parent)))
    codes.append(("player_runtime_regression_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "player_runtime_regression_test.lua")], cwd=HERE.parent)))
    codes.append(("settings_menu_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "settings_menu_test.lua")], cwd=HERE.parent)))
    codes.append(("feature_audit.py", run("feature_audit.py")))
    codes.append(("edit_guard.py", run("edit_guard.py")))
    codes.append(("test_shader_attrs.py", run("test_shader_attrs.py")))
    codes.append(("test_scope_hygiene.py", run("test_scope_hygiene.py")))
    codes.append(("test_performance_invariants.py", run("test_performance_invariants.py")))
    codes.append(("test_801_performance_and_regressions.py", run("test_801_performance_and_regressions.py")))
    codes.append(("test_802_performance_and_regressions.py", run("test_802_performance_and_regressions.py")))
    codes.append(("test_803_regressions.py", run("test_803_regressions.py")))
    codes.append(("test_805_celestial_rain_events.py", run("test_805_celestial_rain_events.py")))
    codes.append(("test_806_lunar_phases.py", run("test_806_lunar_phases.py")))
    codes.append(("test_807_synoptic_transitions.py", run("test_807_synoptic_transitions.py")))
    codes.append(("synoptic_transition_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "synoptic_transition_test.lua")], cwd=HERE.parent)))
    codes.append(("test_808_mesoscale_weather.py", run("test_808_mesoscale_weather.py")))
    codes.append(("lunar_phase_progression_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "lunar_phase_progression_test.lua")], cwd=HERE.parent)))
    codes.append(("procedural_far_snow_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "procedural_far_snow_test.lua")], cwd=HERE.parent)))
    codes.append(("procedural_precip_field_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "procedural_precip_field_test.lua")], cwd=HERE.parent)))
    codes.append(("snow_virtualization_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_virtualization_test.lua")], cwd=HERE.parent)))
    codes.append(("precip_virtualization_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "precip_virtualization_test.lua")], cwd=HERE.parent)))
    codes.append(("npc_lightning_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "npc_lightning_test.lua")], cwd=HERE.parent)))
    codes.append(("tornado_3d_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "tornado_3d_test.lua")], cwd=HERE.parent)))
    codes.append(("rain_cloudbank_visibility_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "rain_cloudbank_visibility_test.lua")], cwd=HERE.parent)))
    codes.append(("tornado_safe_destination_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "tornado_safe_destination_test.lua")], cwd=HERE.parent)))
    codes.append(("rainbow_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "rainbow_test.lua")], cwd=HERE.parent)))
    codes.append(("wind_player_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "wind_player_test.lua")], cwd=HERE.parent)))
    codes.append(("celestial_star_field_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "celestial_star_field_test.lua")], cwd=HERE.parent)))
    codes.append(("celestial_zenith_quality_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "celestial_zenith_quality_test.lua")], cwd=HERE.parent)))
    codes.append(("audio_realtime_authority_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "audio_realtime_authority_test.lua")], cwd=HERE.parent)))
    codes.append(("max_performance_contract_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "max_performance_contract_test.lua")], cwd=HERE.parent)))
    codes.append(("test_benchmark.py", run("test_benchmark.py")))
    codes.append(("test_lightning_rates.py", run("test_lightning_rates.py")))
    codes.append(("test_lightning_bursts.py", run("test_lightning_bursts.py")))
    codes.append(("test_luajit_limits.py", run("test_luajit_limits.py")))
    codes.append(("test_3d_pipeline_integrity.py", run("test_3d_pipeline_integrity.py")))
    codes.append(("test_voxel_host_compat.py", run("test_voxel_host_compat.py")))
    codes.append(("test_strict_3d_present.py", run("test_strict_3d_present.py")))
    codes.append(("test_camera_modes.py", run("test_camera_modes.py")))
    codes.append(("test_night_sky.py", run("test_night_sky.py")))
    codes.append(("test_celestial.py", run("test_celestial.py")))
    codes.append(("test_celestial_supersample.py", run("test_celestial_supersample.py")))
    codes.append(("test_sunset_halo.py", run("test_sunset_halo.py")))
    codes.append(("test_celestial_lod.py", run("test_celestial_lod.py")))
    codes.append(("test_fog_intensity.py", run("test_fog_intensity.py")))
    codes.append(("test_constellations.py", run("test_constellations.py")))
    codes.append(("constellations_expanded_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "constellations_expanded_test.lua")], cwd=HERE.parent)))
    codes.append(("test_818_settings_time_contract.py", run("test_818_settings_time_contract.py")))
    codes.append(("settings_description_complete_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "settings_description_complete_test.lua")], cwd=HERE.parent)))
    codes.append(("settings_live_chain_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "settings_live_chain_test.lua")], cwd=HERE.parent)))
    codes.append(("quality_immediate_3d_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "quality_immediate_3d_test.lua")], cwd=HERE.parent)))
    codes.append(("intensity_control_response_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "intensity_control_response_test.lua")], cwd=HERE.parent)))
    codes.append(("snow_intensity_pipeline_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "snow_intensity_pipeline_test.lua")], cwd=HERE.parent)))
    codes.append(("fog_ownership_matrix_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "fog_ownership_matrix_test.lua")], cwd=HERE.parent)))
    codes.append(("host_night_star_spawn_test.lua", subprocess.call(["texlua", str(HERE.parent / "tests" / "host_night_star_spawn_test.lua")], cwd=HERE.parent)))
    codes.append(("test_harden.py", run("test_harden.py")))
    codes.append(("test_world_precip.py", run("test_world_precip.py")))
    codes.append(("test_sand_pitch_invariance.py", run("test_sand_pitch_invariance.py")))
    codes.append(("test_love_sandbox.py", run("test_love_sandbox.py")))
    codes.append(("test_mod.py", run("test_mod.py", ["--lua"] if want_lua else None)))
    codes.append(("compat_aggressive.py", run("compat_aggressive.py")))
    if (HERE / "audit_full.py").exists():
        codes.append(("audit_full.py", run("audit_full.py", ["--strict"])))
    if (HERE / "audit_compat.py").exists():
        codes.append(("audit_compat.py", run("audit_compat.py")))
    # informational
    for s in ("ai_debug.py", "mod_map.py"):
        codes.append((s, run(s)))
    print("\n===== DONE =====")
    failed = [(n, c) for n, c in codes if c]
    if failed:
        print("FAILED:")
        for n, c in failed:
            print(f"  {n} exit {c}")
        return 1
    print("all ok — safe baseline for next revision")
    return 0

if __name__ == "__main__":
    sys.exit(main())
