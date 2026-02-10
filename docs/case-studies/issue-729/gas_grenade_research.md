# Gas Grenade Mechanics Research - Industry Best Practices

## Research Summary

Based on research from various tactical games and community sources, here are the established best practices for gas grenade effects on enemy AI:

## 1. Enemy Behavior During Gas Exposure

### Expected Behaviors (Industry Standard)
1. **Tactical Movement**: Enemies should NOT stand still
   - Should move to find better positions
   - Should attempt to flank or gain tactical advantage
   - Should seek cover when appropriate

2. **Dynamic Targeting**: 
   - Enemies should prioritize targets within gas cloud first
   - Should switch targets based on threat proximity and opportunity
   - Should maintain situational awareness

3. **State Integration**:
   - Gas effects should modify existing AI states, not replace them
   - Enemies should still use core tactical behaviors (cover, flanking, searching)
   - Movement should remain fluid and responsive

### Problematic Behaviors (What to Avoid)
1. **Static Turret Behavior**: Standing completely still while shooting
2. **AI State Override**: Completely bypassing sophisticated AI systems
3. **No Tactical Movement**: Ignoring flanking, cover, or advance maneuvers
4. **No Searching**: Standing still when no targets available

## 2. Gas Grenade Design Patterns

### Common Implementation Approaches

#### Approach 1: AI State Modification (Recommended)
- Gas effects add "aggression" modifier to existing AI
- Enemies use normal AI states but with modified target priorities
- Preserves all tactical movement and behaviors
- More complex but provides better gameplay

#### Approach 2: Behavior Override (Current - Problematic)
- Gas effects replace normal AI completely
- Simplified combat logic only
- Loses tactical depth and realism
- Easier to implement but creates gameplay issues

#### Approach 3: Hybrid (Best of Both)
- Use gas-specific target selection
- Delegate movement to existing AI systems
- Add gas-specific tactical considerations
- Balanced complexity and functionality

## 3. Specific Game Examples

### The Finals (2023)
- Gas grenade creates damage-over-time area
- AI attempts to escape gas cloud
- Enemies maintain tactical awareness
- Movement priorities: escape > engage > cover

### Ready or Not (2023)
- Gas grenades cause suspect stress responses
- AI becomes more erratic but still mobile
- Enemies attempt to leave gas area
- Maintains cover-seeking behavior

### Rainbow Six Series
- Gas/smoke causes AI to change behavior patterns
- Enemies attempt to flank through smoke
- Movement becomes more cautious but continues
- Preserves tactical AI state machine

### Escape from Tarkov
- Gas effects cause AI to change priorities
- Enemies may retreat or advance aggressively
- Movement patterns adapt to situation
- Complex AI decision-making maintained

## 4. Technical Implementation Best Practices

### Movement Integration
```gdscript
# GOOD: Maintain movement during combat
if has_line_of_sight(target):
    engage_target_with_movement()
else:
    advance_on_target_with_tactical_movement()

# BAD: Static behavior
if has_line_of_sight(target):
    stand_still_and_shoot()  # Current issue
```

### State Preservation
```gdscript
# GOOD: Modify existing states
if is_affected_by_gas:
    modify_target_priorities()
    adjust_movement_patterns()
    # Keep existing AI states intact

# BAD: Complete override  
if is_affected_by_gas:
    override_all_ai_behavior()  # Current issue
```

### Tactical Considerations
1. **Distance Management**: Enemies should maintain optimal engagement distance
2. **Cover Usage**: Should still seek cover when appropriate
3. **Flanking**: Should attempt tactical positioning
4. **Target Switching**: Should evaluate multiple threats dynamically
5. **Movement Fluidity**: Should never become completely static

## 5. Recommended Solution for Current Codebase

### Issue Analysis
The current `AggressionComponent.process_combat()` implements the problematic "Behavior Override" approach:
- Completely replaces enemy AI with simplified combat
- Forces enemies to stand still when they have LOS (`velocity = Vector2.ZERO`)
- Loses all tactical depth and movement behaviors

### Recommended Fix Strategy
Implement "AI State Modification" approach:

1. **Preserve AI States**: Allow enemies to use existing COMBAT, FLANKING, SEEKING_COVER states
2. **Modify Target Selection**: Make enemies prioritize other enemies during gas effect
3. **Enhance Movement**: Add tactical movement options during engagement
4. **Maintain Behaviors**: Keep cover-seeking, flanking, and searching behaviors

### Implementation Plan
1. **Fix Static Movement**: Remove `velocity = Vector2.ZERO` when has LOS
2. **Add Tactical Movement**: Implement advance, strafe, and positioning behaviors
3. **Integrate States**: Allow normal AI state processing during aggression
4. **Enhance Targeting**: Maintain enemy vs. enemy targeting while preserving tactical awareness

This approach aligns with industry best practices and will fix the reported issue where aggressive enemies don't move or flank.