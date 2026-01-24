# Case Study: Issue #194 - Add Shotgun

## Executive Summary

This case study analyzes the feature request to add a shotgun weapon to the godot-topdown-MVP game. The analysis includes codebase exploration, online research, timeline reconstruction, and proposed implementation solutions.

## Issue Overview

| Field | Value |
|-------|-------|
| Issue | [#194](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/194) |
| Title | добавь дробовик (Add Shotgun) |
| Author | Jhon-Crow |
| Created | 2026-01-22T00:45:01Z |
| Status | Open |
| Language | Russian |

## Request Translation

The owner requests a shotgun with the following specifications:

### Weapon Properties
| Property | Value | Notes |
|----------|-------|-------|
| Fire Mode | Semi-automatic | Limited by player skill |
| Pellets | 6-12 random | Per shot |
| Spread | 15 degrees | Cone angle |
| Spread Type | Always medium | No dynamic spread |
| Ricochet Max Angle | 35 degrees | Limited deflection |
| Wall Penetration | None | Cannot go through walls |
| Screen Shake | Large | Single recoil effect |
| Laser Sight | None | No aiming laser |
| Sound | Assault rifle level | Same loudness |
| Capacity | 8 shells | Tube magazine |
| Model | None yet | Visual model postponed |

### Control Scheme

**Reload Sequence:**
1. RMB drag down (open action)
2. MMB → RMB drag down (load shell, repeat 8x)
3. RMB drag up (close action)

**Fire Sequence:**
1. LMB (fire)
2. RMB drag up (cycle)
3. RMB drag down (ready)

## Case Study Documents

| Document | Description |
|----------|-------------|
| [issue-data.json](./issue-data.json) | Raw issue data from GitHub API |
| [issue-comments.json](./issue-comments.json) | Issue comments (empty) |
| [research-shotgun-mechanics.md](./research-shotgun-mechanics.md) | Online research on shotgun game mechanics |
| [codebase-analysis.md](./codebase-analysis.md) | Existing weapon system analysis |
| [timeline.md](./timeline.md) | Feature request timeline |
| [analysis.md](./analysis.md) | Deep technical analysis |

## Key Findings

### 1. Codebase Ready for Extension
The existing weapon system (`BaseWeapon.cs` → `AssaultRifle.cs`) provides a solid foundation. The `WeaponData` and `CaliberData` resources allow easy configuration of new weapons.

### 2. Multi-Pellet System Not Built-In
The current system spawns one bullet per shot. A shotgun requires spawning 6-12 pellets simultaneously with spread distribution.

### 3. Unique Reload Mechanic
The shell-by-shell reload with mouse drag gestures is a completely new paradigm not present in the current magazine-based system.

### 4. Armory Slot Reserved
The `armory_menu.gd` already has a "Shotgun" slot marked as "Coming soon", indicating planned expansion.

### 5. Real-World Research
- Real 00 buckshot spreads approximately 1 inch per yard (closer to 0.5" with quality ammo)
- Buckshot ricochets occur at shallow angles (typically under 30 degrees)
- Pump-action reload involves distinct open/load/close phases

## Root Causes

1. **Gameplay Variety Need**: Single weapon (M16) limits tactical options
2. **Architecture Gap**: No support for multi-projectile weapons
3. **Input System Gap**: No drag gesture recognition for reload

## Proposed Solutions

### Recommended: Phased Implementation

**Phase 1 (MVP):**
- Basic shotgun with multi-pellet spread
- Buckshot caliber data
- Large screen shake
- Simple instant reload (temporary)
- Armory integration

**Phase 2 (Enhanced):**
- Pump-action cycling
- RMB up/down gestures for action
- Audio feedback

**Phase 3 (Full):**
- Shell-by-shell manual reload
- MMB loading gesture
- Complete animation support

## Implementation Complexity

| Feature | Complexity | Risk |
|---------|------------|------|
| Multi-pellet spawn | Medium | Low |
| Cone spread | Low | Low |
| Buckshot caliber | Low | Low |
| Large screen shake | Low | Low |
| Semi-auto fire | Low | Low |
| Pump-action cycle | High | Medium |
| Shell reload | High | High |
| Mouse drag gestures | High | High |

## Recommendations

1. **Start with Phase 1**: Deliver playable shotgun quickly
2. **Iterate Based on Feedback**: Add complexity incrementally
3. **Maintain Backward Compatibility**: Don't break M16 functionality
4. **Create Tests**: Shell reload is complex enough to warrant unit tests

## Additional Data

### Game Log Analysis (2026-01-22)

A game log file (`game_log_20260122_035950.txt`) was provided showing current game behavior:

**Environment:**
- Windows build, Godot 4.3-stable
- Project: "Godot Top-Down Template"
- Debug build: false (release)

**Key Observations:**
1. Current weapon in use: AssaultRifle
2. Sound propagation system working (gunshot at 450, 1250 with range 1469)
3. Bullet ricochet system active (distance-based ricochet calculation)
4. 10 enemies spawning with various behaviors (GUARD, PATROL)
5. Effects managers initialized (PenultimateHit, LastChance)

**Relevant for Shotgun:**
- Sound propagation uses loudness range parameter (1469 for rifle)
- Bullet system tracks shooter position for distance calculations
- Screen shake and effects already integrated

### Icon Reference

The owner provided a reference for the shotgun icon: [3d-model.net pump-action shotgun](https://3d-model.net/3d-models/3d-modeli-oruzhie/strelkovoe-oruzhie/859-pompovoe-ruzhe.html)

Features for icon design:
- Pump-action shotgun silhouette
- Sliding foregrip mechanism
- Traditional stock and barrel proportions

## Implementation Progress

### Phase 1 - Completed (PR #195)

**Implemented:**
- ✅ Shotgun.cs with multi-pellet system (6-12 pellets per shot)
- ✅ 15° spread cone with even distribution
- ✅ Buckshot caliber (35° max ricochet, no penetration)
- ✅ Large screen shake (25.0 intensity)
- ✅ Armory integration with weapon selection
- ✅ Tutorial support with shotgun-specific instructions

**Issues Found (2026-01-22 04:13 Game Log):**

1. **Armory Selection Not Working**: The armory menu displayed the shotgun but there was no mechanism to actually select and equip it. The Player scene had AssaultRifle hardcoded.

2. **Root Cause**:
   - `Player.tscn` had AssaultRifle as embedded child node
   - `Player.cs` auto-equipped "AssaultRifle" by name at `_Ready()`
   - No weapon selection persistence in GameManager

**Fix Applied:**
- Added `selected_weapon` to GameManager for persistence
- Made armory menu slots clickable with visual selection highlighting
- Modified `tutorial_level.gd` and `building_level.gd` to swap weapons based on GameManager selection
- Updated tutorial prompts with shotgun-specific gestures

### Phase 2 - Pending

- Manual pump-action cycling with RMB gestures
- Shell-by-shell reload with MMB + RMB gestures

## Conclusion

The shotgun implementation is technically feasible and architecturally sound within the existing codebase. The primary challenge lies in the manual shell reload system, which requires a new input paradigm. A phased approach is recommended to balance feature delivery with risk management.

---

## Sources

### Online Research
- [Unreal Engine Shotgun Tutorial](https://dev.epicgames.com/community/learning/tutorials/9y9n/unreal-engine-14-weapon-shot-count-and-spread-let-s-make-a-top-down-top-down-shooter)
- [Unity Shotgun Spread Discussion](https://discussions.unity.com/t/2d-top-down-shooter-shotgun-bullets-spread/58976)
- [Godot Shotgun Scatter](https://forum.godotengine.org/t/how-would-i-make-a-shotgun-scatter-bullets-in-godot/16488)
- [Buckshot Pattern Testing](https://www.thefirearmblog.com/blog/2014/07/04/myth-busting-1-per-yard-shotgun-pattern-spreads/)
- [Shotgun Pellet Ricochet Study](https://store.astm.org/jfs11425j.html)
- [2024 Ricochet Research](https://www.sciencedirect.com/science/article/abs/pii/S1355030624000704)
- [Pump Action Shotgun Animation](https://thegunzone.com/how-a-pump-shotgun-works-animation/)

### Repository Analysis
- [Jhon-Crow/godot-topdown-MVP](https://github.com/Jhon-Crow/godot-topdown-MVP)
- Recent PRs: #172-#193 (scoring system, flashbang, player model, etc.)

---

*Case study compiled: 2026-01-22*
*Branch: issue-194-512524e2db12*
*PR: [#195](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/195)*
