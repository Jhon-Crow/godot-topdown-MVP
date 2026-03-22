# Issue #1242 — Shield Enemy (SWAT Shieldbearer)

## Issue Summary

Add a new enemy type: a SWAT-style shieldbearer with a revolver.

### Requirements
1. **Shield**: Enemy holds a shield in front. The shield blocks all bullets **except sniper rounds**.
   - Shield absorbs 20 damage before breaking temporarily.
   - When shield absorbs enough damage → enemy staggers back, shield drops, enemy is stunned + blinded for 1s.
   - Shield rises again automatically after stun ends.
2. **Revolver**: Enemy fires a revolver (no manual hammer cocking — just semi-auto).
   - After 5 shots → enemy goes to cover and reloads the cylinder (same as player's cylinder reload).
3. **Formation**: When nearby enemies detect the shielded enemy, they walk behind it using it as cover.
4. **Speed penalty**: Enemy moves at half speed while shield is raised.
5. **Spawner**: Add to the experimental enemy spawner only (not placed in levels yet).

## Codebase Analysis

### Existing Enemy Architecture
- `scripts/objects/enemy.gd` — main ~4900-line monolithic script; CharacterBody2D
- `WeaponType` enum: RIFLE(0), SHOTGUN(1), UZI(2), MACHETE(3), RPG(4), PM(5), MACHINE_GUN(6), SNIPER_RIFLE(7)
- All special behaviors are extracted into components following the ForceFieldComponent pattern
- Weapon configs in `scripts/components/weapon_config_component.gd`
- Status effects (stun, blind) via `FlashbangStatusComponent` — methods `apply_flashbang_effect(blindness_duration, stun_duration)`, `set_stunned()`, `set_blinded()`

### Existing Bullet Penetration System
- `scripts/projectiles/bullet.gd` — checks `caliber_data.can_penetrate_walls()` via CaliberData resource
- Sniper bullet (12.7x108mm ASVK) has `can_penetrate = true`, `penetration_power = 100.0`
- Revolver bullet (12.7x55mm STs-130) has `can_penetrate = true`, `penetration_power = 80.0`
- The shield needs to be an Area2D that intercepts bullet signals (similar to ForceFieldEffect)

### Existing Components Used as Models
- `EnemyForceFieldComponent` — blocks bullets, deactivates on charge depletion
- `EnemyArmoredSkinComponent` — absorbs hits, triggers at HP threshold
- `FlashbangStatusComponent` — manages stun/blind states with timers

### Formation Pattern
- No existing formation logic in the codebase
- Must use `get_tree().get_nodes_in_group("enemies")` to find nearby allies
- Allies should navigate to a position behind the shield enemy

### Revolver Config
- Player's Revolver (RSh-12, `Revolver.cs`): 5-chamber cylinder, 12.7x55mm caliber
- Enemy revolver: same 5 shots, but simple semi-auto (no manual hammer cocking)
- Reload: after 5 shots, enter IN_COVER state and reload (existing reload mechanism)
- Uses existing `caliber_12p7x55.tres` resource

## Solution Design

### 1. New WeaponType: REVOLVER (8)
Add to `WeaponConfigComponent.WEAPON_CONFIGS`:
- `shoot_cooldown`: 0.35s (semi-auto revolver pace)
- `bullet_speed`: 2000.0 (12.7mm but pistol velocity)
- `magazine_size`: 5 (cylinder)
- `bullet_scene_path`: Bullet12p7mm or Bullet.tscn
- `caliber_path`: `caliber_12p7x55.tres`
- `sprite_path`: `revolver_topdown.png`

### 2. New Component: `enemy_shield_component.gd`
Manages the SWAT shield:
- Area2D intercepts bullets before they reach the enemy's HitArea
- Sniper rounds (can_penetrate=true + high penetration_power >= 80.0) pass through
- Tracks absorbed damage (threshold = 20)
- On threshold exceeded: stagger (knockback), drop shield, apply stun+blind 1s
- After stun: automatically raise shield again
- While shield active: halve move_speed

### 3. Modifications to `enemy.gd`
- Add `has_swat_shield: bool = false` export
- Add `_shield_component: EnemyShieldComponent` variable
- Initialize in `_ready()` alongside other components
- In `_physics_process()`: pass speed override from shield component
- Override `on_hit_with_bullet_info()` to check if shield intercepts first

### 4. Formation Logic (in `enemy_shield_component.gd` or new component)
- Each frame, scan nearby enemies (radius ~300px) from groups("enemies")
- Notify them of shield position so they can use it as cover
- Allies listen for a shielded ally and navigate to positions behind it

### 5. New Scene: `scenes/objects/EnemySwatShield.tscn`
- Inherits same structure as Enemy.tscn
- Sets `has_swat_shield = true`, `weapon_type = REVOLVER`
- Has shield sprite overlay (use force_field_icon as placeholder)

### 6. Spawner Integration
- Add to `game_manager.gd` `types` array: `{"name": "SWAT Shieldbearer", "weapon_type": 8, "behavior": 1, "has_swat_shield": true}`
- Add to `experimental_menu.gd` setup list

## Bug Report: Shield enemy does not rotate toward damage (2026-03-22)

### User Feedback
> "теперь враг вообще не поворачивается в сторону урона (должен медленно)."
> Translation: "Now the enemy doesn't rotate toward damage at all (should rotate slowly)."

### Root Cause Analysis

The fix from Round 7 (commit `983989d8`) added guards to prevent instant snap-rotation on hit for shield enemies.
However, these guards completely **skipped** all rotation instead of replacing it with slow rotation.

**Three code paths affected:**

1. **Shield-blocked hits** (`on_hit_with_bullet_info`, lines 4232-4234): When the shield intercepts a hit, the function returns early. No rotation update occurs — the enemy doesn't even acknowledge the hit directionally.

2. **Non-blocked hits** (`on_hit_with_bullet_info`, line 4247): The guard `not (_shield_component and _shield_component.get_rotation_multiplier() < 1.0)` causes `_force_model_to_face_direction()` to be entirely skipped. But `_update_enemy_model_rotation()` (which runs every frame) doesn't have a "face attacker" priority — it faces the current target (P1/P2) which is already the player. So no observable rotation change occurs.

3. **Priority attacks** (lines 1337, 1381): Same guard pattern — shield enemy skips `_force_model_to_face_direction` entirely. The bullet still fires correctly (Node2D `rotation` is set), but the visual model never catches up.

**Key insight**: The `_update_enemy_model_rotation()` function uses a priority system (P0: grenade, P1: visible target, P2: combat state, P3: corner, P4: velocity, P5: idle scan). None of these priorities represent "face the attacker who just hit me." For normal enemies, `_force_model_to_face_direction` handles this instantly. For shield enemies, this was completely removed with no replacement.

### Fix: Hit Reaction Rotation System

Added a `_hit_reaction_timer` / `_hit_reaction_angle` mechanism (similar to existing `_corner_check_timer` / `_corner_check_angle` pattern):

1. **New variables**: `_hit_reaction_angle`, `_hit_reaction_timer`, `HIT_REACTION_DURATION` (0.8s)
2. **New priority P0.5**: Inserted between P0 (grenade throw) and P1 (visible target) in `_update_enemy_model_rotation()`
3. **New function**: `_set_hit_reaction_target(attacker_direction)` — sets the angle and starts the timer
4. **All three code paths** now call `_set_hit_reaction_target()` instead of skipping rotation entirely

The shield enemy will now slowly rotate toward the attacker at 0.15× speed (0.45 rad/s ≈ 26°/s) for 0.8 seconds after each hit. The rotation is smooth and matches the "heavy shield" feel. After the timer expires, P1/P2 priorities take over and the enemy resumes facing its target.

### Evidence from Game Log
File: `game_log_20260322_204747.txt`

- At `20:48:04`: Shield enemy spawned, enters IDLE
- At `20:48:05`: Hears gunshot, transitions to COMBAT. Target 180°, current -24.9°
- At `20:48:05-20:48:09`: Shield absorbs 20 hits (hp 20→0), no ROT_CHANGE logged between hits
- No "hit_reaction" rotation entries appear because the feature didn't exist yet

## References
- Issue #1034 (ForceField enemy) — bullet-blocking component pattern
- Issue #1123 (ArmoredSkin) — component extraction pattern
- Issue #432/#328 (stun/blind) — FlashbangStatusComponent
- Issue #583 (RPG→PM weapon switch) — complex weapon behavior pattern
- Issue #1125 (Sniper) — heavy weapon with bolt-cycle
