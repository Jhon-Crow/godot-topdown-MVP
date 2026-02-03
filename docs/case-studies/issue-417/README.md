# Case Study: Issue #417 - Add Castle Level (Замок)

## Issue Reference
- **Issue**: [#417](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/417)
- **PR**: [#420](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/420)
- **Title**: добавить уровень - замок (Add Castle Level)

## Timeline of Events

### Initial Request (Issue #417)
**Requirement**: Create a new castle level with:
- Width: ~6000px (3 viewports)
- Layout matching the provided sketch
- Oval-shaped castle walls
- Central tower with inner circle
- Horizontal wings with entrances
- Multiple cover positions arranged in a step pattern
- Enemies positioned strategically

### First Implementation Attempt
The initial implementation created:
- Basic castle structure with oval walls
- Central tower with collision
- Horizontal wings with walls
- Cover positions (limited arrangement)
- 13 enemies with various weapon types

### Feedback Round 1 (PR Comment)
User reported:
1. Camera stopped at 4128px while map extends to 6000px
2. Castle building layout didn't match reference
3. Enemies weren't using player-like weapons

**Fix Applied**:
- Camera limits removed to follow player everywhere
- Castle building redesigned with room openings
- Enemies updated to use same bullet/pellet scenes as player

### Feedback Round 2
User reported 3 issues:
1. **Invisible walls** - Castle has several collision areas blocking player movement
2. **Castle doesn't match image** - Building structure still not accurate to reference
3. **Enemies behind covers** - Enemies should be positioned behind their covers so player is hidden at game start

**Fix Applied**:
- Adjusted collision shape positions and scales
- Redesigned castle with room-style openings
- Repositioned enemies behind covers

### Feedback Round 3 (2026-02-03T21:30:08Z)
User reported via game log (`game_log_20260204_002353.txt`):
1. **Level still doesn't match reference image**
2. **Castle entrances requirement**: Left wing, right wing, and center - everything else solid wall
3. **Remove invisible walls from castle wings**

**Root Cause Analysis from Game Log**:
```
[00:23:57] [ENEMY] [UziEnemy3] ROT_CHANGE: P5:idle_scan -> P1:visible, state=IDLE, target=90.0°, current=40.1°, player=(3000,2100), corner_timer=0.00
[00:23:57] [ENEMY] [UziEnemy3] Player distracted - priority attack triggered
```

The enemy UziEnemy3 at position (3000, 700) had direct line of sight to player at (3000, 2100) - both were aligned on x=3000 with no obstacles blocking the view through the center entrance.

**Fix Applied**:
1. **Simplified castle building structure**:
   - Removed all "room divider" decorations (LeftWingRoom1, LeftWingRoom2, etc.)
   - Removed L-shaped lower walls (LeftLowerLWall, RightLowerLWall)
   - Each wing now has: top wall, bottom wall, end wall (3 solid sides)
   - Wings have open side facing center (entrance)
   - Center area has south wall with gap for center entrance

2. **Three entrances only**:
   - Left wing entrance: Open side facing center courtyard
   - Right wing entrance: Open side facing center courtyard
   - Center entrance: Gap between CenterSouthWallLeft and CenterSouthWallRight

3. **Enemy repositioning to block line of sight**:
   - UziEnemy1: Moved from (2700, 550) to (2500, 550) - behind CenterSouthWallLeft
   - UziEnemy2: Moved from (3300, 550) to (3500, 550) - behind CenterSouthWallRight
   - UziEnemy3: Moved from (3000, 700) to (3000, 300) - behind the tower

## Castle Building Layout (Final)

```
Reference Image Structure:
                          [FOREST - ЛЕС]
    ╔════════════════════════════════════════════════════════════╗
    ║                     OVAL CASTLE WALL                       ║
    ║                                                            ║
    ║   ┌─────────────────┐   ╭──────╮   ┌─────────────────┐    ║
    ║   │  LEFT WING      │   │TOWER │   │   RIGHT WING    │    ║
    ║   │  (entrance →)   │   │  ◯   │   │  (← entrance)   │    ║
    ║   └─────────────────┘   ╰──────╯   └─────────────────┘    ║
    ║                       ║        ║                          ║
    ║   ═══════════════════╝  gap   ╚═══════════════════════   ║
    ║                      ↑ center ↑                           ║
    ║                        entrance                           ║
    ║                                                            ║
    ║        [covers arranged in stepped pattern]                ║
    ║                                                            ║
    ║                      [PLAYER SPAWN]                        ║
    ║                      [EXIT ZONE]                           ║
    ╚════════════════════════════════════════════════════════════╝

Wall Dimensions:
- LeftWingTopWall: position (1400, 350), width 1200px
- LeftWingBottomWall: position (1400, 650), width 1200px
- LeftWingEndWall: position (800, 500), height 324px
- RightWingTopWall: position (4600, 350), width 1200px
- RightWingBottomWall: position (4600, 650), width 1200px
- RightWingEndWall: position (5200, 500), height 324px
- CenterSouthWallLeft: position (2450, 750), width 900px (covers x=2000-2900)
- CenterSouthWallRight: position (3550, 750), width 900px (covers x=3100-4000)
- Center entrance gap: x=2900 to x=3100 (200px wide)
```

## Enemy Line of Sight Analysis

Player spawn: (3000, 2100)
Center entrance: x=2900 to x=3100

| Enemy | Old Position | New Position | Blocked By |
|-------|--------------|--------------|------------|
| UziEnemy1 | (2700, 550) | (2500, 550) | CenterSouthWallLeft (x=2000-2900) |
| UziEnemy2 | (3300, 550) | (3500, 550) | CenterSouthWallRight (x=3100-4000) |
| UziEnemy3 | (3000, 700) | (3000, 300) | CenterTower (radius 180 at y=450) |
| ShotgunEnemy1 | (1000, 500) | No change | Wing walls |
| ShotgunEnemy2 | (1400, 500) | No change | Wing walls |

## Files Modified

1. `scenes/levels/CastleLevel.tscn` - Complete castle level scene
   - Simplified wall structure (removed room dividers and L-shaped walls)
   - Three entrance design (left wing, right wing, center)
   - Repositioned enemies to block line of sight at spawn
   - Updated labels to match new positions

## Game Log Evidence

Key events from `logs/game_log_20260204_002353.txt`:
- Line 215: Scene changed to CastleLevel
- Line 386-387: UziEnemy3 immediately detected player and started combat
- Line 388-500: Combat ensued with player taking damage within first second

This confirms the line of sight issue - enemies could see and attack the player immediately upon level load.

## Lessons Learned

1. **Reference Image Interpretation**: The reference shows:
   - Wings as enclosed spaces with ONE entrance (facing center)
   - Not multiple room divisions or decorative openings
   - "Solid wall except entrances" means exactly that

2. **Line of Sight Testing**: Always verify:
   - Enemy positions relative to entrances/gaps
   - No direct path from enemy to player spawn
   - Cover/walls actually block the sightlines

3. **Collision Shape Simplicity**:
   - Simpler structures = fewer alignment issues
   - Each wall should have ONE collision shape matching its visual

## Testing Recommendations

1. **Line of Sight Test**: At spawn, verify no enemy can see player:
   - Check game log for any "ROT_CHANGE: ... -> P1:visible" within first 2 seconds
   - All enemies should remain in IDLE state initially

2. **Entrance Test**: Verify exactly 3 entrances:
   - Walk into left wing from center
   - Walk into right wing from center
   - Walk through center entrance under tower

3. **No Invisible Walls**: Walk around entire castle perimeter:
   - All collision should match visible walls
   - No unexpected blocking

4. **Camera Test**: Camera follows player to all edges (0-6000px)

## Related Files

- `logs/game_log_20260204_002353.txt` - Game log showing the line of sight issue
- `castle-reference-feedback.png` - Reference image from PR feedback
- `original-sketch.png` - Original sketch from issue #417
- `reference_image.png` - Same as original-sketch.png
