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
- Horizontal wings with room openings
- L-shaped lower walls
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

### Feedback Round 2 (Current - 2026-02-03T20:37:20Z)
User reported 3 issues:
1. **Invisible walls** - Castle has several collision areas blocking player movement
2. **Castle doesn't match image** - Building structure still not accurate to reference
3. **Enemies behind covers** - Enemies should be positioned behind their covers so player is hidden at game start

## Root Cause Analysis

### Issue 1: Invisible Walls
**Root Cause**: The collision shapes for castle walls were scaled beyond their visual representations, creating invisible blocking areas. Additionally, some walls had collision offsets that didn't match their visual positioning.

**Evidence**:
- `LeftLowerLWall` had collision shapes positioned at `Vector2(0, -100)` but visual wall at different offset
- Scale factors on collision shapes (e.g., `scale = Vector2(1.25, 1.0)`) caused misalignment

**Fix**: Adjusted collision shape positions and scales to match visual wall representations exactly.

### Issue 2: Castle Layout Mismatch
**Root Cause**: The reference image showed specific architectural features that weren't properly replicated:
1. Room openings in wings should be square doorways, not small decorative rectangles
2. L-shaped walls should have longer horizontal sections
3. Cover arrangement should follow a stepped/stair pattern in the center area

**Evidence from Reference Image** (`castle-reference-feedback.png`):
- Wings have 2 square room openings each (gaps in wall)
- L-shaped walls extend significantly in horizontal direction
- Covers are arranged in multiple rows forming a step pattern converging toward center

**Fix**:
- Changed room decorations to proper doorway-style openings (top and bottom wall sections)
- Extended L-shaped wall horizontal sections
- Added stepped cover arrangement with 3 rows on each side

### Issue 3: Enemy Positioning
**Root Cause**: Enemies were placed IN their defensive positions rather than BEHIND covers. This meant:
- Player was in direct line of sight of enemies at game start
- The strategic cover placement was negated

**Evidence from Reference Image**:
- Blue dots (enemies) are positioned north (behind) the black rectangles (covers)
- This creates initial cover for both enemies AND player

**Fix**: Repositioned all enemies to be north of (behind) their corresponding covers:
- Enemies in building wings stay inside the wing structure
- Patrol enemies placed in patrol zone areas
- Lower enemies placed behind their cover rows

## Cover Layout (Matching Reference)

The reference shows a specific stepped cover arrangement:

```
Row 1 (y=1350):   [cover] [cover] [cover]   gap   [cover] [cover] [cover]
                      2000    2300    2600           3400    3700    4000

Row 2 (y=1550):       [cover] [cover]         gap       [cover] [cover]
                          2150    2450                      3550    3850

Row 3 (y=1750):           [cover]              gap            [cover]
                              2300                                3700

Row 4 (y=1950):               [cover]                      [cover]
                                  2700                        3300
```

Plus 3 covers on each side (left at x=800,1100,1400 and right at x=4600,4900,5200) at y=1150.

## Files Modified

1. `scenes/levels/CastleLevel.tscn` - Complete castle level scene
   - Fixed collision shape alignments
   - Redesigned castle building with proper room openings
   - Rearranged covers in stepped pattern
   - Repositioned enemies behind covers

## Lessons Learned

1. **Visual-Collision Alignment**: Always verify collision shapes match visual representations exactly. Use position offsets that correspond to visual element offsets.

2. **Reference Image Interpretation**: Carefully study reference images for:
   - Relative positioning (enemies BEHIND covers, not ON them)
   - Architectural details (doorways vs decorations)
   - Pattern recognition (stepped vs linear arrangements)

3. **Gameplay Design Intent**: Consider the gameplay implications of positioning:
   - Player should have initial cover/stealth opportunity
   - Enemies should have defensive positions
   - Layout should encourage tactical movement

## Testing Recommendations

1. Walk test: Player should be able to navigate all walkable areas without hitting invisible walls
2. Line of sight test: At spawn, player should not be in direct line of sight of any enemy
3. Cover utilization test: Enemies should use covers effectively during combat
4. Camera test: Camera should follow player to all map edges (0 to 6000px)

## Related Files

- `castle-reference-feedback.png` - Reference image from PR feedback
- `original-sketch.png` - Original sketch from issue #417
