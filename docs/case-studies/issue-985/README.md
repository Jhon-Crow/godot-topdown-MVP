# Issue #985: Black Metal Visual Filter and Last Chance Effect

## Summary

Issue #985 reported two problems with the Black Metal difficulty mode:
1. Weapon muzzle flashes and explosions were being filtered (appearing as red circles instead of normal)
2. The last chance effect should not work on this difficulty

## Root Cause Analysis

### Problem 1: Weapon Flashes Being Filtered

The Black Metal shader (`scripts/shaders/black_metal.gdshader`) uses a post-processing filter that converts most colors to high-contrast black-and-white while preserving:
- Red-dominant pixels (blood, health indicators)
- Warm/fiery pixels (orange, yellow explosions)

The shader's "fire detection" logic was:
```glsl
float warmth = (original.r + original.g) * 0.5 - original.b;
float is_fire = step(fire_threshold, warmth) * step(0.2, original.r) * (1.0 - is_red);
```

This failed to detect very bright/white-ish pixels that are common in:
- Muzzle flash centers: `Color(1.0, 0.95, 0.9)` → warmth = 0.075 < 0.25 threshold
- Flashbang explosions: `Color(1.0, 1.0, 0.9)` → warmth = 0.1 < 0.25 threshold

These bright pixels were converted to B&W, making flashes appear as solid circles instead of bright bursts.

### Problem 2: Last Chance Effect in Black Metal

The last chance effect (`scripts/autoload/last_chance_effects_manager.gd`) is designed for Hard difficulty mode. It triggers when:
- Player has 1 HP or less
- An enemy bullet enters the player's threat sphere
- The effect hasn't been used this life

The code checked `difficulty_manager.is_hard_mode()` which returns `false` for Black Metal (since Black Metal is a separate difficulty enum value). However, there was no explicit check to reject Black Metal mode, making the code less maintainable.

## Solution

### Fix 1: Enhanced Flash Detection in Shader

Added a new detection path for bright warm pixels:
```glsl
// Detect bright warm pixels (weapon flash centers, explosion cores)
float warm_bias = step(original.b * 1.5, original.r + original.g);  // r+g >= b*1.5
float is_bright_flash = step(bright_flash_threshold, lum) * warm_bias * (1.0 - is_red);

// Combine fire detection: either standard warmth OR bright flash
float is_fire_or_flash = max(is_fire, is_bright_flash);
```

This preserves pixels that are:
- Very bright (luminance >= 0.85)
- Have a warm bias (red + green >= blue * 1.5)

### Fix 2: Explicit Black Metal Check for Last Chance

Added explicit check in `_can_trigger_effect()`:
```gdscript
if difficulty_manager.is_black_metal_mode():
    _log("Black Metal mode - last chance effect disabled (Issue #985)")
    return false
```

This makes the code explicitly document that Black Metal should not have the last chance effect.

## Files Changed

1. `scripts/shaders/black_metal.gdshader`
   - Added `bright_flash_threshold` uniform
   - Added bright flash detection logic
   - Combined fire and flash detection

2. `scripts/autoload/black_metal_effects_manager.gd`
   - Added `bright_flash_threshold` shader parameter initialization

3. `scripts/autoload/last_chance_effects_manager.gd`
   - Added explicit Black Metal mode check in `_can_trigger_effect()`

## Testing

Test scripts created:
- `experiments/test_black_metal_flash_detection.gd` - Verifies shader color classification
- `experiments/test_black_metal_last_chance_disabled.gd` - Verifies last chance trigger logic

## Technical Notes

### Black Metal Shader Layer Architecture
- Black Metal filter: CanvasLayer 97
- Hit/blood effects: CanvasLayer 100+
- Last chance overlay: CanvasLayer 102
- Power fantasy overlay: CanvasLayer 103

The filter affects everything below layer 97, including:
- MuzzleFlash (z_index = 10)
- ExplosionFlash (z_index = 10)
- All game world rendering

### Color Detection Thresholds

| Parameter | Value | Purpose |
|-----------|-------|---------|
| red_threshold | 0.15 | Minimum red dominance for "red" classification |
| fire_threshold | 0.25 | Minimum warmth for standard fire detection |
| bright_flash_threshold | 0.85 | Minimum luminance for bright flash detection |
| warm_bias multiplier | 1.5 | Minimum r+g to b ratio for warm bias |

### Example Color Classifications

| Color | RGB | Classification |
|-------|-----|----------------|
| Muzzle flash particle | (1.0, 0.9, 0.5) | Fire (warmth = 0.45) |
| Muzzle flash light | (1.0, 0.8, 0.4) | Fire (warmth = 0.5) |
| Frag explosion | (1.0, 0.6, 0.2) | Fire (warmth = 0.6) |
| Flashbang | (1.0, 0.95, 0.9) | Bright flash (lum = 0.97) |
| Blood | (0.8, 0.1, 0.1) | Red (dominance = 0.7) |
| Gray wall | (0.5, 0.5, 0.5) | B&W |
