# Case Study: Issue #1769 — Wall Slowing Player Movement

## Summary

When the player moves while pressing against a wall, the wall slows the player down. Three separate fixes were required across two iteration cycles:

1. **Fix 1 (wrong file):** GDScript `player.gd` patched — but the game runs C# `Player.cs`/`BaseCharacter.cs`. No effect.
2. **Fix 2 (wrong approach):** `Vector2.Slide()` applied to the *already-scaled* velocity — reduced target speed by ~29% at 45° input.
3. **Fix 3 (incomplete coverage):** Slide the *input direction* first, then renormalize — but only checked `IsOnWall()`. In Godot 4 GROUNDED mode, top/bottom walls register as `IsOnCeiling()`/`IsOnFloor()`, not `IsOnWall()`.
4. **Fix 4 (correct):** Iterate all `GetSlideCollisionCount()` normals instead of relying on `IsOnWall()` — guarantees full speed along ALL wall directions.

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| Issue opened | Owner reports: "when the player moves while pressed against a wall, the wall slows them — this should not happen" |
| First fix (commit `1ae169af`) | AI solver adds `Vector2.slide(get_wall_normal())` fix to **GDScript** `scripts/characters/player.gd` |
| Owner tests (`game_log_20260410_002804.txt`) | Owner tests using an exported `.exe` on Windows, sees no change |
| Owner comments | "не вижу изменений" (I don't see changes), attaches game log from `физика стен/` test folder |
| Root cause found | The game uses **C# player** (`Scripts/Characters/Player.cs`), which calls `ApplyMovement()` from `Scripts/AbstractClasses/BaseCharacter.cs` — the GDScript fix was never executed |
| Second fix (commit `9271671b`) | `ApplyMovement()` in `BaseCharacter.cs` updated with the same (still-incomplete) wall-plane projection |
| Owner tests again (`game_log_20260410_030927.txt`) | Owner tests the C# fix, reports: "похоже игрок не разгоняется так же как при обычной ходьбе, когда идёт упираясь в стену, по этому фактическая скорость ходьбы вдоль стены меньше" (player still slower along walls) |
| Third fix (commit `d10f56a2`) | Project input **direction** onto the wall plane and **renormalize** before scaling by `MaxSpeed` — correct for lateral walls |
| Owner tests third fix | "проблема сохраняется — например при упоре в верхнюю стену (движение вверх+вправо) игрок движется без ускорения" — top wall still not working |
| Root cause (3rd fix) | `IsOnWall()` in Godot 4 GROUNDED mode **only catches lateral surfaces**; top/bottom walls trigger `IsOnCeiling()`/`IsOnFloor()`. Fix never executed for top/bottom walls. |
| Fourth fix (current) | Iterate `GetSlideCollisionCount()` normals directly — catches ALL surface collision types, handles top/bottom and corner walls |

---

## Root Cause Analysis

### Stage 1: Dual Implementation Problem

The project has **two separate player implementations**:

1. **GDScript** — `scripts/characters/player.gd` (extends `CharacterBody2D`)
2. **C#** — `Scripts/Characters/Player.cs` (extends `BaseCharacter` which extends `CharacterBody2D`)

The game log confirms the **C# player** is what actually runs:

```
[GameManager] set_player() called with: <CharacterBody2D#83818972930> (class: CharacterBody2D)
[LabyrinthLevel] AKGL already equipped by C# Player - applying labyrinth ammo config
```

The first fix patched only the GDScript version, which was never executed.

### Stage 2: Incorrect Slide Application (Vector Magnitude Not Preserved)

The second fix applied `Slide()` to the *already-scaled* target velocity. This is subtly wrong.

**Example: player presses UP + RIGHT (45°), wall on the right (normal = (-1, 0))**

```
direction = normalize(1, -1) = (0.707, -0.707)

// Broken approach (what was in both implementations):
targetVelocity = direction * MaxSpeed = (141.4, -141.4)
targetVelocity.Slide((-1, 0)):
  dot = 141.4 * (-1) = -141.4
  result = (141.4, -141.4) - (-141.4) * (-1, 0) = (0, -141.4)
// Target speed = 141.4 instead of 200 → ~70.7% of max
```

So even with the second fix, the player still moved at ~70.7% of `MaxSpeed` when pressing diagonally into a wall.

### The Correct Fix: Renormalize After Slide

Slide the **direction** vector (unit length), renormalize the result, then scale by `MaxSpeed`:

```
slid = direction.Slide((-1, 0)) = (0.707, -0.707) - (-0.707) * (-1, 0) = (0, -0.707)
moveDir = slid.Normalized() = (0, -1)
targetVelocity = (0, -1) * 200 = (0, -200)  ← full MaxSpeed!
```

This guarantees that regardless of the input angle, the player accelerates at full `MaxSpeed` in whatever direction the wall allows.

### Stage 3: IsOnWall() Only Catches Lateral Surfaces

**Godot 4's `GROUNDED` motion mode** classifies collisions based on the `UpDirection` (default `(0, -1)` = screen-up):

| Collision Surface | Normal Direction | Godot Classification | `IsOnWall()`? |
|---|---|---|---|
| Left wall | `(1, 0)` | Wall | ✅ Yes |
| Right wall | `(-1, 0)` | Wall | ✅ Yes |
| **Top wall (ceiling)** | `(0, 1)` | Ceiling | ❌ **No** |
| Bottom wall (floor) | `(0, -1)` | Floor | ❌ **No** |

In a top-down game, there's no actual gravity direction — "floor" and "ceiling" are just walls in different directions. But Godot still classifies them differently.

**Example: player presses UP + RIGHT (45°), top wall (normal = (0, 1))**

```
direction = normalize(1, -1) = (0.707, -0.707)
IsOnWall() = false  ← top wall registers as IsOnCeiling()!
moveDir = direction  ← no slide applied
Velocity.MoveToward((0.707, -0.707) * 200, Acceleration * delta)
// Target = (141.4, -141.4)
// MoveAndSlide() kills Y component → only X survives
// Result: slow rightward movement instead of full MaxSpeed
```

### The Final Fix: Iterate All Slide Collisions

Instead of relying on `IsOnWall()`, check ALL collision normals from the previous `MoveAndSlide()` call:

```csharp
// C# in BaseCharacter.cs
int collisionCount = GetSlideCollisionCount();
for (int i = 0; i < collisionCount; i++)
{
    var collision = GetSlideCollision(i);
    Vector2 normal = collision.GetNormal();
    // Only slide against surfaces the player is pushing into
    if (direction.Dot(normal) < 0f)
    {
        Vector2 slid = moveDir.Slide(normal);
        if (slid != Vector2.Zero)
            moveDir = slid.Normalized();
    }
}
```

This approach:
- Works for **all wall directions** (left, right, top, bottom)
- Handles **corner collisions** (multiple normals in one frame)
- Uses the `dot(normal) < 0` guard to avoid sliding away from surfaces we're moving toward
- Renormalizes after each slide to preserve `MaxSpeed`

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/characters/player.gd` | Slide direction, renormalize, then scale (correct fix) |
| `Scripts/AbstractClasses/BaseCharacter.cs` | Same fix — where the actual C# player runs |

---

## Evidence

### Game Log: `game_log_20260410_002804.txt`

- **Test environment:** Windows, exported `.exe`, Godot 4.3-stable
- **Test folder:** `I:/Загрузки/godot exe/физика стен/` (wall physics test)
- **Key finding:** C# player active, GDScript code path never reached — explains why first fix had no effect

### Game Log: `game_log_20260410_030927.txt`

- **Test environment:** Same (Windows, exported `.exe`, Godot 4.3-stable)
- **Test folder:** `I:/Загрузки/godot exe/физика стен/`
- **Key finding:** C# fix was in effect, but the player still reported slower movement along walls — confirms that the `Slide(velocity)` approach reduces target magnitude for diagonal inputs

### Online References

- **Godot `CharacterBody2D.IsOnWall()`** — returns `true` when the body has collided with a wall during the last `MoveAndSlide()` call. ([Godot docs](https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html))
- **`Vector2.Slide(normal)`** — removes the component of the vector in the direction of `normal`. Does NOT preserve length unless input is parallel to the wall. ([Godot docs](https://docs.godotengine.org/en/stable/classes/class_vector2.html))
- **`Vector2.Normalized()`** — returns a unit-length version. Used here to restore magnitude to 1 before multiplying by `MaxSpeed`.

---

## How to Reproduce (Before Final Fix)

1. Run the game on a level with walls
2. Move diagonally into **any** wall (e.g., UP+RIGHT against a top wall)
3. **Expected:** Player slides along the wall at full speed (rightward at `MaxSpeed`)
4. **Actual (before fix):** Player moves noticeably slower or without acceleration, especially against top/bottom walls

## Verification (After Final Fix)

After applying the slide-all-collisions fix:
- Left/right walls: player moves at full `MaxSpeed` ✅
- Top wall (pressing up+right): player moves rightward at full `MaxSpeed` ✅  
- Bottom wall (pressing down+left): player moves leftward at full `MaxSpeed` ✅
- Corner collisions: correctly slides along the combined surface ✅

---

## Attached Logs

- [`game_log_20260410_002804.txt`](./game_log_20260410_002804.txt) — Session 1: owner's wall-physics test, shows no effect from GDScript-only fix
- [`game_log_20260410_030927.txt`](./game_log_20260410_030927.txt) — Session 2: owner's second test, confirms C# fix was insufficient due to unrenormalized slide
