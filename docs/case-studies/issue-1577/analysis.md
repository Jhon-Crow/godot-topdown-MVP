# Case Study: Issue #1577 — Water Blocks Bullets (fix вода)

## Issue Summary

> **вода сейчас блокирует пули (не должна)**
> **"Water now blocks bullets (it shouldn't)"**

Reporter: Jhon-Crow
Reference: [PR #1574](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1574) (introduced the regression)
Log file: `game_log_20260326_143314.txt`

---

## Game Log Evidence

From `game_log_20260326_143314.txt`, the session visits BeachLevel multiple times:

```
[14:33:53] [INFO] [BeachLevel] Water node found OK — visual=true shader=true collision=true pos=(1264, 242)
[14:34:23] [INFO] [BeachLevel] Water node found OK — visual=true shader=true collision=true pos=(1264, 242)
[14:34:47] [INFO] [BeachLevel] Water node found OK — visual=true shader=true collision=true pos=(1264, 242)
[14:36:20] [INFO] [BeachLevel] Water node found OK — visual=true shader=true collision=true pos=(1264, 242)
```

The `collision=true` confirms the WaterBody has an active collision shape. No bullet-specific log entries appear because `DebugHits = false` in the exported build, so the exact collision event is not logged. However, the gameplay behavior is observable: bullets fired toward enemies near the water stop visually at the water boundary.

---

## Files Involved

| File | Role |
|------|------|
| `scripts/objects/water_body.gd` | WaterBody Area2D controller — collision setup in `_ready()` |
| `scenes/objects/WaterBody.tscn` | Pre-baked scene — collision_layer/mask NOT set (defaults to layer=1) |
| `scenes/levels/BeachLevel.tscn` | Water node at (1264, 242), water_height=420 after PR #1574 |
| `Scripts/Projectiles/Bullet.cs` | C# bullet — `OnAreaEntered` has unconditional `QueueFree()` |
| `scripts/projectiles/bullet.gd` | GDScript bullet — `_on_area_entered` only destroys on `on_hit` method |

---

## Collision Layer Setup (project.godot)

| Layer | Bit | Value | Name | Used By |
|-------|-----|-------|------|---------|
| 1 | 0 | 1 | player | Player CharacterBody2D |
| 2 | 1 | 2 | enemies | Enemy CharacterBody2D |
| 3 | 2 | 4 | obstacles | Walls, rocks, StaticBody2D |
| 4 | 3 | 8 | pickups | Pickup items |
| 5 | 4 | 16 | projectiles | Bullets, shrapnel |
| 6 | 5 | 32 | targets | Enemy HitArea2D |
| 7 | 6 | 64 | decorative | Casings, ragdolls |

**Bullet configuration:**
- `collision_layer = 16` (layer 5 = projectiles)
- `collision_mask = 39` = 0b00100111 = layers 1 (player) + 2 (enemies) + 3 (obstacles) + 6 (targets)

**WaterBody configuration (set in `_ready()`):**
- `collision_layer = 0` (NOT on any layer)
- `collision_mask = 99` = 0b01100011 = layers 1 (player) + 2 (enemies) + 6 (targets) + 7 (decorative)

**Layer 5 (projectiles/bullets = 16) is NOT in water's collision_mask.** Bullets on layer 5 are explicitly excluded. This exclusion was added in [commit c63c171e](https://github.com/Jhon-Crow/godot-topdown-MVP/commit/c63c171e) as part of Issue #1495.

---

## Root Cause Analysis

### Issue 1: Race Condition — WaterBody.tscn Missing `collision_layer = 0`

**Root cause:** `WaterBody.tscn` does NOT declare `collision_layer` in the `.tscn` file. Godot 4's default `collision_layer` for all new Area2D nodes is **1** (layer 1 = player).

This means during scene initialization, **before `_ready()` runs** to set `collision_layer = 0`, the WaterBody has `collision_layer = 1`. The bullet's `collision_mask = 39` includes layer 1.

**Consequence:** Any bullet that enters the water Area2D during the transition frame before `_ready()` completes will trigger the C# Bullet's `OnAreaEntered` signal. This is rare in normal gameplay (bullets spawn after scene `_ready()` chain completes) but becomes a latent bug.

### Issue 2 (Root Cause): C# Bullet Unconditional `QueueFree()` in `OnAreaEntered`

**Root cause:** In `Scripts/Projectiles/Bullet.cs`, the `OnAreaEntered` method (line 938) calls `QueueFree()` **unconditionally** when no hit methods match on the entered area:

```csharp
private void OnAreaEntered(Area2D area)
{
    // ... multiple early return checks for valid targets ...

    bool hitEnemy = false;

    // Check for hit methods
    if (area.HasMethod("on_hit_with_bullet_info_and_damage"))     { hitEnemy = true; ... }
    else if (area is IDamageable)                                   { hitEnemy = true; ... }
    else if (parent.HasMethod("take_damage"))                       { hitEnemy = true; ... }
    else if (area.HasMethod("on_hit"))                              { hitEnemy = true; ... }
    else if (area.HasMethod("OnHit"))                               { hitEnemy = true; ... }
    // else: hitEnemy remains false

    if (hitEnemy && PenetratesEnemies) return;  // Only skips QueueFree if hit AND penetrating

    QueueFree();  // ← ALWAYS called if no early return, even when hitEnemy == false!
}
```

**The GDScript bullet does NOT have this bug:**
```gdscript
func _on_area_entered(area: Area2D) -> void:
    if area.has_method("on_hit"):
        # ... deal damage ...
        _destroy()
    # No else: bullet silently passes through if on_hit doesn't exist
```

**Impact:** Any Area2D that the C# bullet enters and that has none of the recognized hit methods will cause the bullet to be destroyed. This includes:
- WaterBody (no hit methods)
- Any other detection-only Area2D (e.g., ThreatSpheres already handled)
- Environmental Area2D zones

### Issue 3: WaterBody Collision Shape Extends into Playable Area

After PR #1574, `water_height` was increased from 356 to 420. This extends the water's collision shape downward into the playable sand area:

| Parameter | Before PR #1574 | After PR #1574 |
|-----------|----------------|----------------|
| `water_height` | 356 | 420 |
| Water top edge (y) | 64 | 32 |
| Water bottom edge (y) | 420 | 452 |
| Sand playable start (y) | 400 | 400 |
| Overlap into sand (px) | 20 | 52 |

The water's bottom edge now extends 52px into the sand (vs 20px before), meaning enemies standing at y=420–452 are now detected by the water's collision shape and trigger `body_entered` signals (splash effects, bloody feet suppression). This is **intentional behavior for shore wash visual effects**, but it means the water's Area2D collision footprint is larger.

While this doesn't directly stop bullets (collision layers still don't overlap), the **larger visual water area** extends further into the playable zone, making it more likely that the collision bug (Issue 2) produces visible symptoms.

---

## Timeline / Sequence of Events

1. **Issue #1445** — Water body introduced for BeachLevel
2. **Issue #1495** — Fix: removed bullet layer (5) from water's collision_mask, preventing bullets from triggering water interaction. GDScript bullet already safe (only destroys on `on_hit`).
3. **Issue #1550** — Wave animation, obstacle interruption, camera limits
4. **Issue #1573 / PR #1574** — Water height increased 356→420 for shore wash effect. Larger collision shape, more overlap with sand area. C# Bullet's latent `QueueFree()` bug becomes more visible.
5. **Issue #1577** (this issue) — User reports water blocking bullets on BeachLevel

---

## Solution Design

### Fix 1: WaterBody.tscn — Set `collision_layer = 0` in Scene File

**Change:** Add `collision_layer = 0` to the `WaterBody` node in `WaterBody.tscn`.

**Rationale:** Prevents the race condition where the default `collision_layer = 1` is active before `_ready()` runs. Defensive programming — the scene file should declare the intended state.

### Fix 2: C# Bullet — Add Early Return When No Hit Methods Match

**Change:** In `Scripts/Projectiles/Bullet.cs`, `OnAreaEntered` should return early (without `QueueFree()`) when no hit methods are found on the area:

```csharp
// After checking all hit methods and hitEnemy remains false:
if (!hitEnemy)
{
    return; // Non-target area — bullet passes through silently
}
```

This makes the C# bullet behavior match the GDScript bullet: bullets only stop when hitting actual targets.

**Important:** The force field, shield, and other special areas already have early returns before the hit method checks. This fix only affects the general case of "unrecognized Area2D" — which should be transparent to bullets.

---

## Online References

- **Godot 4 Area2D collision rules**: https://docs.godotengine.org/en/stable/classes/class_area2d.html
  "An Area2D detects another Area2D when their collision layers/masks overlap."
- **Godot 4 default collision_layer**: Godot assigns `collision_layer = 1` by default to all new physics nodes until explicitly overridden.
- **2D physics layer interaction**: In Godot 4, `area_entered` fires on Area A when Area B enters, if: `B.collision_layer & A.collision_mask != 0` OR `A.collision_layer & B.collision_mask != 0`.
- **Shore wash technique**: Common in 2D water shaders — extending the water ColorRect past the shoreline and using alpha fade gives impression of wave wash-over (used in Stardew Valley, Terraria, Godot 2D demos).

---

## Implementation Notes

- See `Scripts/Projectiles/Bullet.cs` — `OnAreaEntered` fix (add early return)
- See `scenes/objects/WaterBody.tscn` — add `collision_layer = 0` to node declaration
- See `tests/unit/test_water_body.gd` — update stale tests from water_height=356
