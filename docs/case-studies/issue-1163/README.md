# Case Study: Issue #1163 — Sniper Enemy Special Behavior & Enemy Breaking Bug

## Issue Summary

**Title:** update враг снайпер (update enemy sniper)

**Requirements:**
1. The sniper enemy should stay at maximum distance from the player and shoot from there.
2. When the player is not visible, the sniper should shoot approximately where the player might be — even through cover — since the sniper rifle (ASVK) penetrates cover.

**Additional report (follow-up comment by Jhon-Crow):**
> все враги сломались (такое уже бывало при добавлении новых врагов).
> ("all enemies broke — this has happened before when adding new enemies.")
>
> Attached: `game_log_20260318_095818.txt`

---

## Part 1 — Sniper AI Design (Original Issue)

### Context

The sniper enemy was introduced in Issue #1125, adding the `SNIPER_RIFLE` weapon type (ASVK anti-materiel rifle) to the enemy system. However, #1125 only added the weapon type without special AI behavior. Issue #1163 requests:
1. Standoff range maintenance (stay far, retreat if player closes in)
2. Blind-fire through cover at last-known / predicted player positions

### Implementation

The sniper AI follows the same **early-return guard pattern** used by Machine Gunner (#1033) and RPG enemy (#583):

- New file: `scripts/components/enemy_sniper_component.gd` (`class_name EnemySniperComponent`)
- In `_process_combat_state`: `weapon_type == WeaponType.SNIPER_RIFLE` check routes to `_sniper_component.process_combat()`
- In `_process_pursuing_state`: `_sniper_component.process_pursuing()` holds position and blind-fires

**Constants:**
- `PREFERRED_DISTANCE = 550.0 px` — preferred engagement range
- `MIN_DISTANCE = 350.0 px` — closer than this → actively retreat
- `BLIND_FIRE_COOLDOWN = 5.0 s` — delay between blind shots through cover

**Blind-fire physics:** `SniperBulletEnemy.tscn` has `MaxWallPenetrations = 2`, so bullets physically penetrate cover walls. The sniper fires at `_last_known_player_position` or the `PlayerPredictionComponent` best estimate.

---

## Part 2 — Enemy Breaking Bug (Follow-up Report)

### Symptom

The user reported (after testing the exported build) that all enemies were non-functional:

```
[LabyrinthLevel] Found Environment/Enemies node with 5 children
[LabyrinthLevel] Child 'Enemy1': script=true, has_died_signal=false
[LabyrinthLevel] Child 'Enemy2': script=true, has_died_signal=false
...
[LabyrinthLevel] Enemy tracking complete: 0 enemies registered
```

All 5 enemies (RIFLE and SHOTGUN types — no snipers) had `has_died_signal=false`, meaning `enemy.gd` failed to declare its signals at load time.

### Root Cause Analysis

#### What `has_signal("died") = false` means

In Godot 4, `has_signal()` returns `false` when a node's script failed to **compile** (parse error). Even though `get_script() != null` (the script resource is attached), if the script has a parse error it cannot register its class, signals, or methods.

#### The Variant Inference Error in Godot 4

Godot 4 GDScript treats certain type inference warnings as **errors** during headless export:

```
SCRIPT ERROR: Parse Error: The variable type is being inferred from a Variant value,
so it will be typed as Variant. (Warning treated as error.)
```

This error occurs when:
1. A variable uses `:=` inference
2. The right-hand side is a call to a method whose return type GDScript cannot determine
3. Specifically: calling a **custom enemy method** through a variable typed as `CharacterBody2D` or `Node2D` — since these base classes don't define the custom method, GDScript cannot know the return type

#### Pre-existing Failures (Before This PR)

Even before the sniper component was added, **two pre-existing components** caused `enemy.gd` to fail in headless export:

| File | Line | Issue |
|------|------|-------|
| `scripts/components/suppressive_fire_component.gd` | 51 | `var spawn_pos := _enemy._get_bullet_spawn_position(...)` — Variant inferred from custom method call |
| `scripts/components/enemy_flashlight_component.gd` | 271 | `var angle_to_player := abs(...)` — `abs()` return type inference |
| `scripts/components/enemy_flashlight_component.gd` | 340 | `var enemy_name := _enemy.name if _enemy else "Unknown"` — `StringName` vs `String` type mismatch |
| `scripts/autoload/black_metal_lightning_effects_manager.gd` | 374, 391, 465, 470, 475, 484 | `clamp()` and `floor()` return type inference |

**Evidence from CI logs (run `23232307648`, before sniper component was added):**
```
at: GDScript::reload (res://scripts/components/suppressive_fire_component.gd:51)
at: GDScript::reload (res://scripts/components/enemy_flashlight_component.gd:271)
at: GDScript::reload (res://scripts/components/enemy_flashlight_component.gd:340)
at: GDScript::reload (res://scripts/objects/enemy.gd:-1)
ERROR: Failed to load script "res://scripts/objects/enemy.gd" with error "Parse error".
```

#### How Our Sniper Component Made It Worse

Our `enemy_sniper_component.gd` added 3 additional Variant-inference parse errors:

| Line | Code | Problem |
|------|------|---------|
| 33 | `var distance_to_player := _enemy.global_position.distance_to(player.global_position)` | `player` typed as `Node` (not `Node2D`), so `player.global_position` returns `Variant` |
| 40 | `retreat_dir = _enemy._apply_wall_avoidance(retreat_dir)` | `_apply_wall_avoidance()` is a custom method, return type is `Variant` from `CharacterBody2D` perspective |
| 107 | `var spawn_pos := _enemy._get_bullet_spawn_position(to_target)` | Same pattern as `suppressive_fire_component.gd:51` |

**Evidence from CI logs (run `23232493856`, after our commit):**
```
at: GDScript::reload (res://scripts/components/enemy_sniper_component.gd:33)
at: GDScript::reload (res://scripts/components/enemy_sniper_component.gd:39)
at: GDScript::reload (res://scripts/components/enemy_sniper_component.gd:107)
ERROR: Failed to load script "res://scripts/components/enemy_sniper_component.gd" with error "Parse error".
ERROR: Failed to load script "res://scripts/objects/enemy.gd" with error "Parse error".
```

#### Cascade Failure Mechanism

```
enemy_sniper_component.gd (parse error)
    ↓ EnemySniperComponent class not registered in global_script_class_cache
    ↓ enemy.gd references `var _sniper_component: EnemySniperComponent` → unresolved type
    ↓ enemy.gd fails to compile
    ↓ signal "died" not declared → has_signal("died") = false
    ↓ 0 enemies registered → level never completes, enemies don't die
```

#### Why This Is a "Known Pattern"

The user noted "this has happened before when adding new enemies." Historical context:
- Each time a new component is added that calls custom enemy methods through a base-typed reference, it causes the same cascade failure in headless export.
- Previous PRs have triggered this same issue: `suppressive_fire_component.gd` (Issue #910) and `enemy_flashlight_component.gd` (Issue #824) both have the same bug pattern.
- The pattern propagates because developers copy the access pattern from existing (broken) components.

### Timeline of Events

```
2026-03-18 06:35 UTC  Commit bd9e3f8c: feat: sniper enemy stays at range and blind-fires
2026-03-18 06:42 UTC  Commit 8d1fc892: refactor: extract sniper AI into EnemySniperComponent
                       CI passes (static analysis doesn't detect runtime parse errors)
                       Build export "succeeds" despite parse errors (export still generates EXE)
2026-03-18 06:43 UTC  Export log shows:
                         ERROR: Failed to load script enemy_sniper_component.gd (Parse error)
                         ERROR: Failed to load script enemy.gd (Parse error)
2026-03-18 ~09:58 local  User downloads and tests build
                         LabyrinthLevel: 5 enemies, has_died_signal=false, 0 registered
                         DocksLevel: Invalid resource (depends on broken enemy.gd)
                         User reports: "все враги сломались"
2026-03-18 ~10:00 UTC  AI session starts (this session)
                       Game log downloaded and analyzed
                       Root cause identified: Variant inference parse errors in components
```

### Fix

Add explicit type annotations to prevent Variant inference in all affected components:

**`enemy_sniper_component.gd` (our new code):**
```gdscript
# Before (line 33-34, caused Variant inference on player.global_position)
var distance_to_player := _enemy.global_position.distance_to(player.global_position)

# After
var player_pos: Vector2 = (player as Node2D).global_position
var distance_to_player: float = _enemy.global_position.distance_to(player_pos)

# Before (line 40, _apply_wall_avoidance() return type unknown)
retreat_dir = _enemy._apply_wall_avoidance(retreat_dir)

# After
retreat_dir = (_enemy._apply_wall_avoidance(retreat_dir) as Vector2)

# Before (line 107, _get_bullet_spawn_position() return type unknown)
var spawn_pos := _enemy._get_bullet_spawn_position(to_target)

# After
var spawn_pos: Vector2 = _enemy._get_bullet_spawn_position(to_target)
```

**`suppressive_fire_component.gd` (pre-existing bug, fixed in this PR):**
```gdscript
# Before
var spawn_pos := _enemy._get_bullet_spawn_position(...)
# After
var spawn_pos: Vector2 = _enemy._get_bullet_spawn_position(...)
```

**`enemy_flashlight_component.gd` (pre-existing bug, fixed in this PR):**
```gdscript
# Before
var angle_to_player := abs(beam_direction.angle_to(to_player))
var enemy_name := _enemy.name if _enemy else "Unknown"
# After
var angle_to_player: float = abs(beam_direction.angle_to(to_player))
var enemy_name: String = str(_enemy.name) if _enemy else "Unknown"
```

**`black_metal_lightning_effects_manager.gd` (pre-existing bug, fixed in this PR):**
```gdscript
# Before
var idx := clamp(int(t * float(points.size() - 1)), 0, points.size() - 2)
var i := floor(t)
var glow_alpha := clamp(cf * intensity * 0.5, 0.0, 1.0)
# After
var idx: int = clamp(...)
var i: float = floor(t)
var glow_alpha: float = clamp(...)
```

### Prevention

1. **Always use explicit type annotations** when calling custom methods on base-typed parent references:
   ```gdscript
   var result: Vector2 = parent._custom_method()  # ✅ correct
   var result := parent._custom_method()           # ❌ Variant inferred if return type unknown
   ```

2. **When ternary expressions mix types** (e.g., `StringName` vs `String`), use `str()` to normalize:
   ```gdscript
   var name: String = str(node.name) if node else "default"
   ```

3. **Add a CI check** that catches Variant-inference warnings in GDScript to prevent regressions.

---

## References

- Issue #1125: Added sniper weapon type (ASVK) to enemy system
- Issue #1033: Machine gunner blind fire pattern (reference implementation)
- Issue #910: Suppressive fire component (pre-existing Variant inference bug)
- Issue #824: Enemy flashlight component (pre-existing Variant inference bug)
- Godot Issue #75684: Headless export doesn't generate global_script_class_cache.cfg properly
- Godot Issue #79153: Parser Error cascades when class registration fails

## Attached Data

- `game_log_20260318_095818.txt` — User's game log showing enemy breaking (0 enemies registered)
