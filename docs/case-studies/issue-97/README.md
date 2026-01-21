# Case Study: Issue #97 - Add Assault Rifle Model

## Issue Summary

**Issue:** [#97 - добавить модель штурмовой винтовки](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/97)
**Author:** Jhon-Crow
**Date Created:** (See GitHub issue)
**Status:** In Progress

### Original Request (Russian)
> добавить модель к существующей штурмовой винтовке (модель что то типа m16)

### Translation
> Add a model to the existing assault rifle (something like M16)

### Reference Provided
- [SimplePlanes Assault Rifle with Cycling Action](https://www.simpleplanes.com/a/cD8RVZ/Assault-Rifle-with-Cycling-Action)

---

## Timeline of Events

### Phase 1: Issue Analysis
1. Issue opened requesting visual model for assault rifle
2. Reference provided: SimplePlanes AEV-972 Groza (drawing from M16, AEK-971, Groza-M, AK series, SCAR-H)
3. Project analyzed to determine implementation approach

### Phase 2: Research
1. SimplePlanes reference analyzed - detailed 3D model with cycling action
2. M16 rifle specifications researched
3. Codebase structure examined
4. **Key Finding:** Project is 2D-only (Node2D-based), not 3D

### Phase 3: Implementation
1. 2D sprite approach selected (appropriate for project type)
2. M16-style rifle sprite created
3. Sprite integrated into AssaultRifle scene
4. Rotation logic added to follow aim direction

---

## Root Cause Analysis

### Problem Statement
The assault rifle weapon exists in the game with full functionality (shooting, reloading, laser sight) but has no visual representation - only a laser line is visible to players.

### Root Causes

1. **Incomplete Implementation**
   - The weapon system was implemented with mechanics-first approach
   - Visual representation was deferred/omitted during initial development
   - Current player visualization: blue circle placeholder
   - Current weapon visualization: laser line only

2. **Project Architecture Mismatch**
   - Reference provided is a 3D model (SimplePlanes)
   - Project is a 2D top-down game
   - Solution requires 2D sprite, not 3D model

3. **Asset Directory Structure**
   - `/assets/sprites/` directory exists but is empty (only `.gitkeep`)
   - No weapon visual assets exist in the project

### Contributing Factors
- Focus on gameplay mechanics over visual polish
- Placeholder graphics used throughout (circles for characters)
- No sprite artist involvement apparent

---

## Technical Analysis

### Current Implementation
```
scenes/weapons/csharp/AssaultRifle.tscn
├── Node2D (AssaultRifle)
│   └── Line2D (LaserSight)
```

### Required Changes
```
scenes/weapons/csharp/AssaultRifle.tscn
├── Node2D (AssaultRifle)
│   ├── Sprite2D (RifleSprite) ← NEW
│   └── Line2D (LaserSight)
```

### Files Modified
1. `/scenes/weapons/csharp/AssaultRifle.tscn` - Added Sprite2D node
2. `/Scripts/Weapons/AssaultRifle.cs` - Added sprite rotation logic
3. `/assets/sprites/weapons/` - New directory for weapon sprites
4. `/assets/sprites/weapons/m16_rifle.png` - New M16 sprite asset

---

## Solution Implementation

### Approach: 2D Sprite Integration

Since this is a 2D top-down game, the "model" is implemented as a 2D sprite that:
1. Displays an M16-style rifle image
2. Rotates to follow the aim direction (matches laser sight)
3. Flips vertically when aiming left (to avoid upside-down appearance)
4. Maintains proper z-ordering with other game elements

### Visual Design
- Simple, clean M16 silhouette
- Appropriate scale for top-down perspective
- Semi-transparent to allow gameplay visibility
- Matches existing visual style (placeholder/minimalist)

### Code Changes
The sprite rotation is handled in `AssaultRifle.cs`:
- Sprite node reference obtained in `_Ready()`
- Rotation updated in `UpdateLaserSight()` to match aim direction
- Vertical flip applied when aiming left (angle > 90° or < -90°)

---

## Research Data

### M16 Rifle Specifications
| Specification | Value |
|--------------|-------|
| Caliber | 5.56×45mm NATO |
| Action | Gas-operated, rotating bolt |
| Rate of Fire | 700-950 rounds/min |
| Muzzle Velocity | 960 m/s |
| Effective Range | 550m (point), 800m (area) |
| Weight | 3.3 kg (unloaded) |
| Length | 1000mm |
| Barrel Length | 508mm |
| Magazine Capacity | 20 or 30 rounds |

### M16 Distinctive Visual Features
1. Carrying handle with rear sight on top receiver
2. "Straight-line" stock design (stock in line with bore)
3. Triangular or round handguard
4. Flash suppressor (bird-cage style on A1+)
5. Forward assist (A1+)
6. Magazine release button
7. Pistol grip

### M16 Variants
- **M16** - Original (1962), triangular handguard, full-auto
- **M16A1** - Vietnam era (1967), chrome-lined bore, bird-cage suppressor
- **M16A2** - 1982, heavier barrel, three-round burst
- **M16A3** - Full-auto variant of A2
- **M16A4** - Removable carry handle, Picatinny rail

---

## References

### Primary Sources
- [M16 Rifle - Wikipedia](https://en.wikipedia.org/wiki/M16_rifle)
- [M16 Rifle - Britannica](https://www.britannica.com/technology/M16-rifle)
- [SimplePlanes Reference Model](https://www.simpleplanes.com/a/cD8RVZ/Assault-Rifle-with-Cycling-Action)

### Asset Sources
- [OpenGameArt - 2D Guns (CC0)](https://opengameart.org/content/2d-guns) - Kay Lousberg
- [OpenGameArt - Gun Sprites (CC-BY 3.0)](https://opengameart.org/content/gun-sprites) - Stagnation

### Game Project Context
- Engine: Godot 4.3
- Language: C# (primary), GDScript (utilities)
- Type: 2D Top-Down Shooter
- Repository: [Jhon-Crow/godot-topdown-MVP](https://github.com/Jhon-Crow/godot-topdown-MVP)

---

## Lessons Learned

1. **Verify project type before proposing solutions** - A 3D model reference doesn't mean a 3D implementation is appropriate
2. **Check existing asset structure** - Empty sprite directories indicate incomplete visual implementation
3. **Consider the visual style** - Placeholder graphics suggest a minimalist/prototype aesthetic
4. **Match existing patterns** - The laser sight implementation showed how visuals should integrate with mechanics

---

## Appendix: Files Created/Modified

### New Files
- `docs/case-studies/issue-97/README.md` - This document
- `docs/case-studies/issue-97/references/simpleplanes-reference.md` - SimplePlanes model details
- `docs/case-studies/issue-97/references/m16-specifications.md` - M16 technical specifications
- `assets/sprites/weapons/m16_rifle.png` - M16 rifle sprite

### Modified Files
- `scenes/weapons/csharp/AssaultRifle.tscn` - Added Sprite2D node for rifle visual
- `Scripts/Weapons/AssaultRifle.cs` - Added sprite rotation following aim direction
