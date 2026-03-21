# Case Study: Issue #1259 — BuildingLevel: Player Death & Ammo Counter Broken

**Date:** 2026-03-21
**Reporter:** Jhon-Crow
**Branch/PR:** `issue-1259-9a7159f5f5ed` / PR #1260
**Severity:** High — core gameplay loop (death, ammo UI) non-functional on one map

---

## 1. Problem Description

Two bugs specific to the **Building** map (`BuildingLevel`):

1. **Player cannot die** — the "YOU DIED" text never appears; the scene restarts without any death screen.
2. **Ammo counter is broken** — the ammo label does not update when the player switches weapons or when `_apply_building_ammo_config` reinitialises magazine count.

Both bugs were absent from all other levels (TestTier, CityLevel, DocksLevel, FactoryLevel, RevolverLevel).

---

## 2. Evidence from Game Log (`game_log_20260321_081722.txt`)

**Key log observations:**

| Time | Event | Significance |
|------|-------|--------------|
| 08:17:23 | `[SceneLoader] ERROR: Invalid resource: res://scenes/levels/BuildingLevel.tscn` | First attempt to load BuildingLevel failed entirely |
| 08:22:00 | BuildingLevel finally loads | No lines from `building_level.gd` (e.g. signal connection messages) |
| 08:22:26 | `[CinemaEffects] Player died` | Player death confirmed at engine level |
| 08:22:26 | `[PenultimateHit] Player died`, `[LastChance] Player died` | C# effects received `Died` signal |
| 08:22:28 | `[CinemaEffects] Scene changed to: BuildingLevel` | Scene restarted ~2s after death |
| *(never)* | No "YOU DIED" label, no `building_level.gd` death handler log | GDScript handler never fired |

**Pattern across all BuildingLevel deaths in the log:**
- CinemaEffects, PenultimateHit, LastChance all fire their `Died` handlers (C# components connected to `Died`)
- `building_level.gd`'s `_on_player_died()` never fires (no corresponding log output)
- Scene restarts via `GameManager.on_player_death()` called from C# effects — no "YOU DIED" screen

---

## 3. Root Cause Analysis

### Root Cause 1: Missing `LevelInitFallback` in `BuildingLevel.tscn`

All other levels include a `LevelInitFallback` C# node that:
- Acts as a safety net if GDScript tokenization fails (Godot 4.3 binary tokenization bug — [godotengine/godot#94150](https://github.com/godotengine/godot/issues/94150))
- Connects to the player `Died` signal in C# to show "YOU DIED" and restart
- Connects weapon `AmmoChanged` signal to update ammo UI

`BuildingLevel.tscn` was missing this node entirely. When `building_level.gd` failed to load (as seen at 08:17:23 in the log), there was no fallback — the death signal was never connected at the GDScript level, and there was no C# fallback either.

Evidence: `[SceneLoader] ERROR: Invalid resource: res://scenes/levels/BuildingLevel.tscn` (line 254 of log). Even when the scene loaded successfully later, the GDScript produced no log output indicating it was running.

### Root Cause 2: Ordering Bug in `_setup_player_tracking()` in `building_level.gd`

In the GDScript level script, `_ammo_label` was initialised **after** `_setup_selected_weapon()` was called:

```gdscript
# BUGGY ORDER (before fix):
func _setup_player_tracking() -> void:
    _player = get_node_or_null("Entities/Player")
    if _player == null:
        return
    _setup_realistic_visibility()
    _setup_selected_weapon()           # ← calls _apply_building_ammo_config()
    if GameManager:
        GameManager.set_player(_player)
    _ammo_label = get_node_or_null(...)  # ← too late! already called above
    if _player.has_signal("died"):
        _player.died.connect(_on_player_died)
```

`_apply_building_ammo_config()` calls `_update_ammo_label_magazine()` which has a null-guard:
```gdscript
func _update_ammo_label_magazine(current_mag: int, reserve: int) -> void:
    if _ammo_label == null:
        return   # ← silently returns, initial ammo display is lost
    _ammo_label.text = "AMMO: %d/%d" % [current_mag, reserve]
```

Because `_ammo_label` is `null` at the time `_apply_building_ammo_config` runs, the initial ammo display is silently skipped. The label stays at its scene-default `"AMMO: 30/30"` even after the weapon is swapped or magazine count is reinitialised.

---

## 4. Fix Applied

### Fix 1: Add `LevelInitFallback` to `BuildingLevel.tscn`

Added the node to `scenes/levels/BuildingLevel.tscn`, matching all other levels:

```gdscript
# Added to header:
[ext_resource type="Script" path="res://Scripts/Components/LevelInitFallback.cs" id="5_fallback"]

# Added as last node:
[node name="LevelInitFallback" type="Node" parent="."]
script = ExtResource("5_fallback")
```

Also updated `load_steps` from `28` to `29`.

### Fix 2: Move `_ammo_label` Initialisation Before `_setup_selected_weapon()`

```gdscript
# FIXED ORDER:
func _setup_player_tracking() -> void:
    _player = get_node_or_null("Entities/Player")
    if _player == null:
        return
    # Find the ammo label early so _apply_building_ammo_config can update it (Issue #1259)
    _ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")
    _setup_realistic_visibility()
    _setup_selected_weapon()           # now _ammo_label is valid when called
    ...
```

---

## 5. Tests Added

New unit tests added to `tests/unit/test_level_scripts.gd`:

**Player death tests:**
- `test_building_player_death_shows_death_message` — death triggers "YOU DIED"
- `test_building_player_death_sets_game_over` — `_game_over_shown` is set to prevent duplicate messages
- `test_building_player_death_does_not_show_game_over_message` — only `show_death_message` fires, not `show_game_over_message`
- `test_building_player_second_death_ignored` — second death is a no-op after first

**Ammo counter tests:**
- `test_building_ammo_label_initialized_before_weapon_setup` — label is ready before weapon setup (fixed order)
- `test_building_ammo_label_buggy_order_misses_initial_update` — proves old order caused label to be skipped
- `test_building_ammo_label_update_reflects_magazine_ammo` — label shows correct `AMMO: current/reserve` text
- `test_building_ammo_label_update_empty_magazine` — label shows `AMMO: 0/reserve` when empty
- `test_building_ammo_label_update_fails_when_not_initialized` — null guard works correctly

---

## 6. Timeline of Events (Reconstructed)

```
[Initial] BuildingLevel.tscn created/modified → LevelInitFallback never added (present in all other levels)
[Code]    _setup_player_tracking() written → _ammo_label initialised after _setup_selected_weapon (subtle ordering bug)
[Runtime] Godot 4.3 tokenization bug may prevent GDScript from running → no fallback exists for BuildingLevel
[User]    Player enters BuildingLevel → ammo label shows wrong value → no "YOU DIED" screen on death
[Report]  Issue #1259 filed: "player cannot die, ammo counter broken" on Building map
[Fix]     PR #1260: (1) added LevelInitFallback, (2) fixed ordering bug
```

---

## 7. Follow-Up Issues Found (game_log_20260321_085325.txt)

After the initial fix, the owner reported three additional issues from a new session log.

### Follow-Up Issue A: Architecture — `_process_retreat_multiple_hits` removed as hack

The previous iteration removed the `_process_retreat_multiple_hits` function from `enemy.gd` and inlined
similar code to get the file below the 5000-line CI limit. This violated code integrity (the function
is a proper state handler matching the `RetreatMode.MULTIPLE_HITS` enum entry).

**Root cause:** `enemy.gd` in main was 5008 lines; after merging new upstream commits it became 4992.
The proper fix was to merge upstream and restore the deleted function — giving 5000 lines exactly.

**Fix:** Merged upstream/main (which had a proper 4999-line `enemy.gd`), then restored:
- `_process_retreat_multiple_hits(delta, direction_to_cover)` function body
- `_process_assault_state` comment+separate assignments (un-inlined)

### Follow-Up Issue B: AK+GL has 30 more ammo than expected

**Evidence (log line 341):** `[Player.Weapon] Equipped AKGL (ammo: 30/30)` — then LevelInitFallback runs,
no ammo reinit logged, and the default 4 magazines (30+90) are used instead of 2 (30+30).

**Root cause:** `LevelInitFallback.ConnectWeaponSignals()` connects to weapon signals and shows initial
ammo, but never calls `ReinitializeMagazines(2, true)` for AKGL/M16. This is BuildingLevel-specific
config that the GDScript `_apply_building_ammo_config()` handles, but the C# fallback didn't replicate it.

**Fix:** Added `ApplyBuildingLevelAmmoConfig(weapon)` call inside `ConnectWeaponSignals()`.
Detects `levelRoot.Name == "BuildingLevel"` and calls `ReinitializeMagazines(baseMagazines, true)`
for AKGL and AssaultRifle weapons, respecting the DifficultyManager ammo multiplier (Issue #949/#1259).

### Follow-Up Issue C: Score screen shows only Restart, missing Next Level / Levels / Armory buttons

**Evidence (log lines 1389–1403):** After the player reached exit, `LevelInitFallback` fired
`Player reached exit — showing score!` and `ScoreManager` completed the level. Then ~3 seconds later
the scene reloaded as BuildingLevel again — no navigation buttons were ever shown.

**Root cause:** `LevelInitFallback.ShowScoreScreen()` created the animated score screen and called
`show_animated_score()`, but never connected to the `animation_completed` signal. All GDScript level
scripts (CityLevel, TestTier, RevolverLevel, etc.) connect to `animation_completed` and then add:
- `→ Next Level` button (if a next level exists in the campaign)
- `↻ Restart (Q)` button
- `☰ Level Select` button
- `★ Armory — Items Available!` button (conditional on UnlockManager)

The C# fallback skipped all of this, so only the built-in "Press Q to restart" hint was visible.

**Fix:** Added `OnScoreAnimationCompleted(Node container)` method connected to `animation_completed`.
Mirrors the full button set from `city_level.gd._add_score_screen_buttons()`:
- `GetNextLevelPath()` uses the same level ordering as all GDScript levels
- Armory button uses gold styling when items are available (Issue #897)
- Focus set to NextLevelButton or RestartButton as fallback

---

---

## Follow-Up Bugs (2026-03-21 session 3, `game_log_20260321_095221.txt`)

### Follow-Up Issue D: Combo counter not working in BuildingLevel

**Reporter comment:** "не работает счётчик комбо." (combo counter not working)
**Log:** `game_log_20260321_095221.txt`

**Evidence:** In LabyrinthLevel (GDScript path), kills correctly log:
```
[ScoreManager] Kill registered. Combo: 1 (points: 500)
[ScoreManager] Kill registered. Combo: 2 (points: 1500)
```
In BuildingLevel (C# fallback path), enemies die (e.g. `[ENEMY] [Enemy4] Enemy died`) but
**no `[ScoreManager] Kill registered` lines appear at all**. The combo counter displays nothing.

**Root cause:** Issue #1196 added a 3rd parameter to the enemy `died_with_info` signal:
```gdscript
# enemy.gd line 96
signal died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool, is_player_kill: bool)
```
`LevelInitFallback.cs` connected to this signal with a handler that accepted only **2 parameters**:
```csharp
// Old — signature mismatch, Godot silently drops the call
private void OnEnemyDiedWithInfo(bool isRicochetKill, bool isPenetrationKill)
```
In Godot 4, a signal connection where the callable parameter count mismatches the signal argument count
causes the call to fail silently. As a result `scoreManager.register_kill()` was never called for any
kill in BuildingLevel, so combo was always 0.

**Fix:** Updated `OnEnemyDiedWithInfo` to accept all 3 parameters:
```csharp
// Fixed — accepts all 3 params from died_with_info signal
private void OnEnemyDiedWithInfo(bool isRicochetKill, bool isPenetrationKill, bool isPlayerKill)
```
`isPlayerKill` is accepted but not forwarded to `scoreManager.register_kill()` (which only takes
`isRicochetKill` and `isPenetrationKill`), matching what GDScript `_on_enemy_died_with_info` does.

---

### Follow-Up Issue E: FPS drops in BuildingLevel

**Reporter comment:** "очень сильно проседает fps" (FPS drops severely)
**Log:** 112 FPS drop events detected across the session; 36 in the final BuildingLevel run alone,
ranging from 1–27 fps (threshold 30).

**Evidence analysis:**

| Factor | Observation |
|--------|-------------|
| Enemy count | 10 enemies in BuildingLevel vs 5 in LabyrinthLevel — 2× AI computation |
| Sound propagation | Every shot queries 10 sound listeners (vs 5), logged heavily |
| Blood decals | 965 decals accumulated in the final BuildingLevel session (no limit by design, per issue #293/#370) |
| Debug features ON | ExperimentalSettings: `nav_mesh_visible: true`, `sound_visualizer: true`, `fps_counter: true` |
| Sound visualizer | Calls `queue_redraw()` every process frame when enabled — significant draw overhead |
| NavMesh overlay | Redraws on every `NavigationRegion2D` scene-tree event |

**Scene-load FPS drops** (e.g. 1 fps at line 265) are expected: `[SceneLoader] Background load started`
confirms Godot is streaming the level in the background on the same thread.

**Root cause verdict:** The FPS drops are caused by a combination of:
1. 2× enemy count (10 vs 5) driving proportionally more AI, sound propagation, and blood decal events
2. User had `sound_visualizer` and `nav_mesh_visible` debug features enabled — both add per-frame draw calls
3. 965 accumulated blood decals rendering each frame (unlimited by project requirement)

**No regression was introduced by this PR.** The performance characteristics are inherent to BuildingLevel
(10 enemies) and the experimental debug overlays the user had enabled. To improve performance:
- Disable `sound_visualizer` and `nav_mesh_visible` in the Experimental menu during normal play
- The Performance menu's "Blood decals" toggle can also be disabled to eliminate the decal overhead

---

## 8. Related Issues

- [godotengine/godot#94150](https://github.com/godotengine/godot/issues/94150) — GDScript binary tokenization bug in Godot 4.3
- Issue #540 — realistic visibility component setup (same `_setup_player_tracking` function)
- Issue #636 — Makarov PM 2.5x ammo multiplier
- Issue #886 — GrenadeTimer GDScript/C# duplicate handling
- Issue #897 — Armory button on score screen (gold highlight when items available)
- Issue #949 — M16/AK+GL should have 2 magazines on Building level
- Issue #1067 — Auto-reload passive item and `ApplyAutoReloadAfterLevelAmmoConfig`
- Issue #1196 — `died_with_info` signal gained 3rd param `is_player_kill` (triggered combo bug in C# fallback)
- Issue #1050 — Armory button gold highlight should be removed after all unlocks are claimed (fix ported to C# fallback)
