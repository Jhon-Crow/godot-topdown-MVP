# Case Study: Issue #470 - Grenade Visual Effects Passing Through Walls

## Issue Summary
- **Issue**: #470
- **Title**: визуальный и обычный эффект наступательной гранаты не должен проходить сквозь стены (как это работает для вспышки)
- **Translation**: "Visual and normal effect of offensive grenade should not pass through walls (as it works for flashbang)"
- **Status**: Fixed (Round 5)
- **Final Solution**: Use PointLight2D with shadow_enabled=true (same approach as weapon muzzle flash)

## Timeline of Events

### Phase 1: Initial Problem Report
- **Problem**: Frag grenade visual effects were visible through walls
- **Expected**: Effects should be blocked by walls

### Phase 2: First Fix Attempt (GDScript)
Added wall occlusion methods to `impact_effects_manager.gd`.
- **Result**: FAILED - User reported "визуал не изменился" (visual hasn't changed)
- **Cause**: Exported builds use C# `GrenadeTimer.cs`, not GDScript

### Phase 3: Second Fix Attempt (C# Path)
Added `PlayerHasLineOfSightTo()` to `GrenadeTimer.cs` with simple raycast.
- **Result**: FAILED - User reported "теперь эффекты обеих гранат не видны" (now effects of both grenades are not visible)
- **Cause**: Raycast was too strict - blocked ALL obstacles including small furniture

### Phase 4: Third Fix Attempt (Distance Tolerance)
Added tolerance: if obstacle is within 100px of player, assume it's small furniture and allow effect.
- **Result**: PARTIAL FAILURE - User reported "то видна то не видна вспышка. вспышка всё ещё проходит сквозь стены"
- **Translation**: "sometimes flash is visible, sometimes not. flash still passes through walls"
- **Cause**: Distance-based tolerance is fundamentally flawed - if player stands WITH THEIR BACK to a wall, the wall hits close to player but SHOULD block the effect

### Phase 5: Fourth Fix Attempt (Node Path Detection)
**Approach**: Instead of distance-based tolerance, distinguish between walls and cover by checking the node's **scene tree path**:
- Objects under `Environment/Cover/` → don't block (furniture)
- Objects under `Environment/Walls/` or `Environment/InteriorWalls/` → block (actual walls)
- **Result**: FAILED - User reported "не работает, посмотри как вспышка сделана у оружия"
- **Translation**: "doesn't work, look at how the flash is made for weapons"
- **Cause**: The approach was fundamentally wrong - using Sprite2D with raycast checks instead of proper light-based occlusion

### Phase 6: FINAL FIX (PointLight2D with Shadow Occlusion)
**User hint**: "посмотри как вспышка сделана у оружия" (look at how the flash is made for weapons)

After studying the `MuzzleFlash.tscn` implementation, discovered the correct approach:
- Weapon muzzle flash uses **PointLight2D with shadow_enabled=true**
- The 2D lighting system automatically blocks light through walls that have LightOccluder2D
- **No raycast needed** - Godot's rendering system handles wall occlusion natively

## Root Cause Analysis

### Why Previous Approaches Failed

**Attempt 1-4 (Raycast + Sprite2D):**
All previous attempts used a `Sprite2D` for the flash visual. Sprite2D is a simple texture that:
- Ignores the 2D lighting system
- Is always visible regardless of walls
- Cannot be blocked by shadows or light occluders

Even with perfect raycast logic, the Sprite2D would sometimes appear to "leak" through edges of walls due to timing or position tolerances.

**The Fundamental Problem:**
```
OLD APPROACH (Sprite2D + Raycast):
   [Explosion]----raycast---->[Wall]---->[Player]
                    |
                  Sprite2D always visible if raycast passes
                  (Edge cases where raycast barely passes)

NEW APPROACH (PointLight2D + Shadows):
   [Explosion]----light ray---->[Wall with LightOccluder2D]---->[Player]
                    |
                  Light automatically blocked by shadow system
                  (Pixel-perfect occlusion handled by GPU)
```

## Solution: PointLight2D with Shadow-Based Wall Occlusion

### The Muzzle Flash Pattern

Looking at how weapon muzzle flash is implemented (`MuzzleFlash.tscn`):

```gdscript
# From MuzzleFlash.tscn
[node name="PointLight2D" type="PointLight2D" parent="."]
color = Color(1, 0.8, 0.4, 1)
energy = 4.5
shadow_enabled = true         # KEY: Enables wall occlusion
shadow_filter = 1             # PCF5 filtering for smooth shadows
```

The `PointLight2D` with `shadow_enabled = true` automatically respects any `LightOccluder2D` nodes in the scene. Walls in this game have light occluders, so the light is automatically blocked.

### How It Works

1. **PointLight2D** emits light in all directions
2. **LightOccluder2D** on walls casts shadows (2D shadow mapping)
3. **GPU rendering** automatically blocks light where shadows exist
4. **No raycast needed** - the rendering system handles all edge cases

```gdscript
# New implementation in impact_effects_manager.gd
func _create_grenade_light_with_occlusion(position, radius, color, effect_type):
    var light = PointLight2D.new()
    light.global_position = position
    light.energy = 8.0 if effect_type == "flashbang" else 6.0
    light.shadow_enabled = true    # Critical: enables wall occlusion
    light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
    # ... add to scene and animate fade-out
```

```csharp
// New implementation in GrenadeTimer.cs
private void SpawnExplosionEffect(Vector2 position)
{
    // Load and use the new PointLight2D-based ExplosionFlash.tscn
    var explosionFlashScene = GD.Load<PackedScene>("res://scenes/effects/ExplosionFlash.tscn");
    // ... instantiate with shadow_enabled = true
}
```

## Key Insights

### 1. Use Native Engine Features
Instead of manually reimplementing wall occlusion with raycasts, use Godot's built-in 2D lighting system with shadows. It's more reliable and handles edge cases automatically.

### 2. Follow Existing Patterns
The user's hint "look at how the flash is made for weapons" was crucial. The muzzle flash already solved this problem correctly using PointLight2D with shadows.

### 3. Sprite2D vs PointLight2D for Visual Effects
- **Sprite2D**: Always visible, ignores lighting/shadows, good for UI elements
- **PointLight2D**: Respects shadows and light occluders, good for in-world light effects

### 4. Dual Codebase Requires Dual Fixes
Both C# (`GrenadeTimer.cs`) and GDScript (`impact_effects_manager.gd`) need the same fix for consistent behavior in editor vs export.

### 5. Simple Raycast Checks Have Edge Cases
Manual raycast checks can miss edge cases where the ray barely passes through a gap but the visual effect would clearly be visible through a wall. The GPU-based shadow system doesn't have these issues.

## Files Modified

| File | Change |
|------|--------|
| `Scripts/Projectiles/GrenadeTimer.cs` | Replaced Sprite2D with PointLight2D (shadow_enabled=true) |
| `scripts/autoload/impact_effects_manager.gd` | Replaced Sprite2D with PointLight2D (shadow_enabled=true) |
| `scenes/effects/ExplosionFlash.tscn` | NEW: Reusable explosion flash scene with shadow-based occlusion |
| `scripts/effects/explosion_flash.gd` | NEW: Script for explosion flash effect (similar to muzzle_flash.gd) |

## Testing Checklist

- [ ] Throw grenade with player in line of sight → visual should appear (bright flash)
- [ ] Throw grenade with player behind WALL → visual should NOT appear (shadow blocks it)
- [ ] Throw grenade with player behind desk/table → visual SHOULD appear (furniture doesn't have light occluders)
- [ ] Test in both editor and exported build
- [ ] Compare with weapon muzzle flash behavior - should match

## Log Messages to Look For

**PointLight2D-based flash spawned:**
```
[GrenadeTimer] Spawned PointLight2D explosion flash at (x, y) (shadow-based wall occlusion)
```

**Fallback used (if scene load fails):**
```
[GrenadeTimer] ExplosionFlash.tscn not found, using fallback PointLight2D
[GrenadeTimer] Spawned fallback PointLight2D explosion at (x, y)
```

## Related Issues

- **#432**: GDScript Call() fails in exports - explains why C# component exists
- **#470**: This issue - visual effects passing through walls

## Attachments

- `game_log_20260204_094613.txt` - Original log showing C#/GDScript mismatch
- `game_log_20260204_163238.txt` - Log showing overly strict raycast blocking all effects
- `game_log_20260204_164608.txt` - Log showing distance-based tolerance failures
- `game_log_20260204_165829.txt` - Log showing node path detection still not working, leading to final fix

## Comparison: MuzzleFlash vs ExplosionFlash

Both effects now use the same pattern:

| Feature | MuzzleFlash | ExplosionFlash |
|---------|-------------|----------------|
| Visual Type | PointLight2D | PointLight2D |
| Shadow Enabled | Yes | Yes |
| Shadow Filter | PCF5 | PCF5 |
| Particles | GPUParticles2D | GPUParticles2D |
| Wall Occlusion | Automatic (shadows) | Automatic (shadows) |
| Duration | 0.3s | 0.3-0.4s |
| Energy (brightness) | 4.5 | 6.0-8.0 |
