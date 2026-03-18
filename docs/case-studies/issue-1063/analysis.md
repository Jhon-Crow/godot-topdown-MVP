# Case Study: Issue #1063 — Arena Mode (including post-implementation bug fixes)

## Issue Summary

**Title:** добавить режим арены (Add Arena Mode)
**Description:** Implement an arena mode featuring spawning of health packs, ammo, weapons, and enemies.
**Request:** Spawn health pickups, ammo pickups, weapon pickups, and enemies in an endless/wave-based survival arena.

---

## Codebase Analysis

### Existing Level Architecture

All existing levels follow a common pattern defined in GDScript:

- `extends Node2D` with a level-specific script (e.g., `building_level.gd`, `labyrinth_level.gd`)
- Scene file (`.tscn`) containing: Environment (walls, floor, cover), Entities (Player, Enemies), CanvasLayer (UI), NavigationRegion2D
- Level script responsibilities:
  - `_setup_navigation()` — bakes nav mesh for pathfinding
  - `_setup_enemy_tracking()` — finds enemies, connects `died` signals
  - `_setup_player_tracking()` — finds player, connects weapon signals, registers with GameManager
  - `_initialize_score_manager()` — starts ScoreManager tracking
  - `_setup_exit_zone()` — places exit after level clear
  - `_start_replay_recording()` — ReplayManager integration

### Enemy System

- `scripts/objects/enemy.gd` — full-featured enemy AI (IDLE, COMBAT, COVER, FLANKING, SUPPRESSED, etc.)
- `scenes/objects/Enemy.tscn` — enemy scene with sprites, collision, hitbox
- Export properties: `behavior_mode` (PATROL/GUARD), `weapon_type` (RIFLE/SHOTGUN/UZI/MACHETE), `min_health`, `max_health`
- Signals: `died`, `died_with_info(is_ricochet_kill, is_penetration_kill)`, `hit`, `state_changed`

### Player Health & Ammo System

- `scripts/characters/player.gd` — GDScript player (legacy, for non-C# scenes)
- `Scripts/Characters/Player.cs` — C# player (modern, used in most levels)
- Player health: `_current_health`, `max_health`, `health_changed` signal, `take_damage()` method
- C# Player has `CurrentAmmo`, `ReserveAmmo`, weapon nodes (MakarovPM, AssaultRifle, Shotgun, etc.)
- No existing pickup system — health and ammo pickups need to be implemented

### Level Selection System

`scripts/ui/levels_menu.gd` contains a `LEVELS` constant array with level metadata. New levels must be added here to appear in the menu.

### Autoloads (GameManager, ScoreManager, etc.)

- `GameManager` — tracks kills, shots, hits, player alive state
- `ScoreManager` — calculates final score with combo, accuracy, time bonus
- `DifficultyManager` — manages difficulty multipliers
- `UnlockManager`, `ProgressManager` — track unlocks/progress

---

## Arena Mode Design

### Core Concept

An **endless survival arena** where the player survives increasingly difficult waves of enemies. Between waves, pickups (health, ammo, weapons) spawn on the map. The goal is to survive as many waves as possible and achieve the highest kill count/score.

### Key Features

1. **Wave System** — Enemies spawn in waves. Each wave is harder than the last (more enemies, tougher types). Wave difficulty scales based on wave number.
2. **Pickup Spawning** — After each wave ends (or periodically), health packs, ammo packs, and weapon pickups spawn at predefined spawn points.
3. **Endless Play** — No "level cleared" state; play until the player dies. Final score shown on death.
4. **Score Tracking** — Use existing ScoreManager; adapt for arena-specific scoring (wave bonuses, survival time).

### Implementation Plan

#### 1. Arena Level Script (`scripts/levels/arena_level.gd`)

Key variables:
- `_wave_number: int` — current wave
- `_enemies_in_wave: int` — enemies remaining in current wave
- `_wave_in_progress: bool` — true during active wave
- `_spawned_pickups: Array` — active pickup nodes

Key functions:
- `_start_wave()` — spawn enemies for this wave, scale difficulty
- `_on_enemy_died()` — decrement enemy count, check wave end
- `_end_wave()` — trigger pickup spawn, wait before next wave
- `_spawn_pickups()` — create health/ammo/weapon pickups at spawn points
- `_spawn_enemy_at()` — instantiate Enemy at spawn point with wave-scaled config
- `_on_pickup_collected()` — restore player health or ammo

#### 2. Pickup System (inline in arena_level.gd)

Pickups are simple `Area2D` nodes created programmatically:
- **Health Pack** — restores 1-2 HP to player on touch (calls player's `_current_health` directly or via method)
- **Ammo Pack** — restores reserve ammo on touch (calls weapon's `ReinitializeMagazines` or adds ammo)
- **Weapon Pickup** — changes the player's weapon to a random one from `GameManager.WEAPON_SCENES`

All pickups auto-destroy on contact or after a time limit.

#### 3. Arena Scene (`scenes/levels/ArenaLevel.tscn`)

- Open square arena (~1920x1080 pixels), minimal cover
- Dedicated spawn zones for enemies (4 corners/sides)
- Pickup spawn points distributed around the arena
- NavigationRegion2D covering the full playable area

#### 4. Levels Menu Integration

Add arena entry to `LEVELS` array in `scripts/ui/levels_menu.gd`.

---

## Research: Existing Arena-Style Games / Libraries

### Similar Godot Arena Patterns
- **Wave spawn managers**: Common pattern in Godot tutorials (e.g., Godot's "Your First 2D Game" uses spawner timer)
- **Pickup systems**: Area2D with `body_entered` signal, `queue_free()` on collection
- **Godot Arena Template**: Uses Timer nodes for wave spawning, preloaded enemy scenes

### Key Design Decisions

1. **Inline pickup nodes** (no separate scene) — simpler, avoids extra file, fits codebase style of building things programmatically
2. **Wave-based progression** rather than pure endless — gives natural pause points for pickup spawning
3. **Scale existing enemy types** — use existing `Enemy.tscn` with varied export parameters rather than new enemy types
4. **No exit zone** — arena ends when player dies, not when enemies are cleared; shows score on death

---

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `scripts/levels/arena_level.gd` | Create | Arena mode level script |
| `scenes/levels/ArenaLevel.tscn` | Create | Arena level scene |
| `scripts/ui/levels_menu.gd` | Modify | Add arena to level list |
| `tests/unit/test_arena_level.gd` | Create | Unit tests for arena level logic |
| `docs/case-studies/issue-1063/analysis.md` | Create | This file |

---

## Post-Implementation Bug Fixes (2026-03-18)

After initial implementation was deployed, the owner reported three issues with game log:
`docs/case-studies/issue-1063/game_log_20260318_021646.txt`

### Bug 1 — Counters (HP, ammo, etc.) not updating

**Log evidence (02:16:57):**
```
[Player.Weapon] Removed default MakarovPM
[Player.Weapon] Equipped AKGL (ammo: 30/30)
...
[Player.Weapon] GameManager weapon selection: ak_gl (AKGL)
[Player.Weapon] Equipped AKGL (ammo: 30/30)   ← second equip replaces the node
```

**Root Cause:** `_setup_player_tracking()` connected weapon signals to the first weapon node,
but the C# `Player._ready()` called `ApplySelectedWeaponFromGameManager()` again on the same
frame, destroying the old weapon node and creating a new one. All signals connected to the
old node were lost.

**Fix:** Changed to `call_deferred("_connect_weapon_signals_deferred")` so signal wiring
happens after all `_ready()` calls finish and the final weapon node is in place.

### Bug 2 — Enemies spawn in IDLE state (stare at walls)

**Log evidence:** Enemies spawn with `behavior: PATROL` but no subsequent SEARCHING/PURSUING
transition appears in logs. Enemies stood still until a gunshot triggered them.

**Root Cause:** Dynamically-spawned enemies start in `AIState.IDLE`. The IDLE→SEARCHING
transition only triggers when the enemy detects the player visually or hears a sound. In an
open arena with the player potentially far away and silent, this could take a long time.

**Fix:** After adding enemy to scene, call
`enemy.call_deferred("_transition_to_searching", player_position)`. The deferred call
ensures `Enemy._ready()` runs first (initializing navigation, memory, etc.) before
transitioning state. Enemies now actively search for the player immediately on spawn.

### Bug 3 — All enemies cluster at same corner

**Log evidence (02:16:59):**
```
Spawned at (1816.412, 822.8873)
Spawned at (1769.763, 801.4407)
Spawned at (1772.515, 789.8121)
```
All 3 wave-1 enemies spawn within 60px of each other at the bottom-right corner.

**Root Cause:** `_pick_random_enemy_spawn()` selected the *single* farthest spawn point
from the player. With the player near center-left, the farthest point is always the
bottom-right corner. ±40px scatter around one point produced dense clustering.

**Fix:** Sort spawn points by distance from player (farthest first), then pick randomly
from the top half. This distributes enemies along all four walls while still keeping
them away from the player's starting position.

---

## Round 2 Bug Fixes (Owner Feedback, 2026-03-18)

Game logs provided: `game_log_20260318_025454.txt`, `game_log_20260318_030642.txt`, `game_log_20260318_031040.txt`

### Bug 4 — Counters not working for all weapons except PM (second report)

**Log evidence (03:10:48 session):**
```
[Player.Weapon] GameManager weapon selection: ak_gl (AKGL)
[Player.Weapon] Removed default MakarovPM
[Player.Weapon] Equipped AKGL (ammo: 30/30)          ← first AKGL
...
[Player.Weapon] GameManager weapon selection: ak_gl (AKGL)
[Player.Weapon] Equipped AKGL (ammo: 30/30)           ← second AKGL (duplicate!)
```

**Root Cause:** Despite the previous `call_deferred` fix, `_setup_player_tracking()` was
still calling `_player.ApplySelectedWeaponFromGameManager()` explicitly. This created a
**second** AKGL weapon node. Godot auto-renames it to "AKGL2". `_find_player_weapon` then
found "AKGL" (the first, inactive node), connected `AmmoChanged` to it, but the player's
`CurrentWeapon` was "AKGL2". All ammo changes fired through AKGL2's signal which had no
listener, so counters stayed frozen.

**Fix:** Removed the `_player.ApplySelectedWeaponFromGameManager()` call from
`_setup_player_tracking()` (the C# Player._Ready() already calls it). Updated
`_find_player_weapon` to first check `player.get("CurrentWeapon")` (always returns the
active weapon), falling back to name-based search only if needed.

### Bug 5 — HP counter not updating

**Root Cause:** `_update_health_label()` was polled only when `_update_enemy_count_label()`
or `_update_debug_ui()` fired. These are called on enemy death events, not on player heal
events, so the HP label stayed stale after collecting a health pack.

**Fix:** Connected to the C# `Damaged` and `Healed` signals on the player via
`_connect_health_signals_deferred()` (called with `call_deferred` so the HealthComponent
is fully initialized). Both handlers immediately update the HP label.

### Bug 6 — Items not being picked up

**Root Cause (primary):** `_on_enemy_died()` lacked a `if not _wave_in_progress: return`
guard. Enemies from previous wave sessions (whose `died` signals survived a quick-restart
scene reload) triggered repeated calls to `_end_wave()`, causing `_spawn_wave_pickups()` to
fire 7+ times. The resulting pickup nodes were valid but the game was in an unstable state.

**Log evidence (game_log_20260318_031040.txt):**
```
[ArenaLevel] Wave 1 complete   ← lines 1159, 1221, 1233, 1310, 1341, 1367, 1451
```
Wave 1 "completes" seven times because enemy death signals keep arriving from previous
scene instances that share the same node IDs (Godot reuses freed object IDs).

**Fix (primary):** Added `if not _wave_in_progress: return` at the start of
`_on_enemy_died()`. Only deaths occurring while a wave is active are processed.

**Fix (secondary):** Changed pickup `collision_layer` from 0 to 1 and set
`monitoring = true` / `monitorable = true` explicitly. Moved pickup parent from
`Environment` to root scene so global positions are unaffected by any parent transform.
Added logging in `_on_pickup_body_entered` so future debug sessions can confirm detection.

### New Feature 4 — Active item charge pickup

When the player has a charge-based active item (Homing Bullets, Teleport Bracers,
Invisibility Suit, Trajectory Glasses, Loudspeaker, Breaching Charges), a "+CHG" pickup
now spawns between waves (purple). Each pickup restores 1 charge via the appropriate
C#/GDScript property on the Player node.

### New Feature 5 — Grenade launcher ammo restored by ammo pickup

When the player uses AKGL and collects an ammo pickup, `AKGL.GrenadeAvailable` is
restored to `true`. This matches the intuitive expectation that "getting ammo" also
refills the launcher's single grenade round.

### New Feature 6 — Grenade pickups

1 grenade pickup (red "+GRN") now spawns between every wave. Collecting it calls
`player.AddGrenades(1)` (C# method), adding 1 F-1 frag grenade up to the player's max.

### New Feature 7 — Arena button in pause menu

Arena mode is now directly accessible from the pause menu (alongside "Training"), 
matching the owner's request to "вынеси арену в отдельный пункт меню (как в случае с Обучением)".
A dedicated "Arena" button was added to `PauseMenu.tscn` and wired in `pause_menu.gd`.

---

## Round 5 Bug Analysis (game_log_20260318_075653.txt)

### Bug 7 — Enemies infinitely resurrect

**Log evidence (game_log_20260318_075653.txt):**
```
[07:58:21] [INFO] [ArenaLevel] Spawned pickups for wave 1   ← wave should be over
[07:58:23] [ENEMY] [@CharacterBody2D@3387] Enemy died       ← same enemy dying again
[07:58:26] [ENEMY] [Enemy] Enemy died                       ← and again
[07:58:27] [ENEMY] [@CharacterBody2D@3387] Enemy died       ← ...
[08:00:41] [INFO] [ArenaLevel] Spawned pickups for wave 1   ← wave "ends" a second time
```

The same 3 enemies (identified by their node IDs `@CharacterBody2D@3387`,
`@CharacterBody2D@3414`, `Enemy`) keep dying every 2-6 seconds indefinitely.

**Root cause:** `enemy.gd` exports `destroy_on_death: bool = false`. When this is `false`,
the `_on_enemy_died()` handler calls `_reset()` after `respawn_delay` seconds (default 2.0s),
restoring full health and re-enabling collision. The arena spawner never set
`destroy_on_death = true`, so all arena enemies respawned forever.

**Fix:** Added `enemy.set("destroy_on_death", true)` in `_spawn_enemy()` before
`add_child(enemy)`. This mirrors the fix applied in PR #1062 (roguelike mode).

### New Feature 8 — Active item charge pickups always spawn

**Previous behaviour:** `_maybe_spawn_active_item_charge_pickup()` only spawned a "+CHG"
pickup if the player's active item was in a hardcoded list of 6 charge-based items.
Force Field (type 7) and other items were excluded, so many players never saw charge
pickups.

**New behaviour:** Any equipped active item (type != 0) triggers 1 charge pickup per wave.
Spawning 1 charge vs 4 health packs keeps them rarer, as requested
("должны спавниться реже чем аптечки").
