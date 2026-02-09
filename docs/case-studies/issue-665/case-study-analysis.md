# Case Study: Issue #665 - Fix Sniper Enemies

## Summary

Sniper enemies (added in PR #582) had three critical bugs:
1. They don't hide from the player (no cover-seeking behavior)
2. Their shots lack smoke/tracer trails (unlike the player's sniper rifle)
3. They don't deal damage to the player (hitscan not reaching targets)

An additional problem reported in comments: snipers don't move/relocate.

## Timeline of Events

### Phase 1: Original Implementation (PR #582)

PR #582 introduced sniper enemies with:
- `SniperComponent` class (`scripts/components/sniper_component.gd`) with static utility functions
- SNIPER weapon type (index 4) in `WeaponConfigComponent`
- Hitscan shooting with wall penetration (up to 2 walls)
- Spread calculation based on distance and wall count
- Red laser sight (Line2D with z_index=100)
- Smoke tracer (Line2D with gradient fade)
- Bolt-action cycling (2s between shots)
- Slow rotation speed (1.0 rad/s, ~25x slower than rifle enemies)

### Phase 2: Failed Fix Attempt (PR #666)

PR #666 attempted to fix sniper issues over **19 rounds** of feedback, encountering:
- **Round 2**: `enemy.call("_method_name")` failed silently in exported Godot builds due to GDScript 4.x static method dispatch
- **Round 6**: COMBAT<->SEEKING_COVER state thrashing when player was close
- **Round 7**: Hitscan couldn't damage GDScript player because it checked for `take_damage()` but the player uses `on_hit()` / `on_hit_with_info()` / `on_hit_with_bullet_info()`
- **Round 7**: Sniper muzzle position behind wall prevented hitscan from working (muzzle offset placed spawn point inside wall geometry)

### Phase 3: Merge Gap

The sniper code from PR #582 was apparently not fully merged to main. The current `main` branch had:
- **No** SNIPER entry in the WeaponType enum
- **No** `_is_sniper` flag in enemy.gd
- **No** sniper-specific state processing
- **No** `sniper_component.gd` file

This means any enemy placed with `weapon_type = 4` (SNIPER) would fall through to default RIFLE behavior with no hitscan, no laser, no tracer, and no appropriate cover behavior.

## Root Cause Analysis

### Root Cause 1: Missing Sniper Code
The sniper weapon type (SNIPER = 4) was not present in the merged codebase. Any enemy configured as a sniper would default to rifle behavior, explaining all three symptoms.

### Root Cause 2: Architectural Mismatch
The original PR #582 attempted to use `SniperComponent` static methods with `enemy.call()` for state processing. This fails in GDScript 4.x exported builds because:
- `call()` cannot reliably dispatch to static methods on RefCounted classes
- Type information is lost when passing `enemy` as `Node2D` to static functions that need access to enemy-specific properties

### Root Cause 3: Hitscan Origin Position
The original implementation spawned hitscan rays from the weapon muzzle position (offset 45-52px from enemy center). When enemies stand near walls/cover, this offset can place the ray origin inside wall geometry, causing the hitscan to hit the wall immediately and never reach the player.

### Root Cause 4: Damage Method Incompatibility
The hitscan damage code only checked for `take_damage()` and `TakeDamage()`, but the player character uses `on_hit()`, `on_hit_with_info()`, and `on_hit_with_bullet_info()`. This meant the hitscan would register hits but never actually apply damage.

## Solution

### Architecture Decision: Inline vs Component

We chose a **hybrid approach**:
- **Utility functions** (hitscan, tracer, laser, spread, casing) remain in `SniperComponent` as static functions since they only use `Node2D`-level properties
- **State processing** (combat state, cover state) is **inlined** directly in `enemy.gd` to avoid call dispatch issues

### Key Implementation Details

1. **Hitscan from center**: Ray starts from `global_position + weapon_forward * 10.0` (small offset from center) instead of muzzle position, avoiding the wall-behind-muzzle problem

2. **Multiple damage methods**: `perform_hitscan()` tries damage methods in order: `on_hit_with_bullet_info()` > `on_hit_with_info()` > `on_hit()` > `take_damage()` > `TakeDamage()`, supporting both GDScript and C# targets

3. **State thrashing prevention**: A `_sniper_retreat_cooldown` (3s) prevents rapid COMBAT<->SEEKING_COVER transitions when the player is near the distance threshold

4. **Sniper-specific behaviors**:
   - Slow rotation (1.0 rad/s) - snipers don't snap-aim
   - No pursuit - snipers seek cover instead of chasing
   - Cover preference near spawn position - snipers hold their position
   - Don't shoot while relocating - too slow to aim on the move
   - Bolt-action cycling (2s between shots)

### Files Modified

| File | Change |
|------|--------|
| `scripts/components/sniper_component.gd` | Created - static utility functions |
| `scripts/components/weapon_config_component.gd` | Added SNIPER (type 4) config |
| `scripts/objects/enemy.gd` | Added sniper state vars, overrides, and helper functions |

## Data Files

- `issue-description.md` - Original issue text (Russian)
- `game_log_20260208_183844.txt` - Game log from issue reporter (5541 lines)

## Lessons Learned

1. **GDScript 4.x `call()` limitations**: Static method dispatch via `call()` is unreliable in exported builds. Prefer direct method calls or inline the logic.

2. **Hitscan origin matters**: When enemies use cover, the weapon muzzle can be inside wall geometry. Use enemy center position for hitscan origin.

3. **Damage interface compatibility**: Always support all damage interfaces in the codebase (GDScript and C# variants) when implementing cross-cutting damage systems.

4. **State thrashing prevention**: Distance-based state transitions need cooldowns to prevent rapid oscillation at boundary distances.

5. **Merge verification**: After complex PRs, verify that all code actually landed in the target branch.
