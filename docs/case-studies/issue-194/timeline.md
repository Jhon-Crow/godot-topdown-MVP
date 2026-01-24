# Timeline and Sequence of Events

## Issue Context

**Issue #194**: Add Shotgun (добавь дробовик)
**Repository**: Jhon-Crow/godot-topdown-MVP
**Created**: 2026-01-22T00:45:01Z
**Author**: Jhon-Crow (repository owner)
**Status**: Open

## Repository Evolution Timeline

Based on the recent merged PRs, the repository has been actively developed:

| Date | PR | Feature Added |
|------|-----|---------------|
| 2026-01-21 | #172 | Hotline Miami-style score system |
| 2026-01-21 | #174 | Scoring system fixes |
| 2026-01-21 | #176 | M16 visual model |
| 2026-01-21 | #179 | Armory menu in pause menu |
| 2026-01-21 | #180 | Flashbang grenade |
| 2026-01-21 | #182 | Flashbang improvements |
| 2026-01-21 | #184 | Grenade throw position fix |
| 2026-01-21 | #186 | Modular player model |
| 2026-01-21 | #187 | System cursor/menu fixes |
| 2026-01-22 | #193 | Grenade explosion time freeze fix |
| **2026-01-22** | **#194** | **Shotgun request (this issue)** |

## Feature Request Breakdown

The issue requests a shotgun with specific mechanics:

### 1. Availability
- **Not default**: Must be selected manually
- **Armory access**: Replaceable via armory menu

### 2. Fire Mechanics
- **Semi-automatic**: One shot per click (player skill limited)
- **Pellet count**: 6-12 pellets randomly
- **Spread angle**: 15 degrees
- **Spread type**: Always medium (no dynamic spread)

### 3. Ballistics
- **Ricochet angle**: Maximum 35 degrees
- **Wall penetration**: Disabled

### 4. Feedback
- **Screen shake**: Large, single recoil effect
- **Laser sight**: None
- **Sound**: Same loudness as assault rifle

### 5. Ammunition
- **Capacity**: 8 shells
- **Reload**: Manual shell-by-shell loading

### 6. Reload Sequence (Mouse Gestures)
```
1. Open action:    RMB drag down
2. Load shells:    MMB → RMB drag down (repeat up to 8x)
3. Close action:   RMB drag up
```

### 7. Fire Sequence (Mouse Gestures)
```
1. Fire:           LMB (shoot)
2. Cycle action:   RMB drag up
3. Ready:          RMB drag down
```

### 8. Visual
- **Model**: Not yet (добавь модельку пока не добавляй)

## Analysis Requirements

The issue also requests:
> Please download all logs and data related about the issue to this repository, make sure we compile that data to `./docs/case-studies/issue-{id}` folder, and use it to do deep case study analysis (also make sure to search online for additional facts and data), in which we will reconstruct timeline/sequence of events, find root causes of the problem, and propose possible solutions.

## Key Observations

1. **Active Development**: The repository has seen 11+ PRs in the last ~24 hours
2. **Weapon System Exists**: M16 and Flashbang are already implemented
3. **Armory Menu Ready**: Infrastructure exists for weapon selection
4. **Shotgun Slot Reserved**: Already in armory_menu.gd as "Coming soon"
5. **Complex Reload**: The manual shell-loading mechanic is unique

## Sequence Diagram: Shotgun Fire Cycle

```
Player                  Shotgun               Bullets
  |                        |                     |
  |--[LMB Press]---------->|                     |
  |                        |--[Fire]------------>|
  |                        |   (6-12 pellets)    |
  |<--[Screen Shake]-------|                     |
  |                        |                     |
  |--[RMB Drag Up]-------->|                     |
  |                        |--[Cycle Action]--->X|
  |                        |   (pump sound)      |
  |                        |                     |
  |--[RMB Drag Down]------>|                     |
  |                        |--[Ready]---------->OK
  |                        |                     |
  v                        v                     v
```

## Sequence Diagram: Shotgun Reload

```
Player                  Shotgun               Magazine
  |                        |                     |
  |--[RMB Drag Down]------>|                     |
  |                        |--[Open Action]----->|
  |                        |   (click sound)     |
  |                        |                     |
  |--[MMB + RMB Down]----->|                     |
  |                        |--[Load Shell]------>|
  |                        |   (shell_count++)   |
  |  (repeat up to 8x)     |                     |
  |                        |                     |
  |--[RMB Drag Up]-------->|                     |
  |                        |--[Close Action]---->|
  |                        |   (chamber sound)   |
  v                        v                     v
```
