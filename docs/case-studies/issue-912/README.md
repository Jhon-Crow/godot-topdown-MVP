# Issue #912 Case Study: Fix Force Field (Силовое поле)

## Issue Description

Fix two problems with the force field item introduced/merged in PR #907:

1. **Visual fix**: The force field visual looks like a large, dark circular vignette (then later a large blue-filled circle) rather than a translucent bubble around the player.
2. **Functionality fix**: The force field does NOT trap bullets or scatter them when deactivated. Despite PR #907 implementing bullet trapping logic, the field always reports "Released 0 trapped projectiles".

Reference issue for requirements: [#906](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/906)

## Data Collected

- **Screenshot** (`screenshot_original.png`): Original dark force field visual from Issue #912 description.
- **Screenshot** (`screenshot_after_first_fix.png`): After the first fix session — still a large blue filled circle instead of bubble.
- **Screenshot** (`force_field_visual_screenshot.png`): Additional evidence of the visual bug.
- **Game log** (`game_log_20260225_011732.txt`): Game log from initial issue report.
- **Game logs** (`logs/game_log_20260225_013410.txt`, `logs/game_log_20260225_013424.txt`): Logs from 2nd test showing persistent bullet trapping failure ("Released 0 trapped projectiles" despite many "Area entered: Bullet" events).

## Root Cause Analysis

### Bug 1: Bullets Not Being Trapped

#### Evidence from game logs

```
[ForceFieldEffect] Activated! Charge: 8.0s/8.0s
[ForceFieldEffect] Area entered: Bullet (script: res://Scripts/Projectiles/Bullet.cs)
[ForceFieldEffect] Area entered: Bullet (script: res://Scripts/Projectiles/Bullet.cs)
...  (dozens of bullets detected)
[ForceFieldEffect] Released 0 trapped projectiles   ← NEVER traps any!
[ForceFieldEffect] Deactivated. Charge remaining: 5.4s
```

The game logs (`013424.txt`) showed 40+ "Area entered: Bullet" events across 7 force field activations, but always "Released 0 trapped projectiles".

#### Root Cause

When a C# `Bullet` Area2D overlaps with the force field `Area2D`, **two signals fire simultaneously**:
1. `ForceFieldArea.area_entered(bullet)` → fires `_on_projectile_entered(bullet)` in force field GDScript
2. `Bullet.AreaEntered(forceFieldArea)` → fires `OnAreaEntered(forceFieldArea)` in C# bullet

**Pre-fix:** The old `Bullet.cs` `OnAreaEntered` called `QueueFree()` unconditionally at the end (no force field area check). The force field area doesn't implement `IDamageable`, `take_damage`, `on_hit`, or `OnHit`, so `hitEnemy` = false, but `QueueFree()` is always called. The bullet freed itself immediately.

**Fix applied in previous session:** Added `IsForceFieldArea()` check in `Bullet.cs` (and `ShotgunPellet.cs`) that returns early without `QueueFree()`.

Also identified a secondary bug: the OLD `force_field_effect.gd` used `bullet.has("direction")` — but `Object.has()` doesn't exist in Godot 4 (it's a Dictionary method). Calling it on a Node returns null, and `not null` evaluates to `true`, causing an early return that skipped every bullet. **Fix:** Replace with `"direction" in bullet` (Godot 4 GDScript standard for Node property existence checks).

#### Why "Released 0" persisted in user testing

The user was running a pre-compiled game export (`.exe`). The GDScript changes take effect at runtime (GDScript is interpreted), but **C# is compiled** — the `.dll` inside the `.pck` export file is the OLD version without `IsForceFieldArea()`. The user needed to rebuild the game from source to see C# fixes.

### Bug 2: Force Field Visual — Large Blue Fill (Not a Bubble)

#### Screenshots comparison

- **Before**: Dark vignette filling entire frame + glowing edge
- **After first fix session**: Large BLUE filled circle + glowing edge

Both show the same underlying problem: the Sprite2D texture is dominating the visual, not the shader.

#### Root Cause

`_setup_shield_visual()` created a `GradientTexture2D` with `FILL_RADIAL`:
- Center: `Color(0.3, 0.6, 1.0, 0.0)` (transparent blue)
- Edge: `Color(0.5, 0.8, 1.0, 0.9)` (bright blue)

This creates a filled radial gradient. Even though the shader sets `COLOR = vec4(final_color, final_alpha)` to override it, there were two problems:
1. The OLD shader had `inner_glow = fresnel * 0.4 * pulse` contributing to interior opacity.
2. Even after removing `inner_glow`, the GradientTexture2D base color can bleed through if the export/build doesn't include the shader properly.

The first fix session reduced then removed `inner_glow` from the shader — correct. But the screenshot after the fix still shows a large blue fill, meaning either:
- The shader wasn't loaded in the user's build (old compiled export), OR
- The GradientTexture2D was producing the fill visually

#### Fix

1. Replace `GradientTexture2D` with a plain white `ImageTexture` — gives the shader full, unambiguous control over color/alpha.
2. Add a fallback `_create_ring_texture()` that programmatically creates a donut/ring image (transparent center + transparent outside + blue rim) for when the shader cannot be loaded.

### Bug 3: ShotgunPellet.cs — Direction Not Exported

`ShotgunPellet.cs` had `Direction` and `ShooterId` as non-exported C# properties. In Godot 4, the GDScript `in` operator only works for `[Export]` C# properties (they're registered as snake_case names). Without `[Export]`, `"direction" in pellet` returns `false`, causing force field to skip trapping shotgun pellets entirely.

**Fix:** Add `[Export]` attribute to `Direction` and `ShooterId` in `ShotgunPellet.cs`.

## Timeline of Events

1. **Issue #676**: Force field initially implemented with bullet reflection
2. **Issue #906**: User requests bullet trapping + bubble visual
3. **PR #907**: AI implements trapping logic in GDScript `force_field_effect.gd` — tested against GDScript bullets only
4. **PR #907 merged by accident** (user mistake)
5. **Issue #912**: User notices two bugs:
   - The force field doesn't trap bullets (C# Bullet.cs QueueFree race condition)
   - The visual is wrong (dark/blue fill instead of bubble)
6. **First fix session (PR #913)**: Fixed `bullet.has()` → `"direction" in bullet`, removed `inner_glow`, added `IsForceFieldArea()` in Bullet.cs
7. **User reports same issues persist** — user was testing with old compiled game export, not rebuilt code
8. **Second fix session (PR #913 continued)**: Fixed GradientTexture2D → white texture, added ring fallback, added [Export] to ShotgunPellet Direction/ShooterId, improved projectile type detection

## Files Modified

1. `Scripts/Projectiles/Bullet.cs` — Add `IsForceFieldArea()` check to prevent `QueueFree()` when entering force field
2. `Scripts/Projectiles/ShotgunPellet.cs` — Add `[Export]` to `Direction` and `ShooterId`; add `IsForceFieldArea()` check
3. `scripts/effects/force_field_effect.gd` — Fix `has()` → `in` operator; white texture; ring fallback; ShotgunPellet path detection
4. `scripts/shaders/force_field.gdshader` — Remove `inner_glow` entirely

## Key Lessons

- **GDScript `in` operator vs `has()`**: Use `"property" in node` for property existence checks on Node objects. `Object.has()` does not exist in Godot 4 — it's a Dictionary method that silently returns null when called on a Node, making conditions always-true or always-false.
- **C# [Export] for GDScript interop**: C# properties need `[Export]` for GDScript's `in` operator and `property = value` assignment to work.
- **Compiled export vs editor source**: C# code changes require a full rebuild. GDScript changes take effect at runtime. Testing must account for this.
- **Shader texture independence**: When a canvas_item shader fully replaces `COLOR`, use a neutral (white, fully opaque) base texture to avoid interference from the texture's built-in color.
