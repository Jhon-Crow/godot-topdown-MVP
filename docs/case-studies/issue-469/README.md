# Case Study: Issue #469 - Flashbang Visual Effect Wall Blocking

## Issue Summary

**Issue**: "визуальный и обычный эффект светошумовой гранаты не должен проходить сквозь стены (как это работает для вспышки)"

**Translation**: "The visual and regular effect of the flashbang grenade should not pass through walls (as it works for flash [muzzle flash])"

**Root Cause**: The flashbang grenade's visual flash effect was not using shadow-enabled lighting like the weapon muzzle flash does, causing the flash to visually pass through walls.

## Timeline of Events

### Initial Implementation (PR #475 - First Draft)

1. **Audio Wall Blocking**: Added line-of-sight check to `_is_player_in_zone()` for audio effects
2. **Enemy Targeting**: Already had wall blocking via `_has_line_of_sight_to()` for enemy targeting
3. **Visual Effect**: NOT modified - still used simple Sprite2D without wall blocking

### User Feedback (2026-02-04)

User @Jhon-Crow reported:
> "не вижу визуальных изменений" (I don't see visual changes)
>
> "посмотри как сделана вспышка оружия в main" (look at how the weapon muzzle flash is done in main)

## Root Cause Analysis

### How Weapon Muzzle Flash Works (Reference Implementation)

The weapon muzzle flash (`scenes/effects/MuzzleFlash.tscn`) uses:

1. **PointLight2D** with `shadow_enabled = true`
   - Shadows are cast by walls (collision layer 3, bitmask 4)
   - Light naturally stops at walls due to shadow casting
   - Configuration:
     ```
     shadow_enabled = true
     shadow_color = Color(0, 0, 0, 0.8)
     shadow_filter = 1 (PCF5)
     shadow_filter_smooth = 4.0
     ```

2. **GPUParticles2D** for visual sparks
   - Short-lived particles (0.04s lifetime)
   - Emitted at barrel position

The key insight: **The light doesn't need raycast checks because the shadow system handles wall occlusion automatically.**

### How Flashbang Visual Effect Was Implemented (Bug)

The flashbang (`scripts/projectiles/flashbang_grenade.gd`) used:

```gdscript
func _spawn_flash_effect() -> void:
    var impact_manager = get_node_or_null("/root/ImpactEffectsManager")
    if impact_manager and impact_manager.has_method("spawn_flashbang_effect"):
        impact_manager.spawn_flashbang_effect(global_position, effect_radius)
    else:
        _create_simple_flash()  # Fallback
```

**Problems**:
1. `ImpactEffectsManager` does NOT have `spawn_flashbang_effect` method
2. `_create_simple_flash()` creates a simple Sprite2D with NO shadow casting
3. The Sprite2D renders on top of everything including walls

### The Missing Piece

The flashbang visual effect needed:
- A `PointLight2D` with `shadow_enabled = true` (like muzzle flash)
- Large radius matching the effect_radius (400px)
- Bright white/yellow color for flashbang effect
- Fade animation over time

## Solution

### 1. Create FlashbangEffect Scene

Created `scenes/effects/FlashbangEffect.tscn` with:
- PointLight2D with shadow_enabled = true
- Larger radius for 400px effect area
- Bright white flash color
- Script to handle fade animation

### 2. Add spawn_flashbang_effect to ImpactEffectsManager

Added method to `scripts/autoload/impact_effects_manager.gd`:
- Instantiates FlashbangEffect scene
- Positions at grenade explosion position
- Effect auto-cleans up after animation

### 3. Keep Existing Wall Blocking for Audio

The `_is_player_in_zone()` line-of-sight check remains for audio:
- Player behind wall hears distant explosion sound
- Player with clear sight hears close-up flashbang effect

## Comparison: Before vs After

| Aspect | Before (Bug) | After (Fixed) |
|--------|-------------|---------------|
| Visual light | Sprite2D (no shadows) | PointLight2D (shadow_enabled) |
| Wall occlusion | None | Automatic via shadow casting |
| Player audio | Uses line-of-sight check | Uses line-of-sight check (unchanged) |
| Enemy targeting | Uses line-of-sight check | Uses line-of-sight check (unchanged) |

## Files Modified

1. `scenes/effects/FlashbangEffect.tscn` - NEW: Shadow-casting flashbang visual effect
2. `scripts/effects/flashbang_effect.gd` - NEW: Animation script for flashbang effect
3. `scripts/autoload/impact_effects_manager.gd` - Added `spawn_flashbang_effect()` method
4. `scripts/projectiles/flashbang_grenade.gd` - Uses new effect (no changes needed, fallback works)

## Test Plan

- [ ] Flashbang visual effect uses PointLight2D with shadow_enabled
- [ ] Flash light stops at walls (doesn't illuminate areas behind walls)
- [ ] Player behind wall sees reduced/no flash (light blocked by shadow)
- [ ] Player with clear line of sight sees full flash effect
- [ ] Audio wall blocking still works (distant vs close sounds)
- [ ] Enemy targeting wall blocking still works

## Lessons Learned

1. **Reference existing implementations**: The weapon muzzle flash already solved the wall-blocking problem using Godot's shadow system
2. **Don't reinvent the wheel**: PointLight2D shadows are GPU-accelerated and more efficient than manual raycasting for visual effects
3. **Verify all aspects**: Initial fix only addressed audio, missing the visual component

## Related Files

- `docs/case-studies/issue-469/game_log_20260204_094159.txt` - Game log from user testing
