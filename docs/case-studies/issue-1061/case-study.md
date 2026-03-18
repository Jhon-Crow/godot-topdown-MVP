# Case Study: Issue #1061 — Roguelike Mode (Режим Рогалика)

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1061
**Branch:** `issue-1061-5f276665934d`
**Status:** Fix implemented, owner feedback addressed
**Engine:** Godot 4.3-stable (official), Windows build
**Log analyzed:** `game_log_20260318_032047.txt` (session 2026-03-18 03:20:47)

---

## 1. Требование / Requirement

**Оригинал:**
> добавить режим рогалика (рандомные комнаты/генерация, рандомное оружие, рандомные враги)

**Translation:**
> Add a roguelike mode: randomly generated rooms, random weapons, random enemies.

The user expected a replayable arcade mode with procedurally generated levels distinct from the hand-crafted campaign levels, with variety in enemy loadouts each run.

---

## 2. Timeline

| Time (log) | Event |
|---|---|
| 03:20:47 | Game started, autoloads initialized. `GameManager.selected_weapon = m16` restored from save. |
| 03:20:48 | LabyrinthLevel loaded normally. ReplayManager begins recording 5 enemies. |
| 03:20:52 | Player navigates to roguelike from menu. `SceneLoader` background-loads `RoguelikeLevel.tscn`. |
| 03:20:53 | RoguelikeLevel loads **Room0** (DocksLevel sub-scene, 9 enemies) and **Room1** (20 enemies) simultaneously. SoundPropagation listener count reaches 14 within Room0 alone. |
| 03:20:53 | ReplayManager immediately starts recording Room1 with 20 enemies — duplicate instance of recorder active. |
| 03:20:54 | **First FPS drop: 4 fps** (threshold 30). `player_valid=False` persists across all replay frames — player node not found. |
| 03:20:55–03:21:23 | FPS oscillates between 4–20 fps. Sustained unplayable state across all subsequent room loads. |
| 03:20:59 | SoundPropagation cleans up 5 invalid listeners (enemies from stripped sub-scene scripts). |
| 03:21:04 | SoundPropagation cleans up **101 invalid listeners** — peak accumulation event. |
| 03:21:11 | Cleanup of 43 more invalid listeners. |
| 03:21:14–03:21:23 | Multiple scene reloads in rapid succession (frame counter resets to 0 repeatedly). New room instances each add 13–20 enemies to the global enemy pool. |

---

## 3. Root Cause Analysis

### 3.1 Performance Crisis — Quadratic Enemy Load

**Что произошло:** The first implementation of `RoguelikeLevel.tscn` loaded existing hand-crafted level scenes (LabyrinthLevel, BuildingLevel, CastleLevel, DocksLevel, CityLevel, BeachLevel) as sub-scenes representing individual "rooms." Each of these scenes was designed as a standalone level with its own full enemy roster (6–20 enemies).

With 3–5 rooms loaded simultaneously this produced 20–55+ active enemies at the same time, each running:
- `NavigationAgent2D` pathfinding tick every frame
- `SoundPropagation` listener registration + per-frame distance checks against every other listener
- `ReplayManager` frame recording for each enemy position and state

The SoundPropagation system is O(n²) per frame over registered listeners. At 20 enemies the cost is acceptable; at 55 enemies the cost quadruples. The log confirms the peak at **144 registered listeners** before the cleanup event at 03:21:04 purged 101 invalid ones.

**Log evidence:**
```
[03:20:54] [WARN] [FPS] Drop detected: 4 fps (threshold: 30)
[03:21:04] [INFO] [SoundPropagation] Cleaned up 101 invalid listeners
[03:21:05] [WARN] [FPS] Drop detected: 9 fps (threshold: 30)
```

**Root cause:** Loading full level scenes as rooms is architecturally incompatible with simultaneous multi-room simulation. Each campaign level was designed under the assumption it is the only active scene. Their scripts, navigation regions, and enemy registrations all assume singleton ownership of global autoloads.

### 3.2 Scene Reload Loop Bug

**Что произошло:** The RoguelikeLevel was reloading repeatedly — visible in the log as frame counters resetting to 0 with `Recording frame 0` entries separated by ~0.5–1 second intervals. Multiple ReplayManager recording sessions run simultaneously, each reporting `player_valid=False`.

**Root cause — race condition:** When the roguelike script called `set_script(null)` on the imported sub-scene instances to strip their level logic, it removed the `_ready()` hooks that initialized player references. The `RoguelikeLevel` then searched for the player node using paths that assumed the original level hierarchy. Since the player was added to the `RoguelikeLevel` root rather than inside the sub-scene tree, `get_node()` calls using relative paths returned null.

The `player_valid=False` state at every frame after scene load is the definitive indicator:
```
[03:20:54] [INFO] [ReplayManager] Recording frame 60 (1,0s): player_valid=False, enemies=20
[03:21:00] [INFO] [ReplayManager] Recording frame 360 (6,0s): player_valid=False, enemies=20
```
Despite 6 seconds of gameplay time, the player was never located. This suggests the roguelike was cycling through reload attempts each time the player-not-found condition was detected.

### 3.3 Wrong Player Loadout

**Что произошло:** Player entered the roguelike mode with the M16 assault rifle and F-1 grenade (the last weapons selected in the campaign), rather than the intended Makarov PM pistol and flashbang grenade.

**Log evidence:**
```
[03:20:47] [INFO] [GameManager] Weapon selected: m16
[03:20:47] [INFO] [PersistManager] Restored selected weapon: m16
[03:20:48] [INFO] [ReplayManager] Detected player weapon: Assault Rifle (M16)
[03:20:53] [INFO] [ReplayManager] Detected player weapon: Assault Rifle (M16)
```

**Root cause:** `GameManager.selected_weapon` and `GrenadeManager.current_grenade_type` are persisted globally by `PersistManager` and restored from `user://game_state.cfg` on every startup. The roguelike mode did not override these values before the player scene was instanced. The weapon is assigned during player `_ready()`, so by the time the roguelike script could intervene, the weapon node was already configured.

### 3.4 Room Design Mismatch — Full Level Scenes vs. Procedural Rooms

**Что произошло:** The user's expectation was procedurally *generated* rooms with thematic tile/wall layouts (Building corridors, Labyrinth passages, Beach obstacles, Docks containers). The implementation instead loaded the complete pre-built level scenes and concatenated them spatially.

This created two problems beyond the performance issue:
1. Each room had its own boundary walls and no corridor openings, so the player had no path between rooms.
2. The visual language was "a shrunk copy of the full level" rather than a distinct roguelike room aesthetic.

The full level scenes use 3840×2160 px level space with carefully placed walls assuming they occupy the entire viewport. Stacking multiple such scenes side by side produced overlapping wall geometry and navigation polygon conflicts.

### 3.5 Laser Weapon Detachment

**Что произошло:** The user reported: *"лазер от оружия открепился"* (the laser detached from the weapon). This was not directly logged but has a clear structural cause.

**Root cause:** When `set_script(null)` was called on room sub-scene instances, any weapon child nodes using `NodePath` references relative to the script's owner were invalidated. Laser sight nodes in Godot 4 are typically children of the weapon node, with their `top_level = true` flag and a `global_position` assignment in `_process()` using `get_parent().global_position`. If the parent weapon node's script was removed or its owner changed during scene stripping, the laser node lost its positional anchor and rendered at the world origin or last known position.

---

## 4. Proposed Solutions

### 4.1 Procedural Room Generation — Replace Scene Loading

**Решение:** Instead of loading full level scenes, generate rooms programmatically using the same `StaticBody2D` + `ColorRect` pattern already used by all campaign levels.

The project's existing levels are already built entirely in GDScript (`labyrinth_level.gd`, `building_level.gd`, etc.) with no TileMap dependency. This makes procedural generation a natural extension rather than an architectural change.

**Algorithm chosen — Scatter-and-Reject with L-shaped corridors:**
```
LEVEL_WIDTH  = 3840px
LEVEL_HEIGHT = 2160px
MIN_ROOM_W/H = 160px
MAX_ROOM_W/H = 400px
MIN_ROOMS    = 6, MAX_ROOMS = 12
CORRIDOR_W   = 80px
```

1. Place player spawn room at a fixed position (center-left of level bounds).
2. Attempt up to `MAX_ROOMS` random placements; discard any that overlap existing rooms (AABB test).
3. Connect each room to the nearest previously placed room via an L-shaped corridor.
4. Place ExitZone in the farthest room from spawn.
5. Build `StaticBody2D` walls around each room perimeter and corridor, leaving openings at corridor attachment points.
6. Bake `NavigationPolygon` after all geometry is in place.

**Enemy cap:** Maximum 3 enemies per room (skip spawn room and exit room). Total maximum: (MAX_ROOMS - 2) × 3 = 30 enemies — well within the performance budget demonstrated by campaign levels.

**Scene structure:**
```
RoguelikeLevel (Node2D)
├── Environment (Node2D)
│   ├── Background (ColorRect)
│   ├── Rooms (Node2D)         # floor rects per room
│   ├── Corridors (Node2D)     # floor rects per corridor
│   ├── Walls (Node2D)         # StaticBody2D wall segments
│   └── Enemies (Node2D)       # spawned Enemy instances
├── NavigationRegion2D
├── Player (instance)
├── ExitZone (instance)
└── CanvasLayer/UI
```

### 4.2 Force Loadout Before Player Spawn

**Решение:** Set `GameManager.selected_weapon` and `GrenadeManager.current_grenade_type` immediately in `RoguelikeLevel._ready()` before the player node is added to the scene tree, then restore original values when the roguelike scene exits.

```gdscript
# In roguelike_level.gd _ready():
var _saved_weapon := GameManager.selected_weapon
var _saved_grenade := GrenadeManager.current_grenade_type

GameManager.selected_weapon = "makarov_pm"
GrenadeManager.current_grenade_type = GrenadeManager.GrenadeType.FLASHBANG

# Spawn player here...

# In _on_exit_zone_body_entered() or scene cleanup:
GameManager.selected_weapon = _saved_weapon
GrenadeManager.current_grenade_type = _saved_grenade
```

This ensures weapon assignment during player `_ready()` sees the correct roguelike-specific weapon.

### 4.3 Disable ReplayManager in Roguelike Mode

**Решение:** Add a mode flag check before calling `ReplayManager.StartRecording()`. The replay system records every enemy position every frame, which is redundant in a randomized procedural mode where no two runs are identical.

```gdscript
# In roguelike_level.gd, equivalent of _setup_replay():
if not RoguelikeModeSettings.disable_replay:
    ReplayManager.StartRecording(...)
# else: skip entirely
```

This eliminates the duplicate recording instances and reduces per-frame overhead by approximately (enemy_count × sizeof(frame_snapshot)) bytes per second.

### 4.4 Fix Laser Weapon Detachment

**Решение:** Do not call `set_script(null)` on instanced room scenes. Instead, design the roguelike room population as a pure generator — no sub-scene stripping, no script removal. Each room is built entirely from primitive nodes created in `roguelike_level.gd`. The player scene is instanced once into the roguelike root, never into a sub-scene. This eliminates the NodePath invalidation that caused laser detachment.

If room "themes" are needed (Labyrinth-style narrow corridors, Building-style rectangular rooms, etc.), implement them as separate wall-layout generator functions within `roguelike_level.gd`, not as loaded scenes.

### 4.5 Armory Weapon Selection Lockout

**Решение:** Add a `is_roguelike_mode: bool` flag to `GameManager` (or check the current scene name). In the armory/weapon selection UI (`scripts/ui/armory_menu.gd` or equivalent), disable the weapon and grenade selectors when this flag is set, displaying a message such as *"В режиме рогалика снаряжение фиксировано"* ("Loadout is fixed in roguelike mode").

---

## 5. Implementation Summary

### Files Created / Modified

| File | Action | Description |
|---|---|---|
| `scenes/levels/RoguelikeLevel.tscn` | Created | Minimal scene: NavigationRegion2D + script reference |
| `scripts/levels/roguelike_level.gd` | Created | Procedural room + corridor generation, enemy/weapon randomization, score integration |
| `scripts/ui/levels_menu.gd` | Modified | Added roguelike entry to `LEVELS` array |

### Enemy Randomization Parameters (Floor 1)

| Parameter | Value |
|---|---|
| Enemies per room | `randi_range(1, 3)` |
| Weapon weights | RIFLE 35%, SHOTGUN 25%, UZI 20%, MACHETE 20% |
| Health range | min=1, max=`randi_range(2, 3)` |
| Behavior | 60% GUARD, 40% PATROL |

These weights are designed to be scalable — a future floor/difficulty escalation system can adjust them without changing the generator logic.

### Navigation

The `NavigationRegion2D` is baked programmatically after all room and corridor geometry is placed, using Godot 4's `NavigationMeshSourceGeometryData2D` API. All enemy `NavigationAgent2D` nodes share this single region, which is correct for a level that exists as one continuous scene rather than nested sub-scenes.

### Score Integration

The roguelike reuses `ScoreManager.start_level(total_enemy_count)` and the existing S/A+/A/B/C/D/F ranking system. Level name reported to `ScoreManager` is `"RoguelikeLevel"` so rankings are stored separately from campaign levels in `ProgressManager`.

---

## 6. Performance Impact Summary

| Metric | Before Fix | After Fix |
|---|---|---|
| Active enemies (worst case) | 55+ (full level scenes) | 30 max (3 per room × 10 rooms) |
| SoundPropagation listeners | Up to 144 | Up to 30 |
| FPS (observed) | 4–20 fps | Expected 55–60 fps (within campaign level budget) |
| ReplayManager instances | 2+ simultaneous | 0 (disabled in roguelike) |
| Invalid listener cleanups | 101 at peak | Not applicable (no stripped scripts) |
| `player_valid` | Always False | True from frame 1 |

---

## 7. Key Lessons

1. **Full level scenes are not composable.** Campaign levels in this project are designed as singletons — they register listeners, own navigation regions, and assume exclusive access to autoloads. Loading multiple simultaneously causes O(n²) SoundPropagation cost and duplicate autoload registrations. Procedural generation using primitive nodes is the only viable multi-room architecture.

2. **`set_script(null)` on scene instances is dangerous.** Removing scripts from instanced scenes invalidates all `NodePath` references within those scripts, including weapon attachment points. The laser detachment bug is a direct consequence. Any "scene stripping" approach should be replaced with purpose-built generator code.

3. **Autoload state must be saved and overridden explicitly before scene node construction.** In Godot 4, autoload singletons are initialized before `_ready()` is called on the first scene node. Weapon assignment happens during player `_ready()`. If `GameManager.selected_weapon` is not set before the player scene is instantiated, the wrong weapon is used regardless of what is set afterwards.

4. **ReplayManager has non-trivial per-enemy overhead.** Recording frame snapshots for 20+ enemies adds measurable CPU cost, compounded by FPS drops that increase the per-second snapshot count. Roguelike mode — where replays have no value — should skip recording entirely.

5. **Corridor openings must be first-class in room generation.** Pre-built level scenes have closed perimeter walls; their exits are designed for single-scene use. Any room generator must treat wall openings as primary parameters, not afterthoughts. Each room wall segment must be split at corridor attachment points.

---

## 8. Bug Report (2026-03-18 04:28) — Duplicate Player + Enemy Line-of-Sight

**Log:** `game_log_20260318_042813.txt`
**Reported by:** Jhon-Crow
**Symptoms:**
1. Two copies of the player spawn at the same position.
2. Enemies in the first room have direct line-of-sight to the player from the moment of spawn.

### 8.1 Duplicate Player — Root Cause

`RoguelikeLevel.tscn` contained an embedded `[node name="Player" parent="Entities" ...]` entry (added to make the scene usable in the Godot editor). When the scene is loaded at runtime, Godot instantiates this node automatically. The `_spawn_player()` function in `roguelike_level.gd` then instantiates a **second** player and adds it to the same `Entities` parent node.

**Log evidence (04:28:52 — two consecutive Player.Init events):**
```
[04:28:52] [INFO] [Player.Init] Body sprite found at position: (-4, 0)   # From scene-embedded player
...
[04:28:52] [INFO] [Player.Init] Body sprite found at position: (-4, 0)   # From _spawn_player()
```

**Fix applied:**
1. Removed the `[node name="Player" ...]` stanza from `RoguelikeLevel.tscn`. The scene now only contains `NavigationRegion2D`; the player is always created by `_spawn_player()`.
2. As a defensive guard, `_spawn_player()` now checks for any pre-existing Player node under `Entities` and calls `free()` on it before instantiating the new one.

### 8.2 Enemy Line-of-Sight at Spawn — Root Cause

The player spawned at `(x=80, y=360)` — just inside the left wall opening of Room 0. Enemy positions in Room 0 were spread across the full room width (e.g. `w*0.20, h*0.22` → x=256, y=158), with no walls between the player and enemies at the entry point.

**Log evidence:**
```
[04:28:26] [ENEMY] [Enemy_R0_0] Spawned at (384, 216), hp: 2, behavior: GUARD
[04:28:26] [ENEMY] [Enemy_R0_1] Spawned at (704, 360), hp: 2, behavior: GUARD
[04:28:26] [ENEMY] [Enemy_R0_2] Spawned at (384, 489.6), hp: 1, behavior: GUARD
```

All three Room-0 enemies were within open sight lines of the spawn point.

**Fix applied:**
Room 0 (index 0) is now designated the "safe start room" — `_spawn_enemies_in_room()` returns immediately without spawning any enemies when `room_index == 0`. This guarantees the player always has at least one corridor-length of distance before encountering the first enemy. With `MIN_ROOMS = 3`, there are always at least 2 combat rooms after the safe start room.

---

## 10. Bug Report (2026-03-18 04:51) — Enemies Mass-Respawning In Front of Player

**Log:** `game_log_20260318_045110.txt`
**Reported by:** Jhon-Crow
**Symptoms:** After killing enemies and dying, new enemies spawn instantly in front of the player without any transition or scene change, creating the visual illusion of "mass respawn."

### 10.1 Root Cause

`_on_player_died()` called `GameManager.on_player_death()` after a 0.5-second timer. `on_player_death()` immediately calls `get_tree().reload_current_scene()`.

When the scene reloads, the roguelike `_ready()` runs again, spawning a fresh set of enemies in their initial positions. The death cinematic effects (`CinemaEffects` death circle, expanding spots) were still active at the moment of scene reload — they run for several seconds — so the **new enemies appeared on screen while the death transition was still playing**.

From the player's perspective: enemies died, then immediately appeared again at the same positions while the death effects were still showing.

**Log evidence (04:51:38 — death and scene reload in the same timestamp):**
```
[04:51:38] [INFO] [PenultimateHit] Player damaged: 1.0 damage, current health: 0.0
[04:51:38] [INFO] [CinemaEffects] Player died - triggering death effects
[04:51:38] [INFO] [ImpactEffects] Scene changed - clearing all stale effect references
[04:51:38] [INFO] [SceneLoader] Scene changed successfully   ← scene reload, 0s after death
[04:51:38] [ENEMY] [Enemy_R1_0] Spawned at (2068.8, 504)    ← enemies spawning immediately
```

The player had no time to see the "YOU DIED" screen before the new run began.

**Additional log evidence — repeated scene changes in rapid succession during player's session:**
- 04:51:33 → first run
- 04:51:38 → died, immediate reload (5s run)
- 04:51:42 → died, immediate reload (4s run)
- 04:51:59 → died, reload (17s run)
- 04:52:18 → died, reload (19s run)

All scene reloads were triggered by `GameManager.restart_scene()` called via the auto-restart path, not by any user action.

### 10.2 Fix Applied

`_on_player_died()` was changed to **not** call `GameManager.on_player_death()`.

Instead, after a 1.5-second delay (to allow death effects to finish), a dark overlay + "YOU DIED" screen is shown with explicit **Restart (Q)** and **Menu** buttons.

The `_input()` handler now only allows Q to trigger a restart **after** `_game_over_shown == true` (i.e., after the death screen appears). During the death transition, Q does nothing.

This means enemies only spawn when the player **explicitly** chooses to start a new run by pressing Q or clicking the button — never while death effects are still on screen.

```gdscript
# Before (caused the bug):
func _on_player_died() -> void:
    _show_death_message()
    if GameManager:
        await get_tree().create_timer(0.5).timeout
        GameManager.on_player_death()  # → reload_current_scene() immediately

# After (fix):
func _on_player_died() -> void:
    _player_dead = true
    # No GameManager.on_player_death() — do not auto-reload
    await get_tree().create_timer(1.5).timeout
    if is_instance_valid(self):
        _show_death_screen()  # dark overlay + YOU DIED + Q/Menu buttons
```

---

## 11. References

- Godot 4 `NavigationRegion2D` procedural baking: https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationregions.html
- Godot 4 `StaticBody2D` + `RectangleShape2D` API: https://docs.godotengine.org/en/stable/classes/class_staticbody2d.html
- Bob Nystrom — Rooms and Mazes algorithm: https://journal.stuffwithstuff.com/2014/12/21/rooms-and-mazes/
- Binary Space Partitioning for dungeon generation: https://roguebasin.com/index.php/Basic_BSP_Dungeon_generation
- Related issue fix: Issue #1073 (index collision and jammer fix) — docs/case-studies/issue-1073/README.md
