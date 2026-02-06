# Case Study: Issue #505 — Power Fantasy Time-Freeze During Explosion

## Issue Summary

In Power Fantasy mode, three related bugs with the time-freeze mechanic during grenade explosions:

1. **Flashbang/explosion visual effects fade out instead of freezing** — the glow effect should stay visible (frozen) while time is stopped, but it was fading away because its `_process()` kept running.
2. **Enemy grenade explosions should also trigger time-freeze** — when enemies throw grenades and they explode, the same Power Fantasy time-freeze should activate.
3. **Conflict between grenade time-freeze and kill effect** — when a grenade kills enemies, both the 2000ms grenade time-freeze (`LastChanceEffectsManager`) and the 300ms kill effect (`PowerFantasyEffectsManager`) activate simultaneously, causing the kill effect to reset `Engine.time_scale` to 1.0 while the node-based freeze is still active.

## Timeline of Events (from game log)

```
[14:35:18] Grenade explodes → on_grenade_exploded() triggers LastChance 2000ms freeze
[14:35:18] Grenade kills Enemy2 → on_enemy_killed() triggers PowerFantasy 300ms effect (Engine.time_scale = 0.1)
[14:35:18] Grenade kills Enemy3 → on_enemy_killed() resets kill effect timer to 300ms
[14:35:18] Shrapnel spawns → LastChance correctly freezes 40 shrapnel pieces
[14:35:18] Explosion visual spawns → PointLight2D frozen, but Node2D parent still fading
[14:35:18] PowerFantasy kill effect expires after 304ms → Engine.time_scale reset to 1.0
           ❌ BUG: LastChance freeze is still active for ~1700ms more
[14:35:20] LastChance effect expires after 2.02s → ends normally
```

## Root Cause Analysis

### Bug 1: Explosion visual effects not frozen

**Root Cause:** The `LastChanceEffectsManager._on_node_added_during_freeze()` correctly freezes `PointLight2D` nodes (the light itself), but the flashbang/explosion effect is a `Node2D` container with a `PointLight2D` child. The parent `Node2D` has a `_process()` method that controls the fade-out animation. Since `Node2D` is treated as a container node (not frozen, only children recursed), the fade-out animation kept running.

Similarly, `_freeze_node_except_player()` traverses container `Node2D` nodes without freezing them, but these specific `Node2D` nodes (with `flashbang_effect.gd` or `explosion_flash.gd` scripts) need to be frozen to pause their fade animation.

**Files affected:**
- `scripts/effects/flashbang_effect.gd` — `_process(delta)` fades `PointLight2D.energy`
- `scripts/effects/explosion_flash.gd` — `_process(delta)` fades `PointLight2D.energy`

### Bug 2: Enemy grenade explosions

**Root Cause:** This was already working correctly in code. The `GrenadeBase._explode()` method (line 391-394) calls `PowerFantasyEffectsManager.on_grenade_exploded()` for ALL grenades, regardless of who threw them. Enemy grenades use `FragGrenade` which extends `GrenadeBase`, so the call chain is intact.

In the game log, enemies never successfully threw grenades because they consistently failed the safety distance check (`238 < 275 safe distance`). No code change was needed.

### Bug 3: Kill effect conflicting with grenade freeze

**Root Cause:** Two independent effect systems conflicting:

| System | Time mechanism | Duration | Trigger |
|--------|---------------|----------|---------|
| `LastChanceEffectsManager` | `Node.PROCESS_MODE_DISABLED` | 2000ms | Grenade explosion |
| `PowerFantasyEffectsManager` | `Engine.time_scale = 0.1` | 300ms | Enemy killed |

When a grenade explodes and kills enemies simultaneously:
1. `LastChanceEffectsManager` freezes all nodes (2000ms)
2. `PowerFantasyEffectsManager` sets `Engine.time_scale = 0.1` (300ms)
3. After 300ms, `PowerFantasyEffectsManager._end_effect()` resets `Engine.time_scale = 1.0`
4. This happens while `LastChanceEffectsManager` is still active for ~1700ms more

The reset of `Engine.time_scale` doesn't break the node-based freeze directly, but creates inconsistent state and potentially affects any logic that reads `Engine.time_scale`.

## Solution

### Fix 1: Freeze explosion visual containers (Issue #505)

In `last_chance_effects_manager.gd`:
- Added `_frozen_explosion_visuals` array to track frozen `Node2D` explosion effects
- Added `_freeze_explosion_visual()` / `_unfreeze_explosion_visuals()` methods
- Updated `_freeze_node_except_player()` to detect and freeze `Node2D` nodes with `flashbang_effect` or `explosion_flash` scripts
- Updated `_on_node_added_during_freeze()` to detect newly created `Node2D` explosion effects
- Updated `_unfreeze_time()` to call `_unfreeze_explosion_visuals()`
- Updated `reset_effects()` to clear `_frozen_explosion_visuals`

### Fix 2: Enemy grenades (no code change needed)

Enemy grenade explosions already call `PowerFantasyEffectsManager.on_grenade_exploded()` through the inherited `GrenadeBase._explode()` method. No fix was required.

### Fix 3: Prevent kill/grenade effect conflict

In `power_fantasy_effects_manager.gd`:
- Updated `on_enemy_killed()` to check if `LastChanceEffectsManager.is_effect_active()` before starting the kill effect
- If LastChance time-freeze is already active, skip the 300ms kill effect entirely
- This prevents the kill effect from setting `Engine.time_scale = 0.1` and then resetting it to `1.0` while the grenade freeze is ongoing

## Files Modified

- `scripts/autoload/last_chance_effects_manager.gd` — Freeze explosion visual effect containers during time-freeze
- `scripts/autoload/power_fantasy_effects_manager.gd` — Skip kill effect when grenade time-freeze is active

## Test Verification

The fix addresses the following scenarios:
1. **Flashbang grenade in Power Fantasy**: Flash glow stays visible while time is frozen, then resumes fading when time unfreezes
2. **Defensive/Frag grenade in Power Fantasy**: Explosion flash stays visible during freeze
3. **Grenade kills enemies during freeze**: Kill effect is suppressed, no `Engine.time_scale` conflict
4. **Enemy grenade explodes in Power Fantasy**: Time-freeze triggers correctly (already worked)
