local V = ...
local P={state={totalMs=0,worst='none',worstMs=0,recommendation='none',pressure=0,serial=0,families={}}}
local FAMILY={cloud_field='clouds',volumetric_weather='clouds',volumetric_renderer='clouds',gpu_weather='particles',surface_state='surface',hydrology='surface',accumulation_geometry='surface',surface_visual_state='surface',surface_visuals='surface',dynamic_lighting='lighting',unified_lighting='lighting',light_probe_grid='lighting',environment_audio='audio',weather_audio='audio',weather_sim='simulation',world_climate='simulation',microclimate='simulation',ecosystem='simulation'}
function P.update(dt,graph)
  local passes=graph and graph.rawStats and graph:rawStats() or ((graph and graph.stats and graph:stats().passes) or {}); local total,worst,wms=0,'none',0; local fam=P.state.families; for k in pairs(fam) do fam[k]=nil end
  for id,p in pairs(passes or {}) do local denom=tonumber(p.samples) or tonumber(p.calls) or 0; local ms=(denom>0 and ((tonumber(p.total) or 0)/denom) or tonumber(p.avg) or 0)*1000; total=total+ms; if ms>wms then wms,worst=ms,id end; local f=FAMILY[id] or 'environment'; fam[f]=(fam[f] or 0)+ms end
  local top,topms='none',0; for f,ms in pairs(fam) do if ms>topms then top,topms=f,ms end end
  local s=P.state; s.totalMs=total; s.worst=worst; s.worstMs=wms; s.pressure=math.max(0,math.min(1,(total-4)/10)); s.recommendation=((s.pressure>.24 or topms>=5.0) and top~='none') and ('trim:'..top) or 'none'; s.serial=s.serial+1
end
function P.peek() return P.state end
function P.sample() local o={}; for k,v in pairs(P.state) do if k=='families' then local q={}; for a,b in pairs(v) do q[a]=b end; o[k]=q else o[k]=v end end; return o end
return P
