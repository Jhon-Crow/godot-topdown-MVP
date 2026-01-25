# Proposed Solutions: Enemy Grenade Throw Safety

## Solution Comparison Matrix

| Solution | Complexity | Performance | Effectiveness | Realism | Implementation Time |
|----------|-----------|-------------|---------------|---------|-------------------|
| 1. Simple Distance Check | Low | Excellent | High | Good | 15 minutes |
| 2. Dynamic Blast Radius Query | Medium | Good | Very High | Excellent | 45 minutes |
| 3. Trajectory Prediction | High | Moderate | Very High | Excellent | 2-3 hours |
| 4. Pre-Throw Repositioning | Medium | Good | High | Excellent | 1-2 hours |

## Recommended Solution: #2 (Dynamic Blast Radius Query)

### Why This Solution?

1. **Solves the core problem**: Prevents enemy self-damage
2. **Future-proof**: Works with any grenade type (frag, flashbang, future types)
3. **Low complexity**: Simple code changes, easy to maintain
4. **Performance**: Negligible impact (one distance check per throw)
5. **Flexible**: Can be enhanced later with more sophisticated checks

### Implementation Details

#### Step 1: Add Grenade Blast Radius Query Method

Add to `scripts/objects/enemy.gd`:

```gdscript
## Get the blast radius of the current grenade type.
## Returns the effect radius from the grenade scene, or a default value.
func _get_grenade_blast_radius() -> float:
	if grenade_scene == null:
		return 225.0  # Default frag grenade radius

	# Try to instantiate grenade temporarily to query its radius
	var temp_grenade = grenade_scene.instantiate()
	if temp_grenade == null:
		return 225.0  # Fallback

	var radius := 225.0  # Default

	# Check if grenade has effect_radius property
	if temp_grenade.get("effect_radius") != null:
		radius = temp_grenade.effect_radius

	# Clean up temporary instance
	temp_grenade.queue_free()

	return radius
```

#### Step 2: Add Safety Margin Constant

Add to `scripts/objects/enemy.gd` (near other grenade constants):

```gdscript
## Safety margin to add to blast radius for safe grenade throws.
## Enemy must be at least (blast_radius + safety_margin) pixels from target.
@export var grenade_safety_margin: float = 50.0
```

#### Step 3: Modify `try_throw_grenade()` Function

Update lines 5513-5517 in `scripts/objects/enemy.gd`:

```gdscript
# Check distance constraints
var distance := global_position.distance_to(target_position)

# Calculate minimum safe distance based on grenade blast radius
var blast_radius := _get_grenade_blast_radius()
var min_safe_distance := blast_radius + grenade_safety_margin

if distance < min_safe_distance:
	_log_grenade("Unsafe throw distance (%.0f < %.0f safe distance, blast=%.0f, margin=%.0f) - skipping throw" %
		[distance, min_safe_distance, blast_radius, grenade_safety_margin])
	return false

if distance > grenade_max_throw_distance:
	# Clamp to max distance
	var direction := (target_position - global_position).normalized()
	target_position = global_position + direction * grenade_max_throw_distance
	distance = grenade_max_throw_distance
```

#### Step 4: Update `grenade_min_throw_distance` Default

Change line 177 in `scripts/objects/enemy.gd`:

```gdscript
# OLD:
@export var grenade_min_throw_distance: float = 150.0

# NEW:
@export var grenade_min_throw_distance: float = 275.0  # Default frag radius (225) + margin (50)
```

### Code Changes Summary

**Files Modified:** 1 file (`scripts/objects/enemy.gd`)
- Add 1 new method: `_get_grenade_blast_radius()` (~15 lines)
- Add 1 new constant: `grenade_safety_margin` (1 line)
- Modify 1 method: `try_throw_grenade()` safety check (~8 lines changed)
- Update 1 constant: `grenade_min_throw_distance` default value (1 line)

**Total Lines Changed:** ~25 lines
**Risk Level:** Low (only adds safety checks, doesn't change core logic)

### Advantages

1. **Type-Agnostic**: Works with frag grenades (225px radius) and flashbang grenades (400px radius)
2. **Configurable**: `grenade_safety_margin` can be tweaked per enemy or difficulty level
3. **Backward Compatible**: Existing grenade triggers and logic unchanged
4. **Debuggable**: Detailed logging shows exact distances and calculations
5. **Testable**: Easy to write unit tests for safety checks

### Disadvantages

1. **Instantiation Cost**: Creates temporary grenade instance to query radius
   - **Mitigation**: Cache the radius value after first query
2. **Doesn't Account for Movement**: Enemy/player may move during grenade flight
   - **Acceptable**: Impact grenades explode quickly, minimal movement occurs
3. **Doesn't Account for Bouncing**: Grenade may bounce closer to enemy
   - **Acceptable**: Safety margin provides buffer for physics variations

### Edge Cases Handled

1. **Null grenade_scene**: Returns default 225.0 radius
2. **Grenade without effect_radius property**: Returns default 225.0
3. **Distance exactly equal to min_safe_distance**: Allowed (>= check)
4. **Clamped max distance throws**: Still validates safety after clamping

### Testing Strategy

1. **Unit Test**: Verify `_get_grenade_blast_radius()` returns correct values
2. **Integration Test**: Enemy at 200px throws grenade → blocked
3. **Integration Test**: Enemy at 300px throws grenade → allowed
4. **Manual Test**: Spawn enemy close to player, verify no self-damage grenades
5. **Trigger Tests**: Verify each of 6 triggers respects safety distance

## Alternative Solutions (Not Recommended)

### Solution 1: Simple Distance Check (Too Rigid)

**Pros:** Simplest implementation
**Cons:** Hard-coded values, not flexible for different grenade types

```gdscript
const MIN_SAFE_DISTANCE = 275.0
if distance < MIN_SAFE_DISTANCE:
    return false
```

**Why Not:** Doesn't adapt to different grenade types (flashbang has 400px radius)

### Solution 3: Trajectory Prediction (Overkill)

**Pros:** Most accurate safety calculation
**Cons:** Complex physics calculations, performance cost

```gdscript
var trajectory_points = _calculate_grenade_trajectory(target_position)
for point in trajectory_points:
    if global_position.distance_to(point) < blast_radius:
        return false  # Enemy in danger zone along trajectory
```

**Why Not:**
- Requires physics simulation
- Frag grenades explode on impact, not timed flight
- Complexity not justified for this use case

### Solution 4: Pre-Throw Repositioning (Changes Game Pace)

**Pros:** Most realistic AI behavior
**Cons:** Requires GOAP integration, changes enemy behavior significantly

```gdscript
# New GOAP action: RepositionForGrenadeThrow
if distance < min_safe_distance:
    _add_goap_goal("reposition_for_grenade", priority=HIGH)
    return false
```

**Why Not:**
- Changes game pacing (enemies delay attacks to reposition)
- Requires new GOAP action implementation
- May make enemies too cautious/predictable

## Implementation Plan

### Phase 1: Core Safety Implementation (Recommended Solution)
1. Add `_get_grenade_blast_radius()` method
2. Add `grenade_safety_margin` export variable
3. Update `try_throw_grenade()` safety check
4. Update `grenade_min_throw_distance` default
5. Add logging for debugging

### Phase 2: Testing & Validation
1. Write unit tests for safety checks
2. Write integration tests for each trigger
3. Manual testing in-game scenarios
4. Performance profiling (ensure no FPS impact)

### Phase 3: Documentation (Current)
1. ✅ Problem statement
2. ✅ Research findings
3. ✅ Technical analysis
4. ✅ Proposed solutions (this document)
5. Implementation log (to be created after implementation)

### Phase 4: Optional Enhancements (Future)
1. Cache blast radius value to avoid repeated instantiation
2. Add visual debugging (draw blast radius in editor)
3. Add post-throw retreat behavior
4. Consider player movement prediction

## Risk Assessment

### Low Risk Changes
- Adding safety check (only blocks unsafe throws)
- Adding logging (no gameplay impact)
- Increasing minimum throw distance (makes enemies safer)

### No Risk
- Reading grenade properties (read-only query)
- Adding export variables (configurable via editor)

### Potential Issues
- **Performance**: Instantiating grenade per throw check
  - **Impact**: Minimal (grenades thrown every 15+ seconds)
  - **Mitigation**: Cache radius value after first query

- **False Positives**: May block valid throws near max safety margin
  - **Impact**: Minor (enemy skips one throw, tries again later)
  - **Mitigation**: Tune `grenade_safety_margin` based on playtesting

## Success Metrics

1. **Primary**: Enemy never takes damage from own grenade
2. **Secondary**: Enemy still throws grenades at appropriate distances (>275px)
3. **Tertiary**: No performance degradation (<1ms per throw check)
4. **Quaternary**: Logs show safety checks working correctly

## Rollback Plan

If issues arise:
1. Revert `try_throw_grenade()` changes
2. Restore original `grenade_min_throw_distance = 150.0`
3. Remove `_get_grenade_blast_radius()` method
4. Keep documentation for future reference

## Conclusion

**Recommended Solution: #2 (Dynamic Blast Radius Query)**

This solution provides the best balance of:
- Effectiveness (solves the problem completely)
- Simplicity (minimal code changes)
- Flexibility (works with all grenade types)
- Performance (negligible overhead)
- Maintainability (clean, documented code)

Implementation time: ~30-45 minutes including testing.
