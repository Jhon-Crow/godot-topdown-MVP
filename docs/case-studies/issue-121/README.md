# Case Study: Issue #121 - Weapon Sensitivity System

## Issue Summary

**Issue:** [#121 - Update Weapons](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/121)
**Date Opened:** January 18, 2026
**Author:** Jhon-Crow

### Original Description (Russian)
> я пытаюсь решить проблему: сейчас курсора не видно, но он продолжает влиять на скорость поворота оружия. чувствительность должна действовать так, как если бы я закрепил курсор жёстко на одном и том же расстоянии от игрока (как на поводке).
> у всего оружия должна быть своя чувствительность (по умолчанию - автоматическая, то есть зависит от дальности курсора от игрока).
> установи чувствительность штурмовой винтовки на 4.

### Translation
> I'm trying to solve a problem: currently the cursor is not visible, but it continues to affect the weapon rotation speed. Sensitivity should work as if I've locked the cursor firmly at the same distance from the player (like on a leash).
> All weapons should have their own sensitivity (default is automatic, i.e., depends on cursor distance from the player).
> Set the assault rifle sensitivity to 4.

---

## Timeline of Events

### Background Context

1. **Pre-Issue State:** The game is a 2D top-down shooter built with Godot 4.x and C#
2. **PR #120 (Jan 18, 2026 09:34):** Implemented fullscreen mode with mouse capture and hidden cursor
   - Commit `9ec5969` added `Input.MOUSE_MODE_CONFINED_HIDDEN` to hide cursor during gameplay
   - Modified files:
     - `project.godot` - fullscreen mode (mode=3)
     - `scripts/autoload/game_manager.gd` - set mouse mode on startup
     - `scripts/ui/pause_menu.gd` - toggle cursor visibility on pause
3. **Issue #121 Opened (Jan 18, 2026):** User reports that despite cursor being hidden, mouse position still directly affects weapon rotation speed, creating inconsistent aiming experience

### Key Files Involved

| File | Purpose |
|------|---------|
| `Scripts/Weapons/AssaultRifle.cs` | Main weapon with laser sight and auto/burst modes |
| `Scripts/Data/WeaponData.cs` | Weapon configuration resource (needs sensitivity) |
| `Scripts/AbstractClasses/BaseWeapon.cs` | Base class for all weapons |
| `Scripts/Characters/Player.cs` | Player character handling input |
| `scripts/autoload/game_manager.gd` | Sets mouse mode at game start |
| `resources/weapons/AssaultRifleData.tres` | Assault rifle configuration data |

---

## Root Cause Analysis

### The Problem

When `MOUSE_MODE_CONFINED_HIDDEN` is active:
1. The cursor is invisible to the player
2. The actual mouse position (`GetGlobalMousePosition()`) still moves freely within the window
3. Weapon aim direction is calculated as a normalized vector from player to mouse position
4. This means cursor distance from player directly affects how fast aiming changes

### Current Code Flow

```
Player shoots → GetGlobalMousePosition() → Calculate direction → Weapon fires in that direction
```

**In `AssaultRifle.cs` (line 183-187):**
```csharp
Vector2 mousePos = GetGlobalMousePosition();
Vector2 direction = (mousePos - GlobalPosition).Normalized();
_aimDirection = direction;  // Direct mapping - no sensitivity applied
```

### Why This Is Problematic

1. **Variable Rotation Speed:** When cursor is close to player, small mouse movements cause large angle changes. When far away, the same movements cause small angle changes.
2. **Hidden Cursor Confusion:** Player cannot see where cursor is, leading to unpredictable aiming behavior.
3. **No Consistency:** Different weapons feel different depending on where the invisible cursor happens to be positioned.

### Expected Behavior (User's Description)

The user wants a "leash" system where:
- Virtual cursor is always at a **fixed distance** from the player
- Sensitivity multiplier controls how fast the aim rotates
- Each weapon can have its own sensitivity value
- Default behavior: automatic (based on actual cursor distance)

---

## Research Findings

### Godot Mouse Handling (from web search)

According to [Godot 4 Recipes - Capturing the Mouse](https://kidscancode.org/godot_recipes/4.x/input/mouse_capture/index.html):

- `MOUSE_MODE_HIDDEN`: Cursor invisible, can leave window
- `MOUSE_MODE_CAPTURED`: Cursor hidden, cannot leave window
- `MOUSE_MODE_CONFINED`: Cursor visible, cannot leave window
- `MOUSE_MODE_CONFINED_HIDDEN`: Cursor hidden, cannot leave window (current setting)

Key insight from [Yo Soy Freeman's tutorial](https://yosoyfreeman.github.io/article/godot/tutorial/achieving-better-mouse-input-in-godot-4-the-perfect-camera-controller/):
> "Godot will automatically use raw mouse data under Linux and Windows when the mouse mode is set to captured... this is why sensitivity and precision change when you capture the mouse"

From [Playgama Blog](https://playgama.com/blog/godot/how-can-i-implement-and-adjust-mouse-sensitivity-settings-in-godot-fps-games-to-enhance-player-experience/):
> "The relative property of InputEventMouseMotion can be assigned to a variable and multiplied by mouse_sensitivity"

### Similar Implementations

[GitHub: 2D Gun Character rotation towards mouse](https://github.com/FortiEighty/Godot-4.3---2D-Gun-Character-rotation-towards-mouse):
- Standard implementation rotates weapon based on mouse position
- No sensitivity system implemented

[Godot Forum: Restrict cursor to radius](https://forum.godotengine.org/t/i-need-help-in-coding-this-feature-to-my-2d-top-down-shooter-please/41425):
- Community member asked for similar "cursor on a leash" feature
- Suggests using virtual cursor position at fixed distance from player

---

## Proposed Solutions

### Solution 1: Fixed Virtual Distance with Sensitivity Multiplier (Recommended)

**Concept:**
- Store a "virtual aim angle" that accumulates mouse movement
- Sensitivity value controls rotation speed
- Higher sensitivity = faster rotation
- Weapon appearance: cursor always at fixed distance from player (the "leash")

**Implementation:**
1. Add `Sensitivity` property to `WeaponData.cs`
2. Track cumulative aim angle instead of direct mouse-to-direction mapping
3. Apply sensitivity multiplier to angle changes
4. Calculate aim direction from fixed virtual distance

**Advantages:**
- Consistent feel regardless of actual cursor position
- Per-weapon customization
- Familiar to players from FPS games

### Solution 2: Interpolated Aim with Speed Limit

**Concept:**
- Keep current mouse position tracking
- Add maximum rotation speed per second
- Sensitivity controls the interpolation speed

**Advantages:**
- Simpler implementation
- More natural feel for some players

**Disadvantages:**
- May feel "laggy" at low sensitivity values

### Solution 3: Virtual Distance Normalization

**Concept:**
- Calculate aim direction normally
- Use sensitivity as a divisor for virtual cursor distance
- sensitivity=4 means virtual cursor at 1/4 of viewport diagonal

**Implementation:**
```csharp
float virtualDistance = viewportDiagonal / Sensitivity;
Vector2 virtualMousePos = GlobalPosition + direction * virtualDistance;
```

This is the approach that matches the user's description of "like on a leash."

---

## Selected Solution: #3 - Virtual Distance Normalization

This solution best matches the user's description and requirements:
1. Cursor acts as if "on a leash" at fixed distance
2. Sensitivity divides the virtual distance
3. sensitivity=4 means cursor is 4x closer virtually, making rotation 4x more responsive
4. Default (sensitivity=0 or automatic) uses actual cursor distance

---

## Implementation Plan

### Step 1: Add Sensitivity to WeaponData.cs
```csharp
[Export]
public float Sensitivity { get; set; } = 0.0f;  // 0 = automatic
```

### Step 2: Update AssaultRifle.cs UpdateLaserSight()
Modify aim direction calculation to use virtual distance when sensitivity > 0.

### Step 3: Update AssaultRifleData.tres
Set sensitivity to 4 as requested.

### Step 4: Document the feature
Add comments explaining the sensitivity system.

---

## Files to Modify

1. `Scripts/Data/WeaponData.cs` - Add Sensitivity property
2. `Scripts/Weapons/AssaultRifle.cs` - Apply sensitivity in UpdateLaserSight()
3. `resources/weapons/AssaultRifleData.tres` - Set Sensitivity=4

---

## Success Criteria

1. Assault rifle has sensitivity value of 4
2. Weapon rotation feels consistent regardless of actual cursor position
3. Higher sensitivity = faster rotation
4. Sensitivity=0 (default) maintains current behavior for backwards compatibility
5. Each weapon can have its own sensitivity value

---

## References

- [Godot 4 Recipes - Capturing the Mouse](https://kidscancode.org/godot_recipes/4.x/input/mouse_capture/index.html)
- [Achieving better mouse input in Godot 4](https://yosoyfreeman.github.io/article/godot/tutorial/achieving-better-mouse-input-in-godot-4-the-perfect-camera-controller/)
- [Mouse sensitivity settings in Godot FPS games](https://playgama.com/blog/godot/how-can-i-implement-and-adjust-mouse-sensitivity-settings-in-godot-fps-games-to-enhance-player-experience/)
- [Godot Forum: Restrict mouse cursor to radius](https://forum.godotengine.org/t/i-need-help-in-coding-this-feature-to-my-2d-top-down-shooter-please/41425)
- [GitHub: 2D Gun rotation towards mouse](https://github.com/FortiEighty/Godot-4.3---2D-Gun-Character-rotation-towards-mouse)
