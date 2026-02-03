# Case Study: Issue #437 - Tactical Reload for Shotgun

## Issue Summary

**Title:** fix перезарядка дробовика должна быть тактической (Shotgun reload should be tactical)

**Description:** When reloading the shotgun (only between shots), after the first RMB (right mouse button) press, the barrel should NOT rotate during drag-and-drop gestures. This allows the player to keep aiming at a specific spot (like a doorway or passage) while performing the reload sequence.

**Link:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/437

---

## Timeline of Events

### Problem Discovery
- Player noticed that while reloading the shotgun via RMB drag gestures, the weapon barrel and player model continue to track the mouse cursor
- This makes it impossible to "hold an angle" during tactical reload operations
- In real-world tactical scenarios, soldiers often reload while keeping their weapon pointed at a threat direction

### Current Behavior
1. Player initiates reload with RMB drag UP (opens bolt)
2. Player performs RMB drag DOWN with/without MMB (loads shells or closes bolt)
3. **Problem:** During steps 1-2, the shotgun sprite and player model continuously rotate to follow the mouse cursor
4. This rotation happens in every frame via `_Process()` → `UpdateAimDirection()` → `UpdateShotgunSpriteRotation()`

### Expected Behavior (Tactical Reload)
1. Player initiates reload with RMB drag UP (opens bolt)
2. **Aim direction is locked** at the moment reload starts
3. Player can move mouse freely for drag gestures without the weapon rotating
4. When reload completes, normal aim tracking resumes

---

## Technical Root Cause Analysis

### Primary Root Cause: Unconditional Aim Updates

The shotgun's aim direction and sprite rotation are updated every frame without checking the reload state.

**File:** `Scripts/Weapons/Shotgun.cs`

```csharp
// Line 379-394: _Process() method
public override void _Process(double delta)
{
    base._Process(delta);

    // Update aim direction - ALWAYS runs regardless of reload state!
    UpdateAimDirection();  // <-- Problem #1

    // ...
    HandleDragGestures();
}

// Lines 444-456: UpdateAimDirection() method
private void UpdateAimDirection()
{
    Vector2 mousePos = GetGlobalMousePosition();
    Vector2 toMouse = mousePos - GlobalPosition;

    if (toMouse.LengthSquared() > 0.001f)
    {
        _aimDirection = toMouse.Normalized();  // <-- Always updates
    }

    // Update sprite rotation if available
    UpdateShotgunSpriteRotation(_aimDirection);  // <-- Problem #2
}
```

### Secondary Root Cause: Player Model Rotation

The player model (body holding the weapon) also rotates to follow aim direction without checking shotgun reload state.

**File:** `Scripts/Characters/Player.cs`

```csharp
// Line 992 in _PhysicsProcess():
UpdatePlayerModelRotation();  // Called every frame

// Lines 1156-1203: UpdatePlayerModelRotation()
private void UpdatePlayerModelRotation()
{
    // ...

    // For non-AssaultRifle weapons, falls back to mouse direction
    Vector2 mousePos = GetGlobalMousePosition();
    Vector2 toMouse = mousePos - GlobalPosition;
    if (toMouse.LengthSquared() > 0.001f)
    {
        aimDirection = toMouse.Normalized();  // <-- Always follows mouse
    }

    // Apply rotation - NO check for shotgun reload state
    _playerModel.Rotation = targetAngle;  // <-- Problem #3
}
```

### Code Flow During Reload (Before Fix)

```
Every Frame:
│
├─► Shotgun._Process()
│   ├─► UpdateAimDirection()
│   │   ├─► _aimDirection = mouseDirection (WRONG during reload)
│   │   └─► UpdateShotgunSpriteRotation()
│   │       └─► _shotgunSprite.Rotation = angle (WRONG during reload)
│   └─► HandleDragGestures() [processes reload]
│
└─► Player._PhysicsProcess()
    └─► UpdatePlayerModelRotation()
        └─► _playerModel.Rotation = mouseAngle (WRONG during reload)
```

---

## Research: Tactical Reload in Games

### What is Tactical Reload?

From [Wikipedia - Tactical Reload](https://en.wikipedia.org/wiki/Tactical_reload):
> A tactical reload is executed by ejecting the magazine and retaining it while inserting a new magazine. The partially expended magazine can then be used later. The main advantage is that rounds are conserved, but the main disadvantage is that reloading is slower.

### Aim Lock During Reload in Other Games

Research from various game development forums and discussions:

1. **Darktide** ([Fatshark Forums](https://forums.fatsharkgames.com/t/change-shotgun-behaviour-when-reloading/80969)):
   - Shotgun reload can be interrupted when aiming down sights
   - Initiating ADS mid-reload affects behavior

2. **Red Dead Redemption 2** ([Steam Discussions](https://steamcommunity.com/app/1174180/discussions/0/3068621701760573612/)):
   - Releasing aim then re-aiming gives auto-aim lock advantage
   - Aim control is crucial during reload sequences

3. **Metal Gear Solid** series ([NeoGAF](https://www.neogaf.com/threads/mgs1-3-i-dont-understand-the-design-decision-of-tactical-reload.1336928/)):
   - Tactical reload involves quick weapon manipulation
   - In MGS3 online, shotgun could use tactical reload for quick successive shots

4. **Receiver** ([Wikipedia](https://en.wikipedia.org/wiki/Receiver_(video_game))):
   - Realistic gun mechanics where each reload step has a separate button
   - Individual control over each aspect of weapon manipulation

### Game Design Principles

From [Medium - What is the role of reloading as a game mechanic?](https://medium.com/rock-milk/what-is-the-role-of-reloading-as-a-game-mechanic-10f9e67ccc42):
> Reloading exchanges a vulnerability period (can't shoot) for battle readiness (a full clip) later, rewarding players that pay attention to their bullet count and limiting encounter duration.

The tactical reload with aim lock adds another dimension: players can maintain situational awareness during the vulnerability period by keeping their weapon pointed at a threat.

---

## Proposed Solution

### Design Decision

When the shotgun enters any reload state (Loading, WaitingToOpen, WaitingToClose), the aim direction should be **locked** at its current value until reload completes.

### Implementation Changes

#### 1. Shotgun.cs - Add Reload State Check to UpdateAimDirection()

```csharp
private void UpdateAimDirection()
{
    // TACTICAL RELOAD: Don't update aim direction during reload
    // This allows player to keep aiming at a specific spot while reloading
    if (ReloadState != ShotgunReloadState.NotReloading)
    {
        return; // Keep current _aimDirection locked
    }

    Vector2 mousePos = GetGlobalMousePosition();
    Vector2 toMouse = mousePos - GlobalPosition;

    if (toMouse.LengthSquared() > 0.001f)
    {
        _aimDirection = toMouse.Normalized();
    }

    UpdateShotgunSpriteRotation(_aimDirection);
}
```

#### 2. Player.cs - Add Shotgun Reload Check to UpdatePlayerModelRotation()

```csharp
private void UpdatePlayerModelRotation()
{
    if (_playerModel == null)
    {
        return;
    }

    // TACTICAL RELOAD: Don't rotate player model during shotgun reload
    // This keeps the player facing the same direction while reloading
    var shotgun = GetNodeOrNull<Shotgun>("Shotgun");
    if (shotgun != null && shotgun.ReloadState != ShotgunReloadState.NotReloading)
    {
        return; // Keep current rotation locked
    }

    // ... rest of method unchanged
}
```

### Code Flow After Fix

```
Every Frame:
│
├─► Shotgun._Process()
│   ├─► UpdateAimDirection()
│   │   ├─► IF ReloadState != NotReloading → RETURN (aim locked!)
│   │   ├─► _aimDirection = mouseDirection
│   │   └─► UpdateShotgunSpriteRotation()
│   └─► HandleDragGestures() [processes reload]
│
└─► Player._PhysicsProcess()
    └─► UpdatePlayerModelRotation()
        ├─► IF shotgun is reloading → RETURN (rotation locked!)
        └─► _playerModel.Rotation = mouseAngle
```

---

## Files Changed

| File | Change | Purpose |
|------|--------|---------|
| `Scripts/Weapons/Shotgun.cs` | Add reload check in `UpdateAimDirection()` | Lock aim direction during reload |
| `Scripts/Characters/Player.cs` | Add shotgun reload check in `UpdatePlayerModelRotation()` | Lock player rotation during shotgun reload |

---

## Testing Plan

### Manual Testing

1. **Basic Aim Lock Test:**
   - Start with shotgun
   - Point at a specific direction (e.g., toward a doorway)
   - Initiate reload (RMB drag UP)
   - Move mouse around for drag gestures
   - Verify barrel stays pointed at original direction
   - Complete reload and verify normal tracking resumes

2. **Mid-Reload Movement Test:**
   - Start reload while moving
   - Perform multiple shell loads
   - Verify aim stays locked throughout
   - Verify player model doesn't rotate during reload

3. **Combat Scenario Test:**
   - In a level with enemies
   - Point at a passage/doorway
   - Reload while keeping aim on the passage
   - Verify you can maintain "cover" angle during reload

---

## References

- [Tactical Reload - Wikipedia](https://en.wikipedia.org/wiki/Tactical_reload)
- [Fatshark Forums - Shotgun Behaviour](https://forums.fatsharkgames.com/t/change-shotgun-behaviour-when-reloading/80969)
- [Medium - Reloading as Game Mechanic](https://medium.com/rock-milk/what-is-the-role-of-reloading-as-a-game-mechanic-10f9e67ccc42)
- [TV Tropes - All-or-Nothing Reloads](https://tvtropes.org/pmwiki/pmwiki.php/Main/AllOrNothingReloads)
