# Case Study: Issue #432 - Shell Casings React to Explosions

## Issue Summary

**Issue**: [#432](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/432)
**Title**: гильзы на полу должны реагировать на взрывы (Shell casings on the floor should react to explosions)
**Author**: Jhon-Crow
**Status**: In Progress

## Requirements

The issue describes three requirements for shell casing behavior:

1. **Lethal blast zone**: Shell casings on the floor should scatter/fly away when they are within the lethal blast zone of an explosion.

2. **Proximity effect**: If casings are close to the lethal blast zone or close to the epicenter of a non-lethal explosion, they should move slightly (even weaker than when pushed by player/enemy).

3. **Multi-source compatibility**: This behavior should work with grenades from both the player and enemy.

## Timeline

| Date | Event |
|------|-------|
| 2026-02-03 | Issue created |
| 2026-02-03 | Implementation started |
| 2026-02-03 | Initial PR #434 opened |
| 2026-02-03 | User feedback: "grenades fly infinitely and don't explode" |
| 2026-02-03 | Investigation: Branch was missing fixes from main (Issue #428, #438) |
| 2026-02-03 | Merged main branch to include latest fixes |

## User Feedback Investigation

### Bug Report
User reported: "гранаты теперь летят бесконечно и не взрываются" (grenades now fly infinitely and don't explode)

### Analysis of Game Log (`logs/game_log_20260203_180528.txt`)

**Key observations:**
1. Grenades are being thrown (log entries show "Grenade thrown!" at multiple timestamps)
2. NO subsequent grenade lifecycle logs appear:
   - Missing: `[GrenadeBase] Grenade created at...`
   - Missing: `[FragGrenade] Pin pulled...`
   - Missing: `[GrenadeBase] Grenade landed at...`
   - Missing: `[FragGrenade] Impact detected - exploding immediately!`
   - Missing: `[GrenadeBase] EXPLODED at...`

**Root cause investigation:**
The Issue #432 changes (adding casing scatter to explosions) cannot cause grenades to not explode because:
1. `casing.gd` change: Only adds casing to a group - does not affect grenade logic
2. `grenade_base.gd` change: Adds `_scatter_casings()` method - only called AFTER explosion
3. `frag_grenade.gd`/`flashbang_grenade.gd` changes: Call `_scatter_casings()` inside `_on_explode()` - only executes after explosion

**Alternative hypotheses:**
1. **Build version mismatch**: User may have been testing an older exported build
2. **Missing branch synchronization**: Branch was missing commits from main:
   - Issue #428 fix (grenade targeting physics compensation)
   - Issue #438 fix (enemies getting stuck in casings)

**Resolution:**
Merged main branch to include all recent fixes. The user should rebuild the export and test again.

## Technical Analysis

### Current Implementation

#### Shell Casings (`scripts/effects/casing.gd`)

- **Type**: RigidBody2D
- **Physics**: gravity_scale = 0.0 (top-down game)
- **Key properties**:
  - Linear damping: 3.0
  - Angular damping: 5.0
  - Auto-land after 2.0 seconds
  - Collision layer 64 (layer 7)
- **Existing method**: `receive_kick(impulse: Vector2)` - Already handles being pushed by player/enemy
- **State tracking**: `_has_landed`, `_is_time_frozen`

#### Grenade System

**FragGrenade (`scripts/projectiles/frag_grenade.gd`)**:
- `effect_radius`: 225.0 pixels (lethal blast zone)
- `explosion_damage`: 99 (flat damage to all in zone)
- Explodes on impact (not timer-based)
- Spawns 4 shrapnel pieces

**FlashbangGrenade (`scripts/projectiles/flashbang_grenade.gd`)**:
- `effect_radius`: 400.0 pixels
- No damage (stun/blind effects only)
- Timer-based (4 second fuse)

### Proposed Solution

The solution leverages the existing `receive_kick()` method in the casing script. During grenade explosion (`_on_explode()`), we need to:

1. Find all casings in the "casings" group (need to add this group)
2. Calculate distance from explosion center to each casing
3. Apply impulse based on:
   - **Inside lethal zone**: Strong impulse (scatter effect)
   - **Just outside lethal zone**: Weak impulse (subtle push)
   - **Far away**: No effect

### Implementation Details

#### Force Calculations

Based on existing casing physics:
- Player kick force: `velocity.length() * CASING_PUSH_FORCE / 100.0` (from `player.gd`)
- CASING_PUSH_FORCE constant: ~3.0 (from player.gd line 60)
- Typical player velocity: 200-300 px/s
- Resulting typical kick: ~6-9 impulse units

For explosion effects, we'll use:
- **Lethal zone (inside radius)**: 30-60 impulse units (strong scatter)
- **Proximity zone (1.0-1.5x radius)**: 5-15 impulse units (weaker than player kick)

#### Direction Calculation

Impulse direction = normalized vector from explosion center to casing position

#### Inverse-square Falloff

Within lethal zone, closer casings receive stronger impulse:
```
impulse_strength = base_strength * (1.0 - (distance / effect_radius))^0.5
```

## Files Modified

1. `scripts/effects/casing.gd` - Add to "casings" group
2. `scripts/projectiles/grenade_base.gd` - Add shared method for casing scattering
3. `scripts/projectiles/frag_grenade.gd` - Call casing scatter on explosion
4. `scripts/projectiles/flashbang_grenade.gd` - Call casing scatter on explosion

## Test Coverage

New tests to be added:
- `test_casing_explosion_reaction.gd` - Unit tests for casing scatter behavior

Test scenarios:
1. Casing inside lethal zone receives strong impulse
2. Casing at proximity zone receives weak impulse
3. Casing far away receives no impulse
4. Landed casings become mobile again after explosion
5. Time-frozen casings don't react to explosions
6. Works with both FragGrenade and FlashbangGrenade

## Related Issues

- Issue #392: Casings pushing player at spawn (fixed with collision delay)
- Issue #424: Reduce casing push force (fixed with 2.5x reduction)
- Issue #375: Enemy grenade safe distance

## References

- [Godot RigidBody2D Documentation](https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html)
- [Godot Physics - Impulse vs Force](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html)
