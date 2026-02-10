# Issue 729: Gas Grenade - Enemy Movement Analysis

## Issue Description
**Problem**: Агрессивные враги не перемещаются и не обходят с флангов других врагов. даже в searching состоянии стоят на месте.

**Translation**: Aggressive enemies don't move and don't flank other enemies, even in searching state they stand still.

## Log Files Referenced in Issue
- game_log_20260210_203330.txt
- game_log_20260210_203352.txt  
- game_log_20260210_203407.txt
- game_log_20260210_203616.txt

## Initial Code Analysis

### Gas Grenade System Analysis
1. **AggressionGasGrenade** (`scripts/projectiles/aggression_gas_grenade.gd`):
   - Releases gas cloud after 4 seconds
   - Cloud radius: 300px (larger than frag grenade's 225px)
   - Aggression duration: 10 seconds
   - Cloud duration: 20 seconds

2. **AggressionCloud** (`scripts/effects/aggression_cloud.gd`):
   - Spawns Area2D with radius 300px
   - Applies aggression effect to enemies every 0.5 seconds
   - Uses StatusEffectsManager to apply 10-second aggression

3. **AggressionComponent** (`scripts/components/aggression_component.gd`):
   - Manages aggressive state per enemy
   - `process_combat()` handles aggressive enemy behavior
   - Finds nearest enemy target and attacks/moves toward them

4. **StatusEffectsManager** (`scripts/autoload/status_effects_manager.gd`):
   - Tracks aggression duration per enemy
   - Applies 10-second aggression effect via `apply_aggression()`

### Enemy AI System Analysis
1. **Enemy** (`scripts/objects/enemy.gd`):
   - Lines 1168-1169: Priority check for aggression
   ```gdscript
   if _aggression and _aggression.is_aggressive():  # [Issue #675] Aggression override
       _aggression.process_combat(delta, rotation_speed, shoot_cooldown, combat_move_speed); return
   ```

2. **AI States** (from enemy.gd enum):
   - AGGRESSIVE state doesn't exist (states: IDLE, COMBAT, SEEKING_COVER, IN_COVER, FLANKING, SUPPRESSED, RETREATING, PURSUING, ASSAULT, SEARCHING, EVADING_GRENADE)

3. **Key Issue**: When aggression is active, the enemy AI processing is completely overridden by `AggressionComponent.process_combat()` which returns early, preventing normal state processing.

## Root Cause Hypothesis

**Problem Location**: `AggressionComponent.process_combat()` method appears to have movement issues.

**Analysis of AggressionComponent.process_combat()**:
1. Line 48: `if _has_los(_target):` - enemies stand still if they have LOS
2. Line 50: `else:` - enemies move only if NO LOS to target
3. Line 47: Shooting logic looks correct
4. **Movement Logic Issue**: Line 48 sets velocity to ZERO when enemy has LOS to target

**Key Finding**: When aggressive enemies have line of sight to their target, they completely stop moving (`velocity = Vector2.ZERO` on line 48). This explains why "агрессивные враги не перемещаются" (aggressive enemies don't move).

## Missing Behaviors in AggressionComponent
1. **No flanking behavior**: Aggressive enemies should still attempt to flank other enemies
2. **No searching behavior**: When no target found, enemies should search
3. **No tactical movement**: Should use cover, advance, retreat behaviors
4. **Static combat**: Only stands still and shoots when has LOS

## Analysis Files Created
- `analysis/gas_grenade_flow.md` - Flow analysis
- `analysis/aggression_component_issues.md` - Component issues  
- `analysis/enemy_ai_states.md` - State analysis

## Next Steps
1. Research gas grenade mechanics in other games
2. Fix AggressionComponent movement logic  
3. Add flanking/searching behaviors to aggressive enemies
4. Test with multiple enemies
5. Verify gas grenade visual/audio effects work