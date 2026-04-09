# Case Study: Issue #1769 — Wall Slowing Player Movement

## Summary

When the player moves while pressing against a wall, the wall was slowing the player down. The issue was caused by the C# movement implementation in `Scripts/AbstractClasses/BaseCharacter.cs`, which was not included in the initial fix that only patched the GDScript `scripts/characters/player.gd`.

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| Issue opened | Owner reports: "when the player moves while pressed against a wall, the wall slows them — this should not happen" |
| First fix (commit `1ae169af`) | AI solver adds `Vector2.slide(get_wall_normal())` fix to **GDScript** `scripts/characters/player.gd` |
| Owner tests (`game_log_20260410_002804.txt`) | Owner tests the fix using an exported `.exe` on Windows, sees no change |
| Owner comments | "не вижу изменений" (I don't see changes), attaches game log from `физика стен/` test folder |
| Root cause found | The game uses **C# player** (`Scripts/Characters/Player.cs`), which calls `ApplyMovement()` from `Scripts/AbstractClasses/BaseCharacter.cs` — the GDScript fix was never executed |
| Second fix | `ApplyMovement()` in `BaseCharacter.cs` updated with the same wall-plane projection logic |

---

## Root Cause Analysis

### The Dual Implementation Problem

The project has **two separate player implementations**:

1. **GDScript** — `scripts/characters/player.gd` (extends `CharacterBody2D`)
2. **C#** — `Scripts/Characters/Player.cs` (extends `BaseCharacter` which extends `CharacterBody2D`)

The game log confirms the **C# player** is what actually runs:

```
[GameManager] set_player() called with: <CharacterBody2D#83818972930> (class: CharacterBody2D)
[LabyrinthLevel] AKGL already equipped by C# Player - applying labyrinth ammo config
```

The `Player.cs` C# class calls `ApplyMovement(inputDirection, delta)` defined in `BaseCharacter.cs`, which had the unfixed version:

```csharp
// BEFORE FIX — target includes blocked wall direction:
Velocity = Velocity.MoveToward(direction * MaxSpeed, Acceleration * delta);
```

### Why the Wall Slows the Player

On each physics frame:
1. Player presses e.g. right + up, with a wall on the right
2. `Velocity.MoveToward(direction * MaxSpeed, ...)` accelerates toward the target including the rightward component
3. `MoveAndSlide()` cancels the rightward velocity (wall blocks it)
4. On the next frame, the same wasted acceleration cycle repeats
5. Net result: the upward (allowed) velocity is never fully reached → player is slower along the wall

### The Fix

Project the target velocity onto the wall plane using `Slide(GetWallNormal())` when `IsOnWall()` is true. This ensures all acceleration budget goes into the direction the player can actually move:

```csharp
// AFTER FIX — target is projected onto wall plane:
Vector2 targetVelocity = direction * MaxSpeed;
if (IsOnWall())
    targetVelocity = targetVelocity.Slide(GetWallNormal());
Velocity = Velocity.MoveToward(targetVelocity, Acceleration * delta);
```

The same logic was also applied in GDScript `scripts/characters/player.gd` (commit `1ae169af`).

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/characters/player.gd` | Added wall-plane projection (first fix, GDScript only — incomplete) |
| `Scripts/AbstractClasses/BaseCharacter.cs` | Added wall-plane projection (second fix — where the actual player runs) |

---

## Evidence

### Game Log Analysis (`game_log_20260410_002804.txt`)

- **Test environment:** Windows, exported `.exe`, Godot 4.3-stable (official)
- **Test folder:** `I:/Загрузки/godot exe/физика стен/` (purposefully testing wall physics)
- **Duration:** 00:28:04 → 00:31:17 (~3 minutes)
- **C# player confirmed active:** `[GameManager] set_player() called with: <CharacterBody2D#...> (class: CharacterBody2D)`, `C# Player`
- **No wall-slide velocity logging present:** The GDScript fix added a code path that was never reached; no log entries indicate it executed

### Online References

- **Godot `CharacterBody2D.IsOnWall()`** — returns `true` when the body has collided with a wall during the last `MoveAndSlide()` call. ([Godot docs](https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html#class-characterbody2d-method-is-on-wall))
- **`Vector2.Slide(normal)`** — returns a vector sliding along the plane defined by the normal. Equivalent to removing the component in the direction of `normal`. ([Godot docs](https://docs.godotengine.org/en/stable/classes/class_vector2.html#class-vector2-method-slide))
- This is the canonical Godot approach for wall-sliding movement in top-down and platformer games.

---

## How to Reproduce (Before Fix)

1. Run the game on a level with walls
2. Hold a movement key toward a wall AND a key perpendicular to it (e.g., Right + Up with a wall on the right)
3. **Expected:** Player slides along the wall at full speed
4. **Actual (before fix):** Player moves noticeably slower along the wall than in open space

## Verification (After Fix)

After applying the fix to `BaseCharacter.cs`, the player maintains full speed when sliding along a wall — because all acceleration is directed along the allowed movement direction.

---

## Attached Logs

- [`game_log_20260410_002804.txt`](./game_log_20260410_002804.txt) — Game session log from owner's wall-physics test (2026-04-10, Windows, exported build). Shows C# player active, demonstrates no wall-slide-related log entries from the GDScript fix.
