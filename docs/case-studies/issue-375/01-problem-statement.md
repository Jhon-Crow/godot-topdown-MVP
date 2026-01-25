# Problem Statement: Issue #375

## Title
Fix бросок наступательной гранаты врагом (Fix Enemy Offensive Grenade Throw)

## Original Requirement (Russian)
враг должен кидать гранату, взрывающуюся от столкновения так, чтобы не попасть в радиус поражения.

## Translation
The enemy should throw a grenade that explodes on collision in such a way as not to get into the damage radius.

## Problem Analysis

### Current Behavior
Currently, enemies can throw frag grenades (offensive grenades that explode on impact) at the player, but the grenade throwing algorithm does not account for the grenade's blast radius. This can lead to the following issues:

1. **Self-damage**: Enemies may throw grenades too close to themselves, resulting in self-damage or death when the grenade explodes on impact.
2. **Poor tactical behavior**: The AI does not ensure it is at a safe distance from the explosion before throwing.
3. **Unrealistic behavior**: In real combat scenarios, a soldier throwing an offensive grenade would always ensure they are outside the blast radius before throwing.

### Frag Grenade Characteristics
Based on the code analysis:
- **Explosion Trigger**: Impact-based (no timer) - explodes when hitting walls, enemies, or ground
- **Blast Radius**: 225 pixels (450px diameter)
- **Damage**: Flat 99 damage to all entities within blast radius (no distance scaling)
- **Line of Sight**: Damage requires direct line of sight
- **Shrapnel**: Spawns 4 pieces with 20° spread deviation

### Enemy Grenade Throwing Mechanics
From `scripts/objects/enemy.gd`:
- **Throw Distance Constraints**:
  - Minimum: 150 pixels (prevents point-blank throws)
  - Maximum: 600 pixels (clamps beyond max range)
- **Throw Inaccuracy**: ±0.15 radians (±8.6°)
- **Throw Delay**: 0.4 seconds (animation telegraph)
- **Cooldown**: 15 seconds between throws
- **Path Check**: Allows arcs over obstacles (60% distance threshold)

### The Core Issue
**The minimum throw distance (150px) is LESS than the blast radius (225px)**

This means:
- An enemy standing at 150-224 pixels from the target can throw a grenade that will damage itself
- The current implementation does NOT check if the enemy will be in the blast radius after the grenade explodes
- The enemy does not consider:
  - Its current position relative to the explosion point
  - The grenade's trajectory and where it will land/explode
  - Whether it has time to move away from the blast radius

### Risk Scenarios

1. **Static Throw**: Enemy throws grenade while standing still at distance < 225px
2. **Close Combat**: Enemy throws during pursuit at close range
3. **Trigger 2 (Pursuit)**: Targets 50% distance between enemy and player - if player is close, this puts grenade very close to enemy
4. **Trigger 4 (Sound)**: Targets sound source location - could be close to enemy
5. **Trigger 6 (Desperation)**: Low health enemy throws without constraints - most dangerous

## Expected Behavior

The enemy should:
1. **Verify safe distance**: Before throwing, ensure it is at least `blast_radius` pixels away from the target position
2. **Calculate landing position**: Predict where the grenade will land/explode
3. **Check self-safety**: Ensure the enemy won't be within the blast radius when the grenade explodes
4. **Tactical positioning**: Ideally, position itself at safe distance before attempting throw
5. **Cancel unsafe throws**: If conditions aren't met, skip the throw or reposition first

## Success Criteria

The solution should:
1. Prevent enemies from throwing grenades that would damage themselves
2. Maintain the existing trigger system (6 grenade triggers)
3. Preserve tactical behavior and game balance
4. Add minimal computational overhead
5. Be compatible with existing grenade physics and damage system
6. Include proper logging for debugging
