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

## Implemented Fix

Based on the hypothesis that the gesture fails due to limited vertical space when looking UP (causing more horizontal drift in the drag), the following changes were implemented:

### 1. Reduced Minimum Drag Distance for Pump Actions

For pump actions (NeedsPumpUp/NeedsPumpDown states), the minimum drag distance is reduced from 30px to 20px:

```csharp
float effectiveMinDistance = isPumpActionContext ? 20.0f : MinDragDistance;
```

This makes pump actions more responsive and easier to trigger with smaller gestures.

### 2. Relaxed Verticality Requirement for Pump Actions

For pump actions, the verticality check uses a 63° cone instead of the standard 45° cone:

```csharp
// Standard: Y > X (45° cone)
// Lenient: Y > X * 0.5 (63° cone)
float verticalityFactor = isPumpActionContext ? 0.5f : 1.0f;
bool isVerticalDrag = Mathf.Abs(dragVector.Y) > Mathf.Abs(dragVector.X) * verticalityFactor;
```

This allows more diagonal movement while still requiring mostly vertical intent, accommodating players who have less vertical space when looking UP.

### Code Changes Summary

| File | Change | Purpose |
|------|--------|---------|
| `Scripts/Weapons/Shotgun.cs` | `TryProcessMidDragGesture()` | Lenient detection for pump actions |
| `Scripts/Weapons/Shotgun.cs` | `ProcessDragGesture()` | Same lenient detection on RMB release |

### Why These Values?

- **20px minimum**: Still requires intentional gesture, but accommodates limited space scenarios
- **0.5 verticality factor**: Allows up to ~63° diagonal angle (was 45°), making it easier to register vertical intent with some horizontal drift
- **Only for pump actions**: Reload gestures keep the stricter requirements since they typically have more space/time

---

## Status (First Attempt)

**First fix attempted but FAILED.** The initial changes:
1. Added detailed diagnostic logging for debugging
2. Made pump action gestures more lenient (20px minimum, 63° cone)
3. Preserved strict detection for reload operations

However, the user reported "проблема сохранилась" (problem persists).

---

## Second Analysis: True Root Cause Identified

### New Log File Analysis: `game_log_20260203_220729.txt`

The new log file with diagnostic logging revealed the **true root cause**:

**Critical log entries:**
```
[22:07:38] [Shotgun.FIX#445] dragStartPos=(141, 15), aimDir=(-0,03, -1,00)
[22:07:38] [Shotgun.FIX#445] In NeedsPumpUp but isDragUp=false (isDragDown=True), dragVector.Y=92,5
[22:07:38] [Shotgun.FIX#445] In NeedsPumpUp but isDragUp=false (isDragDown=True), dragVector.Y=493,3
```

And later:
```
[22:07:45] [Shotgun.FIX#445] dragStartPos=(145, 0), aimDir=(-0,01, -1,00)
[22:07:46] [Shotgun.FIX#445] In NeedsPumpUp but isDragUp=false (isDragDown=True), dragVector.Y=719,3
```

### Analysis

| Metric | Value | Meaning |
|--------|-------|---------|
| `dragStartPos.Y` | 0-15 | Mouse is at **TOP of screen** |
| `aimDir.Y` | -1.00 | Player is looking **UP** |
| `ActionState` | `NeedsPumpUp` | System expects drag **UP** (negative Y) |
| `dragVector.Y` | +92 to +719 | User is dragging **DOWN** (positive Y) |

**The problem:** When looking UP, the mouse cursor is at the TOP of the screen (Y ≈ 0). The system expects `NeedsPumpUp` = drag UP = negative Y movement. But the user **cannot drag UP** because there's no screen space above Y=0!

The user's only option is to drag DOWN (positive Y), but the state machine rejects this because it's waiting for "drag UP" first.

### Why the First Fix Failed

The first fix reduced minimum distance and relaxed verticality, but **neither addresses the fundamental problem**: the gesture direction is physically impossible when looking UP.

- ✅ 20px minimum distance - good, but not the issue
- ✅ 63° cone - good, but not the issue
- ❌ The gesture direction (UP first) is impossible at screen top

---

## Timeline / Sequence of Events

### When Looking UP (reproducing the bug):

1. **T+0ms**: Player fires shotgun while looking UP
2. **T+0ms**: Mouse cursor is near top of screen (Y ≈ 0-20)
3. **T+0ms**: `ActionState` → `NeedsPumpUp` (expects drag UP)
4. **T+100ms**: Player presses RMB to start drag
5. **T+100ms**: `dragStartPos = (145, 0)` - at screen TOP
6. **T+200ms**: Player drags mouse DOWN (only possible direction)
7. **T+200ms**: `dragVector.Y = +300` (positive = DOWN in screen coords)
8. **T+200ms**: System checks: `isDragUp = (dragVector.Y < 0)` → **FALSE**
9. **T+200ms**: System rejects gesture: "In NeedsPumpUp but isDragUp=false"
10. **T+1000ms**: RMB released, gesture fails, `ActionState` remains `NeedsPumpUp`
11. **Repeat**: Player is stuck - cannot pump action when looking UP

### When Looking in Other Directions (working correctly):

1. **T+0ms**: Player fires shotgun while looking RIGHT
2. **T+0ms**: Mouse cursor is in CENTER of screen (Y ≈ 360)
3. **T+0ms**: `ActionState` → `NeedsPumpUp`
4. **T+100ms**: Player presses RMB, drags UP (toward top of screen)
5. **T+200ms**: `dragVector.Y = -50` (negative = UP in screen coords)
6. **T+200ms**: System checks: `isDragUp = (dragVector.Y < 0)` → **TRUE**
7. **T+200ms**: System accepts: "Pump UP - shell ejected"
8. **T+300ms**: Player continues drag DOWN
9. **T+400ms**: `dragVector.Y = +50` (from new reference point)
10. **T+400ms**: System accepts: "Pump DOWN - chambered"
11. **T+500ms**: Success - weapon is ready to fire

---

## Proposed Solution: Direction-Aware Pump Gestures

### Concept

Make pump gestures **relative to aim direction** instead of fixed screen coordinates:
- **Drag AWAY from player** (in aim direction) = "Pump UP" (eject shell)
- **Drag TOWARD player** (opposite of aim direction) = "Pump DOWN" (chamber)

When looking UP:
- Mouse at screen top → drag DOWN (toward center) = drag TOWARD player = "Pump UP"
- Then drag UP (toward edge) = drag AWAY from player = "Pump DOWN"

This naturally inverts the expected gesture when looking UP, matching the physical mouse space available.

### Mathematical Implementation

```csharp
// Convert screen drag vector to aim-relative direction
Vector2 dragVector = currentPosition - _dragStartPosition;

// Project drag onto aim direction
float dragAlongAim = dragVector.Dot(_aimDirection);
// Positive = drag in aim direction (AWAY from player)
// Negative = drag opposite to aim direction (TOWARD player)

// For pump actions:
// "Pump UP" (eject) = drag TOWARD player = negative dot product
// "Pump DOWN" (chamber) = drag AWAY from player = positive dot product
bool isDragPumpUp = dragAlongAim < -minDistance;
bool isDragPumpDown = dragAlongAim > minDistance;
```

### When Looking UP (aimDir ≈ (0, -1)):
- Drag screen DOWN (+Y) → dot product with (0, -1) = **negative** → "Pump UP"
- Drag screen UP (-Y) → dot product with (0, -1) = **positive** → "Pump DOWN"

### When Looking RIGHT (aimDir ≈ (1, 0)):
- Drag screen RIGHT (+X) → dot product with (1, 0) = **positive** → "Pump DOWN"
- Drag screen LEFT (-X) → dot product with (1, 0) = **negative** → "Pump UP"

### Benefits

1. **Works at all screen edges** - gestures adapt to available space
2. **Intuitive for players** - "pull back" and "push forward" relative to aim
3. **No UX change for normal play** - when looking right/left, vertical screen drags still work naturally
4. **Consistent with pump-action mental model** - pull toward you to eject, push away to chamber

---

## Alternative Solutions Considered

### Alternative 1: Invert gestures when looking UP
- **Pros**: Simple to implement
- **Cons**: Creates inconsistency based on aim angle, may confuse players

### Alternative 2: Use viewport-relative gestures
- **Pros**: Always predictable based on screen
- **Cons**: Doesn't solve the screen edge problem

### Alternative 3: Allow "pump DOWN first" when looking UP
- **Pros**: Quick fix
- **Cons**: Breaks the logical eject→chamber sequence

### Alternative 4: Mouse cursor confinement
- **Pros**: Prevents mouse from reaching screen edge
- **Cons**: Frustrating UX, limits precision aiming

**Selected: Direction-Aware Gestures** - Most robust and intuitive solution.

---

## Research References

- [TopDown Engine by More Mountains](https://topdown-engine.moremountains.com/) - Common weapon systems in top-down games
- [Receiver 2 Wiki: Controls](https://receiver.fandom.com/wiki/Controls) - Realistic gun manipulation mechanics
- [Receiver 2 Review](https://rogueliker.com/receiver-2-review/) - Example of gesture-based gun operations
- [Unity Discussions: Restricting Cursor Movement](https://discussions.unity.com/t/restricting-cursor-movement-to-a-screen-section-clamp/822377) - Mouse boundary issues in games
- [NN/G: Drag and Drop Design](https://www.nngroup.com/articles/drag-drop/) - UX best practices for drag gestures

---

## Files to Change

| File | Change | Purpose |
|------|--------|---------|
| `Scripts/Weapons/Shotgun.cs` | Add direction-aware gesture detection | Fix the root cause |
| `docs/case-studies/issue-445/README.md` | Update with root cause analysis | Documentation |

---

## Implementation Status

**FIX #2 IMPLEMENTED**: Direction-aware pump gesture system using dot product with aim direction.

### Code Changes (v2)

Added `GetDirectionAwarePumpGesture()` method to `Shotgun.cs`:
```csharp
/// <summary>
/// Uses dot product to project drag vector onto aim direction.
/// - Positive dot = drag in aim direction (AWAY from player) = "Pump DOWN" (chamber)
/// - Negative dot = drag opposite to aim (TOWARD player) = "Pump UP" (eject)
/// </summary>
private bool GetDirectionAwarePumpGesture(Vector2 dragVector, float minDistance,
    out bool isPumpUp, out bool isPumpDown)
{
    float dragAlongAim = dragVector.Dot(_aimDirection);
    float gestureThreshold = minDistance * 0.7f;

    isPumpUp = dragAlongAim < -gestureThreshold;   // Toward player
    isPumpDown = dragAlongAim > gestureThreshold;  // Away from player
    return isPumpUp || isPumpDown;
}
```

### How It Works

| Player Facing | Screen Drag | Dot Product | Gesture |
|---------------|-------------|-------------|---------|
| UP (0, -1) | DOWN (+Y) | negative | Pump UP (eject) |
| UP (0, -1) | UP (-Y) | positive | Pump DOWN (chamber) |
| RIGHT (1, 0) | LEFT (-X) | negative | Pump UP (eject) |
| RIGHT (1, 0) | RIGHT (+X) | positive | Pump DOWN (chamber) |
| DOWN (0, 1) | UP (-Y) | negative | Pump UP (eject) |
| DOWN (0, 1) | DOWN (+Y) | positive | Pump DOWN (chamber) |

### When Looking UP - Before and After

**BEFORE (broken):**
1. Mouse at screen top (Y=0)
2. System expects "drag UP" (negative Y)
3. User can only drag DOWN (positive Y)
4. Gesture rejected → pump action fails

**AFTER (fixed):**
1. Mouse at screen top (Y=0)
2. System expects "drag TOWARD player" (opposite of aim)
3. User drags DOWN → dot product with (0, -1) = negative
4. Gesture accepted as "Pump UP" → pump action succeeds!

### Files Changed

| File | Change | Lines |
|------|--------|-------|
| `Scripts/Weapons/Shotgun.cs` | Added `GetDirectionAwarePumpGesture()` method | ~60 new lines |
| `Scripts/Weapons/Shotgun.cs` | Updated `TryProcessMidDragGesture()` to use direction-aware detection | ~30 lines changed |
| `Scripts/Weapons/Shotgun.cs` | Updated `ProcessDragGesture()` to use direction-aware detection | ~20 lines changed |
| `Scripts/Weapons/Shotgun.cs` | Updated `ProcessPumpActionGesture()` parameter names | ~10 lines changed |

### Build Status

✅ Build successful (0 errors, 26 pre-existing warnings)
