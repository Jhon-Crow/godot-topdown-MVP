# Case Study: Issue #579 - Machete Enemy Type

## Problem Statement

Add a new enemy type: a machete-wielding melee combatant with distinct tactical behaviors:
1. Hides and approaches nearest cover (stealth approach)
2. Attempts to attack from behind or when player is under fire
3. In attacking state, dodges bullets instead of hiding
4. Create a Beach map with these enemies

## Architecture Analysis

### Existing Enemy System

The current enemy system (`scripts/objects/enemy.gd`, ~5000 lines) supports:
- **3 weapon types**: RIFLE (M16), SHOTGUN, UZI - all ranged
- **11 AI states**: IDLE, COMBAT, SEEKING_COVER, IN_COVER, FLANKING, SUPPRESSED, RETREATING, PURSUING, ASSAULT, SEARCHING, EVADING_GRENADE
- **2 behavior modes**: PATROL, GUARD
- **GOAP planning**: Action-based decision making
- **Components**: VisionComponent, CoverComponent, ThreatSphere, GrenadeAvoidanceComponent, EnemyMemory

### Key Design Decision: Extend vs. New Script

**Option A: New separate script** - Creates code duplication, hard to maintain
**Option B: Extend existing enemy.gd** - Add MACHETE weapon type with melee-specific behaviors

**Chosen: Option B** - The existing enemy.gd already has sophisticated AI, cover system, flanking, and threat detection. Adding a new weapon type with behavioral overrides is cleaner than duplicating 5000 lines.

## Implementation Design

### 1. MACHETE Weapon Type (WeaponType.MACHETE = 3)

- No bullet_scene (melee only)
- No casing_scene
- Attack range: 80px (melee range)
- Attack cooldown: 1.5s
- Damage: 2 (higher than single bullet)
- Weapon sprite: machete_topdown.png
- No ammunition system (infinite melee)
- No reload mechanic

### 2. New AI Behaviors for Machete

#### Sneaking Approach (Modified PURSUING)
- Uses cover-to-cover movement like PURSUING but quieter
- Lower movement speed when near player (stealth)
- Prefers cover positions that approach from behind the player

#### Backstab Preference
- Calculates player's facing direction
- Prioritizes approach paths behind the player
- When player is engaged with other enemies (under fire), rushes in

#### Bullet Dodging (DODGING state)
- When in melee attack range and bullets enter threat sphere
- Instead of seeking cover, performs lateral dodge
- Quick side-step movement perpendicular to bullet direction
- Short dodge cooldown to prevent constant dodging

### 3. Beach Map

- Open outdoor level with scattered cover (palm trees, beach huts, rocks, barrels)
- Mix of machete enemies and ranged enemies
- Sandy terrain with water boundary
- Navigation mesh covering playable area

## Technical References

- WeaponConfigComponent: `scripts/components/weapon_config_component.gd`
- Enemy AI: `scripts/objects/enemy.gd`
- Cover System: `scripts/components/cover_component.gd`
- Threat Detection: `scripts/components/threat_sphere.gd`
- Level Template: `scenes/levels/BuildingLevel.tscn`
- Level Script: `scripts/levels/building_level.gd`

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Breaking existing enemies | MACHETE-specific code gated behind weapon_type check |
| State machine complexity | Reuse existing states where possible |
| CI validation failures | Follow architecture-check.yml patterns |
| Gameplay balance | Machete enemies are high-risk melee fighters |

## Bug Report: All Enemies Broken (Post-Implementation)

### Symptoms Reported by User

From game log `game_log_20260207_172131.txt`:
- `has_died_signal=false` for ALL enemies (not just machete)
- `0 enemies registered` in score/replay systems
- No enemy AI behavior at all
- Beach level not accessible from levels menu

### Root Cause

**GDScript Parse Error** in `enemy.gd` lines 1364 and 1966:

```
SCRIPT ERROR: Parse Error: Cannot infer the type of "bd" variable because the value doesn't have a set type.
          at: GDScript::reload (res://scripts/objects/enemy.gd:1364)
ERROR: Failed to load script "res://scripts/objects/enemy.gd" with error "Parse error".
```

The original code used `:=` (type inference) for a variable initialized from a ternary expression on a Variant value:

```gdscript
var bd := b.direction if b.get("direction") != null else Vector2.RIGHT.rotated(b.rotation)
```

`b` comes from `_bullets_in_threat_sphere[0]` which is an untyped `Array`, so `b` is `Variant`. The ternary branches return `Variant` (from `b.direction`) and `Vector2` (from `Vector2.RIGHT.rotated(...)`), making GDScript unable to infer the type for `bd`.

### Why ALL Enemies Break

When a GDScript file has ANY parse error, Godot fails to load the ENTIRE script. This means:
1. ALL enemies using `enemy.gd` lose their script functionality
2. They fall back to the base `CharacterBody2D` class
3. The `died` signal (declared in enemy.gd) is no longer available
4. `has_signal("died")` returns `false`
5. Level scripts can't register any enemies
6. Score tracking, replay, and death handling all break

### Why Beach Level Was Missing

The Beach level scene and script were created but never added to the `LEVELS` array in `scripts/ui/levels_menu.gd`. Without an entry in this array, the level doesn't appear in the card-based level selection menu.

### Historical Pattern

This exact symptom (`has_died_signal=false`) has occurred multiple times in this project:
- **Issue #377**: Typo referencing undefined variable (`max_grenade_throw_distance` vs `grenade_max_throw_distance`)
- **Issue #363**: Typed class reference causing script load failure
- **Issue #424**: Implicit type inference on polymorphic return value (`collision.get_collider()`)

All share the same root cause pattern: GDScript parse errors silently break the entire script in export builds.

### Fix Applied

1. **Type inference fix**: Changed `var bd := ...` to `var bd: Vector2 = b.get("direction") if ...` with explicit type annotation
2. **Safe property access**: Changed `b.direction` to `b.get("direction")` for safer Variant property access
3. **Removed unused variable**: Removed `@onready var _sprite: Sprite2D` (duplicate of `_body_sprite`)
4. **Beach level registration**: Added Beach level entry to `LEVELS` array in `levels_menu.gd`
5. **Updated tests**: Updated level count test from 4 to 5

### Lessons Learned

1. **NEVER use `:=` (type inference) with Variant values** - always use explicit type annotations (`var x: Type = ...`)
2. **Use `.get()` for dynamic property access on Variants** - direct property access (`b.direction`) can cause parse errors
3. **Check CI import logs for GDScript parse errors** - even when CI tests pass, the import step may log script parse errors that indicate export build failures
4. **New levels must be registered in the levels menu** - creating a scene/script is not enough; the level must be added to the `LEVELS` array
5. **Pre-existing CI pattern**: The `SCRIPT ERROR: Parse Error` messages in CI import logs were visible but did not cause CI failure because the test itself uses a MockEnemy class
