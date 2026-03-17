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
