# FPS Drop Investigation - Phase 3 (2026-02-24)

## Issue Summary
User reported FPS still drops significantly after F-1 grenade or shotgun with breaker bullets explosions, even after implementing PointLight2D pooling in Phase 2.

## Root Cause Analysis

### Game Log Analysis
Analyzed `game_log_20260215_121605.txt` from user's feedback comment.

**Key Finding:**
```
[12:16:19] [INFO] [GrenadeTimer] Spawned shadow-enabled flashbang effect at (1029.8049, 994.07227) (radius: 700)
```

The log reveals that **shadow_enabled is still true** for grenade explosion effects!

### Sources of Shadow-Enabled PointLight2D

1. **FlashbangEffect.tscn** (`scenes/effects/FlashbangEffect.tscn`):
   ```
   shadow_enabled = true
   shadow_color = Color(0, 0, 0, 0.9)
   shadow_filter = 1
   shadow_filter_smooth = 6.0
   ```

2. **GrenadeTimer.cs** (`Scripts/Projectiles/GrenadeTimer.cs`):
   - `SpawnFlashbangEffectScene()` loads FlashbangEffect.tscn (which has shadow_enabled=true)
   - `CreateFallbackExplosionFlash()` explicitly sets `light.ShadowEnabled = true`

### Why Shadows Cause FPS Drops

Per [Godot documentation](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html):
> "Enabling shadows has a significant performance cost"

Shadow rendering creates:
- 4 draw lists per light
- 4 × lights × occluders additional draw calls

For the F-1 grenade (radius 700px) in a scene with many wall occluders, this becomes extremely expensive.

### Why Previous Fixes Didn't Fully Work

The Phase 1 and Phase 2 fixes addressed:
- ✅ `ImpactEffectsManager.spawn_explosion_effect()` - shadows disabled
- ✅ PointLight2D object pooling implemented
- ❌ `FlashbangEffect.tscn` - still had shadow_enabled=true
- ❌ `GrenadeTimer.cs` C# fallback - still set ShadowEnabled=true

The F-1 defensive grenade explosion was using the FlashbangEffect.tscn via C# GrenadeTimer, bypassing the GDScript ImpactEffectsManager entirely.

## Fix Applied (Phase 3)

### 1. FlashbangEffect.tscn
Changed from:
```
shadow_enabled = true
shadow_color = Color(0, 0, 0, 0.9)
shadow_filter = 1
shadow_filter_smooth = 6.0
```

To:
```
shadow_enabled = false
```

### 2. GrenadeTimer.cs
Changed `CreateFallbackExplosionFlash()` from:
```csharp
light.ShadowEnabled = true;
light.ShadowColor = new Color(0, 0, 0, 0.9f);
light.ShadowFilter = PointLight2D.ShadowFilterEnum.Pcf5;
light.ShadowFilterSmooth = 6.0f;
```

To:
```csharp
light.ShadowEnabled = false;
```

Updated documentation comments to reflect Issue #724 fix.

## Expected Performance Improvement

| Scenario | Before (Phase 2) | After (Phase 3) |
|----------|------------------|-----------------|
| F-1 grenade explosion | Shadow-enabled light (expensive) | Non-shadow light (cheap) |
| Flashbang explosion | Shadow-enabled light (expensive) | Non-shadow light (cheap) |
| Draw calls per explosion | ~4 + 4×occluders | ~1 |

## Visual Trade-off

By disabling shadows on explosion effects:
- **Lost:** Light doesn't respect wall geometry (visible through walls briefly)
- **Gained:** No FPS drops on explosion

This is an acceptable trade-off because:
1. Explosion flashes are very brief (0.3-0.4 seconds)
2. Players rarely notice shadow accuracy during fast-paced action
3. Gameplay smoothness (60 FPS) is more important than visual accuracy

## Files Changed
- `scenes/effects/FlashbangEffect.tscn` - Disabled shadow_enabled
- `Scripts/Projectiles/GrenadeTimer.cs` - Disabled ShadowEnabled in fallback method
- `docs/case-studies/issue-724/fps_drop_investigation_2026-02-24.md` - This analysis

## Testing Recommendations
1. Test F-1 (defensive) grenade explosion - verify no FPS drop
2. Test frag grenade explosion - verify no FPS drop
3. Test shotgun with breaker bullets - verify no FPS drop
4. Verify explosion flash still looks acceptable (brief light effect visible)
