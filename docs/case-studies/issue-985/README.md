# Issue #985: Black Metal Visual Filter and Last Chance Effect

## Summary

Issue #985 reported two problems with the Black Metal difficulty mode:
1. Weapon muzzle flashes and explosions were being filtered (appearing as red circles instead of normal)
2. The last chance effect should not work on this difficulty

## Root Cause Analysis

### Problem 1: Weapon Flashes Appearing as Red Circles (Two-Stage Bug)

The Black Metal shader (`scripts/shaders/black_metal.gdshader`) uses a post-processing filter.

#### Stage 1 (first attempt - partially fixed by PR #987 v1):
The original fire detection `(1.0 - is_red)` guard was added to prevent red pixels from being classified as fire. A "bright flash" detection was added for near-white pixels.

#### Stage 2 (confirmed by game_log_20260309_194328.txt after v1 fix):
Game log from 2026-03-09 19:43 confirmed flashes STILL appeared as red circles after v1.

**Root cause (v2 analysis):** Orange/yellow explosion particle colors like `(1.0, 0.7, 0.2)` are classified as BOTH red AND fire-eligible:
- `red_dominance = r - max(g, b) = 1.0 - 0.7 = 0.3 ≥ 0.15` → `is_red = 1`
- `warmth = (1.0 + 0.7)*0.5 - 0.2 = 0.65 ≥ 0.25`

But the `(1.0 - is_red)` guard in `is_fire` set it to 0 for these pixels, so they stayed as vivid red instead of being preserved as orange.

**All actual explosion/muzzle flash colors affected:**
| Color | RGB | Red dominance | Effect |
|-------|-----|---------------|--------|
| Muzzle flash particle (outer) | (0.9, 0.4, 0.1) | 0.5 | Turned red |
| Frag explosion particle | (1.0, 0.7, 0.3) | 0.3 | Turned red |
| Frag light | (1.0, 0.6, 0.2) | 0.4 | Turned red |
| Muzzle flash light | (1.0, 0.8, 0.4) | 0.2 | Turned red |

The key insight: orange = high green channel. Blood = very low green channel. The previous code treated all red-dominant pixels the same, but orange fire always has `g ≥ 0.35` while blood/damage has `g < 0.2`.

### Problem 2: Last Chance Effect in Black Metal

The last chance effect (`scripts/autoload/last_chance_effects_manager.gd`) is designed for Hard difficulty mode. It triggers when:
- Player has 1 HP or less
- An enemy bullet enters the player's threat sphere
- The effect hasn't been used this life

The code checked `difficulty_manager.is_hard_mode()` which returns `false` for Black Metal (since Black Metal is a separate difficulty enum value). However, there was no explicit check to reject Black Metal mode, making the code less maintainable.

## Solution

### Fix 1 (v2): Correct Orange Fire vs Red Blood Detection in Shader

Changed the fire detection from `(1.0 - is_red)` guard to a **green-channel check**:
```glsl
// v2: Use step(0.30, original.g) to distinguish orange fire (moderate-to-high green)
// from pure red blood (very low green)
float is_fire = step(fire_threshold, warmth) * step(0.30, original.g) * step(0.2, original.r);

// v2: Remove (1-is_red) from bright flash - use warm_bias alone
float is_bright_flash = step(bright_flash_threshold, lum) * warm_bias;
```

Why this works:
- Orange fire `(1.0, 0.7, 0.2)`: `g = 0.7 ≥ 0.30` → `is_fire = 1` → preserved as original orange ✓
- Dark orange edge `(0.8, 0.3, 0.1)`: `g = 0.3 ≥ 0.30` → `is_fire = 1` → preserved ✓
- Red blood `(0.8, 0.1, 0.1)`: `g = 0.1 < 0.30` → `is_fire = 0` → stays vivid red ✓
- Since `is_fire_or_flash` overrides `is_red` in the mixing, orange pixels are correctly preserved even when `is_red = 1`

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
| green_fire_threshold | 0.30 | Minimum green channel to classify as orange/yellow fire (v2) |
| warm_bias multiplier | 1.5 | Minimum r+g to b ratio for warm bias |

### Example Color Classifications (v2 shader)

| Color | RGB | is_red | is_fire (v2) | is_bright | Final |
|-------|-----|--------|---------|-----------|-------|
| Muzzle flash particle center | (1.0, 0.9, 0.5) | 1 (r-g=0.1) | 1 (g=0.9≥0.30) | - | Preserved (fire wins) |
| Muzzle flash particle outer | (0.9, 0.4, 0.1) | 1 (r-g=0.5) | 1 (g=0.4≥0.30) | - | Preserved (fire wins) |
| Muzzle flash particle edge | (0.8, 0.3, 0.1) | 1 (r-g=0.5) | 1 (g=0.3≥0.30) | - | Preserved (fire wins) |
| Muzzle flash light | (1.0, 0.8, 0.4) | 1 | 1 (g=0.8≥0.30) | - | Preserved (fire wins) |
| Frag explosion light | (1.0, 0.6, 0.2) | 1 | 1 (g=0.6≥0.30) | - | Preserved (fire wins) |
| Flashbang | (1.0, 0.95, 0.9) | 0 | 0 (warmth=0.075) | 1 (lum=0.97) | Preserved |
| Blood | (0.8, 0.1, 0.1) | 1 | 0 (g=0.1<0.30) | 0 | Vivid Red |
| Health indicator red | (0.9, 0.1, 0.1) | 1 | 0 (g=0.1<0.30) | 0 | Vivid Red |
| Gray wall | (0.5, 0.5, 0.5) | 0 | 0 | 0 | B&W |

## Logs and Evidence

- `game_log_20260309_194328.txt`: Game session log from 2026-03-09 showing:
  - Line `[19:43:41] [LastChance] Black Metal mode - last chance effect disabled (Issue #985)` confirms last chance IS disabled (v1 fix worked for this)
  - The log also shows "Black Metal shader loaded (B&W+red, hint_screen_texture approach)" which is the v1 shader version
  - The visual bug (red circles) was confirmed by the owner after v1 - indicating the orange→red color misclassification was the remaining issue
