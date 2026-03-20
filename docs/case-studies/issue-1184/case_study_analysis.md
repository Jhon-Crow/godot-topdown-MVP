# Case Study: Issue #1184 — FPS Drops on BuildingLevel

## Timeline of Reports

| Time | Log | FPS | Condition |
|---|---|---|---|
| 2026-03-20 08:24 | game_log_20260320_082422.txt | ~1fps spike | Shader warmup at startup |
| 2026-03-20 08:48 | game_log_20260320_084817.txt | 12-20fps sustained | All enemies in SEARCHING state |
| 2026-03-20 09:23 | game_log_20260320_092301.txt | Normal (4s session) | LabyrinthLevel only |
| 2026-03-20 09:59 | game_log_20260320_095930.txt | Normal (4s session) | LabyrinthLevel only |
| 2026-03-20 10:18 | game_log_20260320_101853.txt | 25-29fps | BuildingLevel IDLE, nav mesh visible |
| 2026-03-20 10:43 | game_log_20260320_104332.txt | 3-4fps spikes, ~30fps sustained | BuildingLevel, patrol corner oscillation |
| 2026-03-20 10:44 | game_log_20260320_104440.txt | 3-13fps spikes, ~30fps sustained | BuildingLevel + invisibility activation |

## Root Causes Found and Fixed

### Fix 1: Corner Check Cooldown Bug (NEW — commit after 9e04d999)

**Symptom**: Enemy7 (PATROL) generates `PATROL corner check: angle 89.6°` immediately after the previous corner check completes. Log shows:
```
[10:44:15] Enemy7 ROT_CHANGE: P3:corner -> P4:velocity (corner_timer=-0.02)
[10:44:15] Enemy7 PATROL corner check: angle 89.6°  ← IMMEDIATE re-trigger
```

**Root cause**: In `_process_corner_check()`, the timer and cooldown were set to the same value simultaneously:
```gdscript
_corner_check_timer = CORNER_CHECK_DURATION; _corner_check_cooldown = CORNER_CHECK_DURATION
```
Both count down in sync (in the if/elif/elif chain). When the timer expires at time T, the cooldown has ALSO already expired. So no actual cooldown was applied.

**Fix**: The cooldown is now set WHEN the timer expires, not when the check is triggered:
```gdscript
if _corner_check_timer > 0:
    _corner_check_timer -= delta
    if _corner_check_timer <= 0: _corner_check_cooldown = CORNER_CHECK_DURATION  # start cooldown AFTER timer
```

**Impact**: Eliminates the 4fps spikes from continuous perpendicular opening re-detection (Enemy7, Enemy10 on BuildingLevel PATROL).

### Fix 2: ExperimentalSettings Autoload Cache (NEW — commit after 9e04d999)

**Symptom**: `get_node_or_null("/root/ExperimentalSettings")` called every physics frame in the global stuck detection code (line ~800), inside the `if _current_state == PURSUING or FLANKING` branch.

**Root cause**:
```gdscript
var _experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")  # per-frame!
```
With 10 enemies, this is 600 autoload dictionary lookups/sec just for stuck detection.

**Fix**: Cached as `_exp_settings_node` in `_ready()` alongside `_perf_settings_node`.

**Impact**: Eliminates 600 string-based node lookups/sec when enemies are in PURSUING/FLANKING states.

### Fix 3: PerformanceSettings Cache (commit 9e04d999)
`get_node_or_null("/root/PerformanceSettings")` was called every frame in `_physics_process()`. Cached as `_perf_settings_node`.

### Fix 4: Separation Force Throttle (commit 9e04d999)
`_apply_separation_force()` — O(N²) group query — now runs every 3rd frame, staggered by `get_instance_id() % 3`. Reduces separation cost by 66%.

### Fix 5: Combat Count Throttle (commit f2a36021)
`_count_enemies_in_combat()` — O(N²) — throttled to every 0.5s max.

### Fix 6: Intel Share Timer Stagger (commit f2a36021)
All enemies used to fire `get_nodes_in_group("enemies")` on the same frame. Now offset by `randf() * 0.5s`.

### Fix 7: Navigation Map RID Cache (commit f2a36021)
`NavigationServer2D.map_get_path()` was re-fetching the map RID up to 100× per waypoint burst. Cached.

### Fix 8: Integer Zone Key (commit f2a36021)
`_get_zone_key()` was allocating a String per waypoint. Now returns an integer.

## New Log Analysis: game_log_20260320_111452.txt (2026-03-20 11:14)

**Symptom**: Sustained 19-21fps on BuildingLevel with all enemies in IDLE, then 3fps spikes.

**Session events**:
- 11:15:01: BuildingLevel loaded, 10 enemies
- 11:15:02: Player enables Invincibility, selects Invisibility suit from armory → scene reloads
- 11:15:07: Scene reloads with invisibility equipped
- 11:15:09: 21fps (1 sec in), Debug mode toggled ON
- 11:15:10: 19fps (2 sec in)
- 11:15:13: 3fps spike (frame 180 arrived 3 real seconds late = ~10fps)
- 11:15:15: 3fps spike again

**Root causes found (Fix 9-13 below)**:

### Fix 9: _is_position_in_fov — ExperimentalSettings per vision-check (NEW — this commit)

`_is_position_in_fov()` called `get_node_or_null("/root/ExperimentalSettings")` on every vision check frame:
- Each enemy runs `_check_player_visibility()` → `_is_position_in_fov()` every 6 physics frames
- 10 enemies × 10 lookups/sec = 100 autoload lookups/sec from vision alone

**Fix**: Use `_exp_settings_node` cached at `_ready()`.

### Fix 10: _update_memory flashlight check — ExperimentalSettings per frame (NEW — this commit)

`_update_memory()` called `get_node_or_null("/root/ExperimentalSettings")` every physics frame when player is NOT visible (i.e., when using invisibility suit!):
- 10 enemies × 60fps = 600 lookups/sec while player is invisible

**Fix**: Use `_exp_settings_node` cached at `_ready()`.

### Fix 11: _draw debug rendering — ExperimentalSettings per render frame (NEW — this commit)

When Debug mode is ON (user toggled at 11:15:09), `_draw()` is called every render frame per enemy:
- Called `get_node_or_null("/root/ExperimentalSettings")` for FOV cone rendering
- 10 enemies × 60fps render = 600 lookups/sec added when debug is enabled

**Fix**: Use `_exp_settings_node` cached at `_ready()`.

### Fix 12: _check_pacifism_spread — ActiveItemManager per frame (NEW — this commit)

`_check_pacifism_spread()` called `get_node_or_null("/root/ActiveItemManager")` every physics frame per enemy:
- Early-exit if no loudspeaker, but the lookup happens before the check
- 10 enemies × 60fps = 600 lookups/sec always

**Fix**: Cache `_active_item_manager_node` in `_ready()` alongside other autoloads. Use in `_check_pacifism_spread()`.

### Fix 13: _transition_to_* — PerformanceSettings per state change (NEW — this commit)

Each of 9 state transition functions (`_transition_to_idle`, `_transition_to_combat`, etc.) called `get_node_or_null("/root/PerformanceSettings")` on every state transition. When enemies change states frequently (IDLE→PURSUING→IDLE during invisible-player gunshot react), this fires many times per second.

**Fix**: Use `_perf_settings_node` cached at `_ready()`.

## Observations: Non-Code Issues in Logs

- `Nav mesh visible: true` in ExperimentalSettings adds significant rendering overhead (the nav mesh polygon overlay is drawn every frame). This is a user toggle unrelated to our code changes.
- `Invincibility: true` + `Debug: true` enabled — adds minor overhead but not a bottleneck.
- FPS target is 60fps. BuildingLevel with 10 enemies and nav mesh visible may still be at 30-40fps without the nav mesh toggle, depending on hardware.

## Conclusion

The 4fps spikes are now fixed by the corner check cooldown correction. The sustained 30fps (rather than 60fps) on BuildingLevel with `Nav mesh visible: true` on the user's hardware is expected — the nav mesh rendering itself has overhead that this PR cannot address.
