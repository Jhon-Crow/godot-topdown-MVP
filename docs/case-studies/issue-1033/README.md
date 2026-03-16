# Case Study: Issue #1033 — Add New Enemy: Machine Gunner

## Overview

**Issue:** [#1033](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1033)
**Title:** добавить нового врага - пулимётчика (Add a new enemy — a machine gunner)
**Status:** Implemented in PR #1060 (Stage 1)
**Branch:** `issue-1033-243cbb7b0407`

---

## Problem Statement

The game needs a new enemy type: a machine gunner (PKM-style heavy weapon operator) with unique gameplay characteristics that distinguish it from existing enemies (rifle, shotgun, UZI, machete). The enemy should feel like a stationary suppressing force that is powerful in one-directional defense but vulnerable when flanked.

The owner described the following requirements:
- Very slow movement
- 30% chance to ignore damage when hit from directly in front (30-degree arc)
- Fires into passages near which the player was last seen until the belt runs out
- Long reload time
- Ammo: 500 + 500 rounds (one spare belt)
- When ammo depleted: draws a PM (Makarov pistol) and retreats to distant cover
- Optional: can add an ammo-carrier companion if already implemented
- Add to the map from issue #1032
- Break the task into stages and implement the first stage

---

## Stage Breakdown

The full implementation was broken into the following stages:

### Stage 1 (this PR)
- Add `MACHINE_GUN` weapon type to `WeaponType` enum in `enemy.gd`
- Configure the machine gun in `WeaponConfigComponent` (7.62x39 caliber, 500-round belt, slow fire rate)
- Implement front-arc damage resistance (30% chance to ignore hits within ±15° of facing direction)
- Implement PM fallback behavior on ammo depletion (swap to RIFLE-equivalent PM, transition to RETREATING)
- Slow movement speed for machine gunner instances (configurable via export)
- Add machine gunner enemy instance to an existing level scene (BuildingLevel or CityLevel)

### Stage 2 (future)
- Belt-fire suppression toward passages where player was last seen (extend `SuppressiveFireComponent`)
- Ammo carrier companion integration (when companion system is extended)
- Dedicated machine gunner scene with visual distinction (PKM sprite, bipod animation)
- Add to the new map from issue #1032 (when that map is implemented)

---

## Root Cause / Design Analysis

The existing enemy system already has excellent infrastructure for this new type:

1. **`WeaponType` enum** — `enemy.gd` line 33: easy to extend with a new `MACHINE_GUN = 4` value.
2. **`WeaponConfigComponent`** — `weapon_config_component.gd`: static dictionary with all weapon configs. Adding key `4` is straightforward.
3. **`AmmoComponent` / inline ammo system** — The enemy uses an inline ammo system (not the separate `AmmoComponent`). `magazine_size: 500, total_magazines: 2` gives 500+500 setup.
4. **Reload time** — `reload_time` export variable already exists; setting it to 8–10 seconds gives the "long reload" feel.
5. **Front arc resistance** — `on_hit_with_bullet_info()` at line 4143 is the primary entry point for all damage. Adding a random roll check against `hit_direction` vs enemy facing direction is straightforward.
6. **Ammo-depleted fallback** — `_can_shoot()` at line 1146 already emits `ammo_depleted` signal and sets `_goap_world_state["ammo_depleted"]`. The PM fallback is implemented by switching `weapon_type` to `RIFLE` (or a new `PM` type) and calling `_transition_to_retreating()` — the existing RETREATING state handles moving to cover.
7. **Speed reduction** — `move_speed` and `combat_move_speed` are export variables at line 37–38; setting them lower for machine gunner instances in the scene gives the "very slow" feel.

---

## Affected Files

| File | Change |
|------|--------|
| `scripts/objects/enemy.gd` | Add `MACHINE_GUN` to `WeaponType` enum; add front-arc damage resistance in `on_hit_with_bullet_info()`; add PM fallback on ammo depletion in `_can_shoot()` |
| `scripts/components/weapon_config_component.gd` | Add weapon config for `MACHINE_GUN` (type 4): 500-round belt, 7.62x39 caliber, slow fire rate, long reload |
| `scenes/levels/BuildingLevel.tscn` | Add machine gunner enemy instance with slow speed and MACHINE_GUN weapon type |
| `tests/unit/test_machine_gunner.gd` | Unit tests for front-arc resistance and ammo fallback behavior |

---

## Solution

### Change 1: `weapon_config_component.gd` — MACHINE_GUN config

```gdscript
4: {  # MACHINE_GUN (PKM) - belt-fed heavy machine gun
    "shoot_cooldown": 0.12,     # Slightly slower than rifle (8.3 rps)
    "bullet_speed": 2800.0,     # High muzzle velocity
    "magazine_size": 500,       # Full belt
    "bullet_spawn_offset": 40.0,
    "weapon_loudness": 2200.0,
    "sprite_path": "res://assets/sprites/weapons/m16_topdown.png",  # Placeholder
    "bullet_scene_path": "res://scenes/projectiles/csharp/Bullet.tscn",
    "casing_scene_path": "res://scenes/effects/Casing.tscn",
    "caliber_path": "res://resources/calibers/caliber_762x39.tres",
    "is_shotgun": false,
    "pellet_count_min": 1,
    "pellet_count_max": 1,
    "spread_angle": 0.0,
    "spread_threshold": 5,
    "initial_spread": 0.3,
    "spread_increment": 0.4,
    "max_spread": 6.0,
    "spread_reset_time": 0.4
}
```

### Change 2: `enemy.gd` — Front-arc damage resistance

In `on_hit_with_bullet_info()`, before applying damage, check if this enemy is a machine gunner
and the hit came from within ±15° of the facing direction:

```gdscript
# Machine gunner front-arc damage resistance (Issue #1033)
if weapon_type == WeaponType.MACHINE_GUN:
    var facing_dir := Vector2.from_angle(_enemy_model.global_rotation if _enemy_model else rotation)
    var dot := facing_dir.dot(-hit_direction.normalized())
    var FRONT_ARC_COS: float = cos(deg_to_rad(15.0))  # cos(15°)
    if dot >= FRONT_ARC_COS and randf() < 0.30:
        _log_to_file("[#1033] Machine gunner front-arc damage ignored (30% resistance)")
        return  # Ignore this hit
```

### Change 3: `enemy.gd` — PM fallback on ammo depletion

In `_can_shoot()`, when `ammo_depleted` is emitted for a `MACHINE_GUN` enemy, switch to PM behavior:

```gdscript
# Machine gunner fallback to PM pistol when belt is empty (Issue #1033)
if weapon_type == WeaponType.MACHINE_GUN:
    _activate_machine_gunner_pm_fallback()
```

New method `_activate_machine_gunner_pm_fallback()`:
- Sets `weapon_type = WeaponType.RIFLE` (uses existing rifle ammo config as PM substitute)
- Calls `_configure_weapon_type()` to reload weapon parameters
- Calls `_transition_to_retreating()` to move to distant cover

---

## Impact Analysis

- **New enemy type:** Players will encounter a new, distinct threat that rewards flanking play and punishes direct frontal assaults.
- **No regression:** All existing weapon types (RIFLE, SHOTGUN, UZI, MACHETE) are unchanged. The new `MACHINE_GUN = 4` extends the enum without breaking existing values.
- **Balanced threat:** The front-arc resistance (30% chance, 30° arc) is bounded and random — it does not make the enemy invincible; flanking or suppression from outside the arc counters it cleanly.

---

## Related Issues

- **Issue #1032** — New map where machine gunner will be placed (future stage)
- **Issue #910** — Suppressive fire component (will be extended for belt-fire behavior in Stage 2)
- **Issue #579** — Machete component (reference for per-weapon-type component pattern)
- **Issue #934** — BFF companion system (future ammo-carrier companion integration)
