# C# to GDScript Set() Interop Test (Issue #781)

## Problem Statement

MakarovPM.cs uses Node.Set() to set properties on GDScript bullets:

```csharp
bulletNode.Set("Direction", direction);  // PascalCase
bulletNode.Set("direction", direction);  // snake_case
```

The GDScript bullet.gd has:
```gdscript
@export var direction: Vector2 = Vector2.RIGHT
```

## Key Question

Does `Node.Set("direction", value)` from C# work correctly with `@export var direction` in GDScript?

## Godot 4 Documentation Says

According to Godot 4 docs, when calling methods like Set(), Call(), etc. from C#:
- Use the **original snake_case names** as they appear in the GDScript/Godot API
- Godot automatically converts PascalCase to snake_case for native API methods
- BUT for GDScript custom properties, you must use the exact property name

## Hypothesis

The `@export var direction` in GDScript should be accessible via `Set("direction", ...)` from C#.
However, in Godot 4, exported properties in GDScript might have different property name resolution.

## Test Cases to Verify

1. Does `Set("direction", Vector2(1, 0))` work?
2. Does `Set("Direction", Vector2(1, 0))` work?
3. Is there a timing issue (setting before AddChild vs after)?
4. Does the Vector2 type marshal correctly between C# and GDScript?

## Observations from Log

The user's log shows NO `[Bullet]` debug messages at all, which means:
1. Either the exported build is outdated (doesn't have debug logging)
2. OR `_ready()` is not being called (unlikely if we see red rectangles)
3. OR FileLogger and print() both fail in exported builds (very unlikely)

## Most Likely Root Cause

Given that:
- Red rectangles appear (bullets are spawning visually)
- Bullets don't move (direction stays at default Vector2.RIGHT or 0,0)
- No debug logs appear

The most likely issue is that the user's build is from **before** the @export fix was committed.

## Timeline Analysis

- 17:42 UTC: AI session committed @export fix
- 18:11 UTC: User reported issue with log timestamped 21:10 local time
- The user likely ran an OLD exported build

## Recommendation

Ask user to:
1. Pull latest changes from the branch
2. Rebuild the Godot export
3. Test again and share new log
