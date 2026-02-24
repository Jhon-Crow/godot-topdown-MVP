# Case Study: Issue #908 — Buckshot Disappears After Ricochet

## Issue Summary

**Title:** `fix дробь исчезает после рикошета` ("fix: buckshot disappears after ricochet")
**Repo:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/908
**State:** OPEN
**Author:** Jhon-Crow

The issue reports that shotgun pellets (дробь = buckshot) disappear after ricocheting off walls instead of continuing to travel.

---

## Codebase Investigation

### Files Involved

- `Scripts/Projectiles/ShotgunPellet.cs` — The shotgun pellet projectile class
- `Scripts/Weapons/Shotgun.cs` — The shotgun weapon class that fires pellets

### How the Bug Was Discovered

The `ShotgunPellet.cs` has a **post-ricochet lifetime system** based on distance:

```csharp
// From _PhysicsProcess:
if (_hasRicocheted)
{
    _distanceSinceRicochet += movement.Length();
    if (_distanceSinceRicochet >= _maxPostRicochetDistance)
    {
        QueueFree();
        return;
    }
}
```

After a ricochet, `_maxPostRicochetDistance` is calculated in `PerformRicochet()`:

```csharp
float angleFactor = 1.0f - (impactAngleDeg / MaxRicochetAngle);
angleFactor = Mathf.Clamp(angleFactor, 0.1f, 1.0f);
_maxPostRicochetDistance = _viewportDiagonal * angleFactor * 0.5f;
// "Shorter post-ricochet distance for pellets"
```

### Root Cause: Too Short Post-Ricochet Distance

The `MaxRicochetAngle` for pellets is **35 degrees** (much lower than bullets' 90 degrees). This creates a severe problem in the formula.

**Numerical Analysis:**

Given:
- `MaxRicochetAngle = 35°`
- `VelocityRetention = 0.75`
- After-ricochet speed = `2500 * 0.75 = 1875 px/s`
- Viewport diagonal = `~2203 px` (1920×1080)
- At 60 FPS = `31.2 px/frame`

| Impact Angle | angleFactor | MaxPostDist | Survive Time |
|:---:|:---:|:---:|:---:|
| 0° | 1.00 | 1101.5 px | 587 ms |
| 5° | 0.86 | 944.1 px | 504 ms |
| 10° | 0.71 | 786.8 px | 420 ms |
| 15° | 0.57 | 629.4 px | 336 ms |
| 20° | 0.43 | 472.1 px | 252 ms |
| 25° | 0.29 | 314.7 px | 168 ms |
| 30° | 0.14 | 157.4 px | **84 ms** |
| 35° | 0.10 (clamped) | 110.2 px | **59 ms** |

The `* 0.5f` multiplier (commented "Shorter post-ricochet distance for pellets") combined with the 35° max ricochet angle creates **extremely short post-ricochet lifetimes**:

- At 30–35° impact angles (the steeper end of what pellets allow), the pellet only survives **59–84 ms** after ricocheting — effectively **3–5 physics frames**. To the player, this looks like an **instant disappearance**.
- Even at 20°, the pellet survives only 252 ms — barely noticeable.

For comparison, the standard `Bullet.cs` uses:
- `MaxRicochetAngle = 90°`
- No `* 0.5f` multiplier
- At 35°: `angleFactor = 1 - 35/90 = 0.61`, `maxDist = 2203 * 0.61 = 1344 px`, surviving ~716 ms

### Contributing Factors

1. **The `* 0.5f` factor** — Explicitly added to "Shorter post-ricochet distance for pellets", but it halves what would otherwise be reasonable travel distances.

2. **Small `MaxRicochetAngle` (35° instead of 90°)** — The `angleFactor` formula `1.0 - (angle/MaxRicochetAngle)` approaches 0 much faster when the max is 35° instead of 90°. A 30° impact (which is allowed) gives only 14% of the viewport diagonal for post-ricochet travel.

3. **The clamp to 0.1 minimum** — Only marginally rescues the worst case, giving 110 px (59 ms) vs 0 px.

### Why The Formula Is Wrong for Pellets

The original formula was designed for bullets with a 90° max ricochet angle. The concept is: the more grazing the ricochet (smaller angle), the longer the bullet travels. At 90° (direct hit), the bullet barely continues. At 0° (grazing), it travels the full viewport diagonal.

When applied to pellets with 35° max:
- The valid range is 0–35°
- Any angle in the 20–35° range now produces a very short post-ricochet distance
- Adding `* 0.5f` makes this even worse

---

## Fix

Remove the `* 0.5f` factor, and normalize the `angleFactor` against `90.0f` (not `MaxRicochetAngle`), since the intended physical meaning is "steeper angles = less travel after ricochet" — and the reference scale should remain 90° for physical correctness.

### Before (buggy):
```csharp
float angleFactor = 1.0f - (impactAngleDeg / MaxRicochetAngle);
angleFactor = Mathf.Clamp(angleFactor, 0.1f, 1.0f);
_maxPostRicochetDistance = _viewportDiagonal * angleFactor * 0.5f;
```

### After (fixed):
```csharp
float angleFactor = 1.0f - (impactAngleDeg / 90.0f);
angleFactor = Mathf.Clamp(angleFactor, 0.1f, 1.0f);
_maxPostRicochetDistance = _viewportDiagonal * angleFactor;
```

**Effect of fix** (at 35° impact angle, the worst case for pellets):
- Before: `angleFactor = 0.1` (clamped), `maxDist = 110 px`, survive time = 59 ms
- After: `angleFactor = 1 - 35/90 = 0.61`, `maxDist = 1344 px`, survive time = 716 ms

This makes pellet post-ricochet behavior consistent with standard bullet behavior.

---

## Related Code

- `Bullet.cs` line 1035: `float angleFactor = 1.0f - (impactAngleDeg / 90.0f);` — uses 90.0f (correct)
- `bullet.gd` line 688: `var angle_factor := 1.0 - (impact_angle_deg / 90.0)` — uses 90.0 (correct)
- `ShotgunPellet.cs` line 909: `float angleFactor = 1.0f - (impactAngleDeg / MaxRicochetAngle);` — uses MaxRicochetAngle=35 (BUG)

---

## Files Changed

- `Scripts/Projectiles/ShotgunPellet.cs` — Fix `PerformRicochet()` to normalize angle against 90° and remove the `* 0.5f` factor
