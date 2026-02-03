# Case Study: Issue #445 - Shotgun Pump Action Fails When Looking Up

## Issue Summary

**Title:** fix взвод затвора дробовика глядя вверх (fix shotgun bolt cocking while looking up)

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/445

### Problem Description

When the player is looking UP (toward the top of the screen/map) and tries to perform continuous shotgun pump action (RMB drag up then down in one motion) between shots, it doesn't work. The same gesture works correctly when looking in any other direction.

**Original Report (Russian):**
> если игрок смотрит вверх и пытается взвести затвор и зарядить заряд между выстрелами одним движением (RMB драгндроп вверх и вниз) - это не работает.
> если игрок смотрит в любое другое направление - непрерывное передёргивание затвора работает.

**Translation:**
> If the player looks up and tries to cock the bolt and load a shell between shots in one motion (RMB drag up and down) - it doesn't work.
> If the player looks in any other direction - continuous bolt pumping works.

---

## Technical Analysis

### Shotgun Pump Action Mechanics

The shotgun uses a pump-action system with RMB drag gestures:
1. **After firing:** `ActionState = NeedsPumpUp`
2. **RMB drag UP (toward screen top):** Ejects spent shell → `ActionState = NeedsPumpDown`
3. **RMB drag DOWN (toward screen bottom):** Chambers next round → `ActionState = Ready`

The system supports **continuous gestures** where the player can hold RMB and drag up then down without releasing.

### Relevant Code Files

- **`Scripts/Weapons/Shotgun.cs`** - Main shotgun weapon code
  - `HandleDragGestures()` - Main input handler (line 509)
  - `TryProcessMidDragGesture()` - Mid-drag gesture detection (line 630)
  - `ProcessDragGesture()` - Final gesture processing on RMB release (line 838)
  - `ProcessPumpActionGesture()` - Pump action state machine (line 894)

### Key Variables

- `_dragStartPosition`: World position when RMB was first pressed
- `_isDragging`: True while RMB is held
- `MinDragDistance`: 30 pixels (minimum drag to register gesture)
- `dragVector`: Current mouse position minus drag start position
- `isDragUp`: True when `dragVector.Y < 0` (screen Y increases downward)
- `isDragDown`: True when `dragVector.Y > 0`

### Gesture Detection Logic

```csharp
// TryProcessMidDragGesture()
if (dragVector.Length() < MinDragDistance) return false;

bool isVerticalDrag = Mathf.Abs(dragVector.Y) > Mathf.Abs(dragVector.X);
if (!isVerticalDrag) return false;

bool isDragUp = dragVector.Y < 0;
bool isDragDown = dragVector.Y > 0;
```

---

## Log File Analysis

### Log File: `game_log_20260203_212203.txt`

**Key Events:**
1. `[21:22:09]` Shotgun fired at position (150, 360) - pellets go UPWARD (Y values 322-349)
2. `[21:22:10]` First RMB drag started - `ActionState=NeedsPumpUp`
3. `[21:22:11]` RMB released after 42 frames - **NO pump action processed**
4. `[21:22:12]` Second RMB drag started - `ActionState=NeedsPumpUp` (unchanged!)
5. `[21:22:13]` RMB released after 43 frames - **NO pump action processed**
6. `[21:22:15]` Third RMB drag started - `ActionState=NeedsPumpUp` (unchanged!)
7. `[21:22:17]` RMB released after 124 frames - **NO pump action processed**

**Critical Observation:**
- The `ActionState` remains `NeedsPumpUp` through all drag attempts
- No "[Shotgun] Mid-drag pump UP" log message appeared
- This means `TryProcessMidDragGesture` never detected a valid pump UP gesture

### Potential Failure Points

1. **Drag too short:** `dragVector.Length() < 30` pixels
2. **Drag not vertical:** `Mathf.Abs(dragVector.Y) <= Mathf.Abs(dragVector.X)`
3. **Drag going wrong direction:** `isDragUp = false` (dragVector.Y >= 0)

---

## Hypotheses

### Hypothesis 1: Limited Screen Space When Looking Up

When looking UP:
- The mouse cursor is positioned near the top of the screen
- Dragging UP (toward screen top) has limited space available
- The player might not be able to drag 30+ pixels before hitting screen edge

**Counter-argument:** The player position was at Y=360 (middle of 720px screen), so there should be ~360 pixels of space above.

### Hypothesis 2: Player Movement During Drag

When looking UP, the player is likely moving forward (toward the top of the map):
- Camera follows player movement
- This could affect the world coordinate calculation of `GetGlobalMousePosition()`
- The `dragVector` might become skewed

**Counter-argument:** Both positions are in world coordinates, so camera movement should not affect the relative drag direction.

### Hypothesis 3: Horizontal Component Dominates

When dragging UP from a position near the top of the screen:
- The player might inadvertently add horizontal movement
- If `Mathf.Abs(dragVector.X) >= Mathf.Abs(dragVector.Y)`, the gesture is rejected as "not vertical"

This seems like the most likely cause, as the player at the screen edge has less vertical space but full horizontal freedom.

---

## Diagnostic Logging Added

To diagnose the actual root cause, detailed logging was added to `Shotgun.cs`:

### New Log Messages (Issue #445)

1. **`[Shotgun.FIX#445] TryProcessMidDragGesture`** - Logs drag vector every 10 frames
2. **`[Shotgun.FIX#445] Drag rejected - not vertical`** - Logs when drag fails verticality check
3. **`[Shotgun.FIX#445] In NeedsPumpUp but isDragUp=false`** - Logs when direction check fails
4. **`[Shotgun.FIX#445] ProcessDragGesture`** - Logs final drag vector on RMB release
5. **`[Shotgun.FIX#445] Drag too short`** - Logs when drag distance is insufficient
6. **`[Shotgun.FIX#445] Drag not vertical`** - Logs when final gesture fails verticality
7. **`[Shotgun.FIX#445] Valid vertical drag detected`** - Logs successful validation
8. **`[Shotgun.FIX#445] dragStartPos=..., aimDir=...`** - Logs start position and aim direction

These logs will help identify exactly why the gesture fails when looking UP.

---

## Proposed Solutions

### Solution 1: Reduce MinDragDistance for Pump Actions

Reduce the minimum drag distance specifically for pump actions to make detection more lenient:
```csharp
float effectiveMinDistance = (ActionState == ShotgunActionState.NeedsPumpUp ||
                              ActionState == ShotgunActionState.NeedsPumpDown)
                            ? MinDragDistance * 0.5f  // 15 pixels for pump
                            : MinDragDistance;        // 30 pixels for reload
```

### Solution 2: Relax Verticality Requirement for Pump Actions

Allow more horizontal tolerance when detecting pump gestures:
```csharp
// Current: strictly vertical (Y > X)
bool isVerticalDrag = Mathf.Abs(dragVector.Y) > Mathf.Abs(dragVector.X);

// Proposed: 60° cone (Y > X * 0.577) for pump actions
float verticalTolerance = isPumpAction ? 0.577f : 1.0f;
bool isVerticalDrag = Mathf.Abs(dragVector.Y) > Mathf.Abs(dragVector.X) * verticalTolerance;
```

### Solution 3: Direction-Relative Gestures

Make pump gestures relative to aim direction instead of screen direction:
- Drag AWAY from player (in aim direction) = pump UP
- Drag TOWARD player (opposite of aim direction) = pump DOWN

This would require significant changes and might be confusing for players.

---

## Files Changed

| File | Change | Purpose |
|------|--------|---------|
| `Scripts/Weapons/Shotgun.cs` | Added diagnostic logging | Identify root cause of gesture failure |

---

## Testing Plan

### With Diagnostic Logging

1. Build and test the game
2. Look UP (toward top of screen)
3. Fire shotgun
4. Attempt continuous pump gesture (RMB drag up then down)
5. Check log file for `[Shotgun.FIX#445]` messages
6. Analyze which check is failing:
   - Drag length
   - Verticality
   - Direction

### Expected Log Output

```
[Shotgun.FIX#445] dragStartPos=(X, Y), aimDir=(0.00, -1.00)  // Looking UP
[Shotgun.FIX#445] TryProcessMidDragGesture - dragVector=(?, ?), length=?, minDist=30
[Shotgun.FIX#445] ...  // One of the failure reasons
```

---

## References

- Issue #243 - Original MMB timing fix for shotgun reload
- Issue #437 - Tactical reload (barrel lock during drag)
- Issue #266 - Mid-drag shell loading fix

---

## Status

**Investigation in progress.** Diagnostic logging has been added. Next steps:
1. User tests with new build
2. Analyze logs to identify exact failure point
3. Implement targeted fix based on findings
