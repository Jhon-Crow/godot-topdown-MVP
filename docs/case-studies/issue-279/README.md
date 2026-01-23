# Case Study: Issue #279 - Fix Offensive Grenade (Frag Grenade) Wall Impact Detection

## Issue Summary

**Issue:** [#279](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/279)
**Title:** fix наступательная граната (Fix offensive grenade)
**Description:** "наступательная граната должна взрываться сразу при столкновении со стеной." (The offensive grenade should explode immediately upon collision with a wall)

## Background Research

### Real-World Grenade Types

Based on military documentation and research:

**Offensive Grenades (Наступательная граната):**
- Work by concussive blast/overpressure effect
- Do NOT produce shrapnel (or minimal shrapnel)
- Can be thrown with minimal cover as the danger radius is smaller
- Used when forces are advancing/pushing forward
- Examples: M111 Offensive Hand Grenade (US), RG42 (Soviet/Russian)

**Defensive Grenades (Оборонительная граната):**
- Work by fragmentation (shrapnel)
- Have thick metal casing that shatters into deadly fragments
- Must be thrown from behind cover due to larger danger radius
- Examples: M67 (US), RGD-5 (Soviet/Russian)

**Sources:**
- [What's the difference between offensive and defensive hand grenades? - Technology Org](https://www.technology.org/2019/09/26/whats-the-difference-between-offensive-and-defensive-hand-grenades/)
- [FM 3-23.30 - Types of Hand Grenades](https://www.intpyrosoc.org/wp-content/uploads/2015/10/TYPES-OF-HAND-GRENADES.pdf)
- [United States hand grenades - Wikipedia](https://en.wikipedia.org/wiki/United_states_hand_grenades)

### Game Implementation Context

In this codebase, the **"Frag Grenade"** is implemented as the **offensive grenade** (наступательная граната), despite the somewhat confusing naming. Evidence:

1. `scripts/ui/armory_menu.gd:36` - Frag Grenade is labeled as "Offensive grenade"
2. `scripts/projectiles/frag_grenade.gd:3` - Comments say "Offensive (frag) grenade"
3. Issue #261 references: "наступательная граната должна наносить такой же урон игроку как и врагам" (offensive grenade should deal same damage to player as enemies)

**Note:** The naming is slightly confusing because real-world "frag grenades" are typically defensive grenades with fragmentation. However, in this game, the "Frag Grenade" combines features of both types (impact-triggered explosion + shrapnel), but is classified as "offensive" in the UI.

## Timeline of Events (from game_log_20260123_223601.txt)

### Test Session: 2026-01-23 22:36:01

1. **22:36:01** - Game started, GrenadeManager loaded both Flashbang and FragGrenade scenes
2. **22:36:07** - User switched from Flashbang to Frag Grenade in Armory menu
3. **22:36:12-22:38:10** - Multiple frag grenades thrown during gameplay

### Grenade Explosion Pattern Analysis

All frag grenade explosions followed this pattern:
```
[22:36:14] [INFO] [GrenadeBase] Grenade landed at (808.9091, 594.5131)
[22:36:14] [INFO] [FragGrenade] Impact detected - exploding immediately!
[22:36:14] [INFO] [GrenadeBase] EXPLODED at (808.9091, 594.5131)!
```

**Key Observation:** The log shows grenades exploding after "Grenade landed" events, which occur when the grenade **comes to rest on the ground** (velocity drops below threshold). There are **ZERO** instances of wall collision sounds (`play_grenade_wall_hit`) in the entire 5,415-line log file.

## Root Cause Analysis

### Investigation Steps

1. **Code Review of frag_grenade.gd:**
   - Lines 121-128: `_on_body_entered` method exists and should detect wall impacts
   - Line 127: Checks `if body is StaticBody2D or body is TileMap` to trigger explosion
   - Implementation appears correct

2. **Code Review of grenade_base.gd:**
   - Line 113: Signal connection exists: `body_entered.connect(_on_body_entered)`
   - Line 94: Collision mask includes obstacles: `collision_mask = 4 | 2` (obstacles + enemies)
   - Implementation appears correct

3. **Log Analysis:**
   - Search for "grenade_wall_hit": 0 results
   - Search for "body_entered": 0 results
   - **Conclusion:** The `_on_body_entered` signal is NEVER firing

4. **Research into Godot RigidBody2D Behavior:**
   - Discovered that RigidBody2D requires `contact_monitor = true` for collision signals to work
   - Must also set `max_contacts_reported` to a value > 0
   - **Sources:**
     - [Godot Forum: RigidBody2D body_entered signal not working](https://forum.godotengine.org/t/solved-rigidbody2d-body-entered-signal-does-not-work/21902)
     - [Godot Forum: body_entered signal not firing for static bodies](https://godotforums.org/d/31564-body-enteredbody-signal-not-firing-for-static-bodies)

5. **Verification:**
   - Checked `grenade_base.gd`: No `contact_monitor` property set ❌
   - Checked `FragGrenade.tscn`: No `contact_monitor` property set ❌

### Root Cause Identified

**The grenade's `body_entered` signal never fires because `contact_monitor` is not enabled.**

From Godot documentation:
> If true, the RigidBody2D will emit signals when it collides with another body.
> Note: By default the maximum contacts reported is one contact per frame. See max_contacts_reported to increase it.

**Current Behavior:**
- Grenades only explode when they come to rest (landing detection via velocity check)
- Wall impacts do not trigger explosion because collision signals are not being emitted

**Expected Behavior:**
- Grenades should explode immediately when hitting walls (StaticBody2D/TileMap)
- Grenades should also explode when landing on ground

## Solution Design

### Fix Implementation

Add contact monitoring to `grenade_base.gd` in the `_ready()` function:

```gdscript
func _ready() -> void:
    # Set up collision
    collision_layer = 32  # Layer 6 (custom for grenades)
    collision_mask = 4 | 2  # obstacles + enemies (NOT player, to avoid collision when throwing)

    # Enable contact monitoring for body_entered signal
    contact_monitor = true
    max_contacts_reported = 4  # Track up to 4 simultaneous contacts

    # ... rest of existing code
```

**Why this works:**
- Enables the RigidBody2D's contact reporting system
- Allows `body_entered` signal to fire when colliding with StaticBody2D/TileMap
- The existing `_on_body_entered` override in frag_grenade.gd will then work correctly

### Impact Analysis

**Files Modified:**
- `scripts/projectiles/grenade_base.gd` - Add contact monitoring

**Affected Grenades:**
- Frag Grenade (offensive grenade) - **PRIMARY FIX**
- Flashbang Grenade - No change in behavior (uses timer, not impact detection)

**Test Coverage:**
- Existing unit tests in `tests/unit/test_frag_grenade.gd` cover explosion mechanics
- Tests use mock objects, so don't test actual Godot physics/signals
- Manual testing required to verify wall impact detection

## Testing Plan

### Unit Tests
- Existing tests continue to pass (mock-based, don't test physics)
- Consider adding integration tests for collision detection

### Manual Testing
1. Launch game in Godot editor
2. Select Frag Grenade in Armory menu
3. Throw grenade directly at a wall
4. **Expected:** Grenade explodes immediately on wall impact
5. **Expected:** Hear wall collision sound followed by explosion
6. Verify logs show wall collision events before explosion

### Regression Testing
- Ensure flashbang grenades still work (timer-based explosion)
- Ensure frag grenades still explode when landing on ground
- Ensure collision with enemies doesn't trigger explosion (only walls)

## Related Issues and Context

- **Issue #261:** Offensive grenade damage to player (already fixed)
- **Issue #256:** Velocity-based grenade throwing (implemented in PR #260)
- **Issue #212:** Related to grenade mechanics improvements

## Lessons Learned

1. **Godot RigidBody2D Requirements:** Always enable `contact_monitor` when using collision signals
2. **Log Analysis:** Absence of expected log messages is a strong indicator of missing functionality
3. **Naming Conventions:** "Frag Grenade" vs "Offensive Grenade" terminology could be clearer
4. **Testing:** Physics-based features need integration tests, not just unit tests

## Implementation Checklist

- [x] Research real-world offensive vs defensive grenades
- [x] Analyze game logs to identify behavior pattern
- [x] Review existing code implementation
- [x] Identify root cause (missing contact_monitor)
- [ ] Implement fix in grenade_base.gd
- [ ] Add detailed logging to track wall impacts
- [ ] Manual test in game
- [ ] Verify logs show wall collision events
- [ ] Run local CI checks
- [ ] Update PR with findings and fix
