# Root Cause Analysis - Issue 729: Gas Grenade Enemy Movement Bug

## Problem Summary
**Issue**: "агрессивные враги не перемещаются и не обходят с флангов других врагов. даже в searching состоянии стоят на месте."
**Translation**: Aggressive enemies don't move and don't flank other enemies, even in searching state they stand still.

## Root Cause Identified

### Primary Issue: AggressionComponent.process_combat() Logic Flaw

**Location**: `scripts/components/aggression_component.gd`, lines 38-50

**Problem Code**:
```gdscript
func process_combat(delta: float, rotation_speed: float, shoot_cooldown: float, combat_move_speed: float) -> void:
    if not _parent: return
    if _target == null or not is_instance_valid(_target) or _target.get("_is_alive") == false:
        _target = _find_nearest_enemy_target()
    if _target == null:
        _parent.velocity = Vector2.ZERO; return
    if _has_los(_target):                           # <-- ISSUE HERE
        # ... rotation and shooting logic ...
        _parent.velocity = Vector2.ZERO            # <-- ENEMY STOPS MOVING
    else:
        if _parent.has_method("_move_to_target_nav"): _parent._move_to_target_nav(_target.global_position, combat_move_speed)
```

### Critical Problems

#### 1. **Movement Completely Stops When Enemy Has LOS**
- **Line 48**: `_parent.velocity = Vector2.ZERO` forces enemy to stop completely
- **Effect**: Aggressive enemies become static turrets when they can see their target
- **Expected**: Enemies should move tactically (advance, strafe, find cover) even while shooting

#### 2. **No Tactical Movement Behaviors**
- **Missing**: Flanking behavior when attacking other enemies
- **Missing**: Advance movement to get better firing position
- **Missing**: Sidestepping to avoid incoming fire
- **Missing**: Cover seeking when under fire

#### 3. **No Integration with Enemy AI States**
- **Problem**: AggressionComponent completely bypasses the sophisticated AI state machine
- **Missing States**: Enemies should use existing AI states (COMBAT, FLANKING, SEEKING_COVER)
- **Effect**: All tactical intelligence is lost during aggression

#### 4. **Searching State Override**
- **Problem**: Even when enemies should be in SEARCHING state, aggression overrides all behavior
- **Expected**: Aggressive enemies should still search for targets when none visible
- **Current**: Enemies stand still when no target found (line 36-37)

## Analysis of Expected vs Actual Behavior

### Expected Behavior (Gas Grenade Design)
1. Enemy enters gas cloud → becomes aggressive for 10 seconds
2. Aggressive enemy searches for nearest enemy target
3. **Enemy should use existing AI behaviors** to engage target:
   - Move tactically (COMBAT state)
   - Attempt to flank (FLANKING state) 
   - Seek cover when needed (SEEKING_COVER state)
   - Search for targets when none visible (SEARCHING state)

### Actual Behavior (Bug)
1. Enemy enters gas cloud → becomes aggressive ✓
2. Aggressive enemy finds nearest enemy target ✓
3. **Enemy stands still and shoots** when has LOS ✗
4. **Enemy stands still completely** when no target ✗

## Technical Flow Analysis

### Normal Enemy AI Flow
```
_process_ai_state() → _process_[state]_state() → Complex tactical behaviors
```

### Aggression Override Flow (Buggy)
```
_process_ai_state() → _aggression.process_combat() → Static turret behavior
```

### Issue Location in enemy.gd
```gdscript
# Lines 1168-1169 in enemy.gd
if _aggression and _aggression.is_aggressive():  # [Issue #675] Aggression override
    _aggression.process_combat(delta, rotation_speed, shoot_cooldown, combat_move_speed); return
```

**Problem**: Early `return` statement completely bypasses all AI states when aggressive.

## Solution Strategy

### Option 1: Enhance AggressionComponent (Recommended)
- Add tactical movement behaviors to AggressionComponent
- Integrate with existing navigation and cover systems
- Maintain compatibility with existing code

### Option 2: Modify AI State Integration  
- Make aggression work within existing AI states
- Add aggression as a modifier rather than replacement
- Higher complexity but better integration

### Option 3: Hybrid Approach
- Use AggressionComponent for target selection and visual effects
- Delegate movement to existing AI state machine
- Balance of compatibility and functionality

## Recommended Fix: Enhanced AggressionComponent

### Key Changes Needed
1. **Dynamic Movement**: Replace static `velocity = Vector2.ZERO` with tactical movement
2. **State Integration**: Allow some AI state behaviors during aggression
3. **Flanking Behavior**: Add flanking logic for aggressive enemies
4. **Search Behavior**: Maintain searching when no targets available

### Implementation Plan
1. **Fix Static Movement**: Add tactical movement options during combat
2. **Add Flanking**: Implement flanking when engaging other enemies  
3. **Preserve Searching**: Allow searching behavior when no targets
4. **Maintain Cover**: Keep cover-seeking instincts during aggression
5. **Test Integration**: Ensure compatibility with existing systems

This will restore the intended tactical behavior while maintaining the gas grenade's core functionality.