# Case Study: Issue #668 - Fix Revolver Reloading

## Problem Description

The revolver reload system has a bug where cartridges can be inserted into already-occupied chambers. Two specific scenarios are described:

### Scenario 1: Back-and-forth rotation
1. Open cylinder
2. Insert a cartridge into chamber (e.g., chamber 0)
3. Rotate forward (scroll up) - moves to chamber 1
4. Rotate backward (scroll down) - moves back to chamber 0
5. **Bug**: The system allows inserting another cartridge into chamber 0 (already occupied)

### Scenario 2: Fired rounds and top-up reload
1. Start with a full cylinder (5/5)
2. Fire one shot (4/5, next chamber will advance on next shot)
3. Open cylinder to reload
4. **Bug**: The current chamber position may be occupied, but the system allows insertion
5. **Expected**: Player should rotate to the empty chamber before inserting

## Root Cause Analysis

The revolver tracks ammunition as a single integer `CurrentAmmo` rather than tracking the state of each individual chamber. The `_cartridgeInsertionBlocked` flag is a simple boolean that gets reset to `false` on every cylinder rotation, regardless of whether the destination chamber is occupied.

### Code Flow (Before Fix)

```
InsertCartridge() → CurrentAmmo++ → _cartridgeInsertionBlocked = true
RotateCylinder()  → _cartridgeInsertionBlocked = false  // Always unblocks!
```

The `CanInsertCartridge` property only checks `CurrentAmmo < CylinderCapacity`, which prevents inserting when the cylinder is globally full, but doesn't prevent inserting into an already-occupied specific chamber.

## Solution: Per-Chamber State Tracking

### Approach
Add a boolean array `_chamberOccupied[CylinderCapacity]` that tracks whether each individual chamber slot is loaded (has a live round) or empty. Add an integer `_currentChamberIndex` to track which chamber the cylinder is currently pointing at.

### Key Changes

1. **`_chamberOccupied` array**: Tracks loaded/empty state for each chamber
2. **`_currentChamberIndex`**: Tracks current cylinder position (0 to CylinderCapacity-1)
3. **`RotateCylinder()`**: Now checks if the destination chamber is occupied and only unblocks insertion if it's empty
4. **`InsertCartridge()`**: Now also checks that the current chamber is empty before allowing insertion
5. **`OpenCylinder()`**: Initializes chamber states based on current ammo and fired rounds
6. **`Fire()`**: Marks the current chamber as empty after firing

### Design Decisions

- Chamber tracking is only active during reload (when cylinder is open)
- When the cylinder opens, chambers are initialized: first N chambers are marked as occupied (where N = CurrentAmmo), remaining are empty
- Firing advances the chamber index and marks the fired chamber as empty
- This matches real revolver mechanics where the cylinder rotates to present each chamber

## References

- [Receiver (video game)](https://en.wikipedia.org/wiki/Receiver_(video_game)) - Gold standard for per-chamber gun mechanics in games
- [How Revolvers Work](https://science.howstuffworks.com/revolver2.htm) - Real-world revolver cylinder mechanics
- Issue #626 - Original multi-step cylinder reload implementation
- Issue #659 - One cartridge per drag gesture fix (related)
