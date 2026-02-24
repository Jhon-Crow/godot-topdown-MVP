# Issue #912 Case Study: Fix Force Field (Силовое поле)

## Issue Description

Fix two problems with the force field item introduced/merged in PR #907:

1. **Visual fix**: The force field visual looks like a large, dark circular vignette rather than a translucent bubble around the player. The user attached a screenshot showing the dark appearance.

2. **Functionality fix**: The force field does NOT trap bullets or scatter them when deactivated. Despite PR #907 implementing bullet trapping logic, the field always reports "Released 0 trapped projectiles" in the game log.

Reference issue for requirements: [#906](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/906)

## Data Collected

- **Screenshot** (`force_field_visual_screenshot.png`): Shows the dark force field visual bug.
- **Game log** (`game_log_20260225_011732.txt`): Contains logs proving bullets enter the force field area but are never trapped.

## Root Cause Analysis

### Bug 1: Bullets Not Being Trapped

#### Evidence from game log

```
[ForceFieldEffect] Activated! Charge: 8.0s/8.0s
[ForceFieldEffect] Area entered: Bullet (script: res://Scripts/Projectiles/Bullet.cs)
[ForceFieldEffect] Area entered: Bullet (script: res://Scripts/Projectiles/Bullet.cs)
...  (many bullets entered)
[ForceFieldEffect] Released 0 trapped projectiles   ← NEVER traps any!
[ForceFieldEffect] Deactivated. Charge remaining: 5.4s
```

Bullets enter the force field area (the `area_entered` signal fires on the force field side), but they are NEVER added to `_trapped_bullets`.

#### Root Cause

**The bullets are in C# (`Scripts/Projectiles/Bullet.cs`) while the force field logic is in GDScript (`scripts/effects/force_field_effect.gd`).**

When a C# `Bullet` Area2D overlaps with the force field `Area2D`, **two signals fire simultaneously**:
1. `ForceFieldArea.area_entered(bullet)` → fires `_on_projectile_entered(bullet)` in force field GDScript
2. `Bullet.AreaEntered(forceFieldArea)` → fires `OnAreaEntered(forceFieldArea)` in C# bullet

The GDScript `_trap_bullet()` correctly:
- Checks `bullet.has("direction")` and `bullet.has("speed")` ✓
- Calls `bullet.set_physics_process(false)` ✓
- Appends to `_trapped_bullets` ✓

However, **simultaneously**, the C# `Bullet.OnAreaEntered()` runs and **unconditionally calls `QueueFree()`**:

```csharp
private void OnAreaEntered(Area2D area)
{
    // ... checks for IDamageable, take_damage, on_hit ...
    EmitSignal(SignalName.Hit, area);
    QueueFree();  // ← ALWAYS called! No force field check!
}
```

The force field `Area2D` doesn't implement `IDamageable`, `take_damage`, `on_hit`, or `OnHit`, so `hitEnemy` stays false. But `QueueFree()` is called unconditionally at the end regardless.

**The bullet frees itself immediately upon entering the force field area**, before the force field's trap logic can actually hold it in place.

#### Comparison with GDScript bullet

The GDScript `bullet.gd` has a correct check:

```gdscript
func _on_area_entered(area: Area2D) -> void:
    # Only destroy bullet if the area has on_hit method
    if area.has_method("on_hit"):
        # Force field protection check
        if parent and parent.has_method("is_force_field_active"):
            if parent.is_force_field_active():
                return  # Bullet blocked, don't destroy
        # ... deal damage ...
        _destroy()
    # If area has no on_hit → bullet passes through harmlessly
```

The GDScript bullet **only destroys itself if the area has `on_hit`**. Since the force field area doesn't have `on_hit`, the GDScript bullet wouldn't self-destruct.

The **C# bullet always calls `QueueFree()` regardless**, which is the bug.

### Bug 2: Force Field Visual Too Dark

The shader creates a dark interior (`fresnel = pow(r, 2.5)` gives dark center-fill) with a bright rim. This creates a "dark vignette with glowing edge" rather than a transparent bubble.

The shader uses:
- `inner_glow = fresnel * 0.4 * pulse` → moderate interior opacity
- `combined = rim * glow_intensity * pulse + inner_glow` → glow_intensity=2.0 makes rim very bright

Result: The interior appears as a semi-opaque blue filled circle rather than mostly transparent, making the visual look like a large dark overlay rather than a translucent bubble.

## Timeline of Events

1. Issue #676: Force field initially implemented with bullet reflection
2. Issue #906: User requests bullet trapping + bubble visual
3. PR #907: AI implements trapping logic in GDScript `force_field_effect.gd` - tested against GDScript bullets
4. PR #907 merged by accident
5. Issue #912: User notices:
   - The force field doesn't trap bullets (because game uses C# `Bullet.cs`)
   - The visual doesn't look right (dark interior issue)

## Proposed Solution

### Fix 1: C# Bullet.cs - Force Field Detection

Add a check in `OnAreaEntered` to detect the force field area and skip `QueueFree()`:

```csharp
private void OnAreaEntered(Area2D area)
{
    // Check if this is the force field — it will handle the bullet itself
    // The force field's GDScript traps and freezes bullets directly
    if (IsForceFieldArea(area))
    {
        return;  // Don't destroy — the force field handles this bullet
    }

    // ... rest of logic ...
    QueueFree();
}

private bool IsForceFieldArea(Area2D area)
{
    // Detect by parent having is_force_field_active method
    var parent = area.GetParent();
    if (parent != null && parent.HasMethod("is_force_field_active"))
        return true;
    // Also check by area name
    if (area.Name.ToString().Contains("ForceField", StringComparison.OrdinalIgnoreCase))
        return true;
    return false;
}
```

### Fix 2: Force Field Shader - Bubble Appearance

Reduce the interior opacity to make the center mostly transparent:

```glsl
// Reduce inner glow to near-zero for transparent center
float inner_glow = fresnel * 0.08 * pulse;  // Was 0.4, now 0.08

// Also soften the glow intensity
float combined = rim * 1.2 * pulse + inner_glow;  // Was glow_intensity=2.0
```

This makes the center mostly transparent while keeping the bright rim, matching a soap bubble appearance.

## Files to Modify

1. `Scripts/Projectiles/Bullet.cs` - Add force field detection to `OnAreaEntered`
2. `scripts/shaders/force_field.gdshader` - Reduce interior opacity
