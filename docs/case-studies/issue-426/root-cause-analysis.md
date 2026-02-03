# Root Cause Analysis - Issue #426

## Issue Summary

**Title:** fix враги не должны разбегаться от гранаты игрока, пока не знают о ней
(fix: enemies should not flee from player's grenade until they know about it)

## Expected Behavior

Enemies should only flee from grenades when they:
1. **SEE** the player throw the grenade, OR
2. **HEAR** the grenade land after being thrown (while grenade is in flight), OR
3. See a nearby enemy throwing a grenade

## Actual Behavior

Enemies flee when the player activates a grenade (pulls the pin), even if:
- They don't see the player
- They don't hear the player
- They're in IDLE state
- The grenade hasn't been thrown yet

## Timeline from Log File

| Time | Event | Issue |
|------|-------|-------|
| 16:01:29 | Player presses G to grab grenade | Normal |
| 16:01:30 | Timer activated (pin pulled) | Normal |
| **16:01:30** | **Enemy2, Enemy3, Enemy4 enter EVADING_GRENADE from IDLE** | **BUG** |
| 16:01:32 | Grenade actually thrown | Normal |

**Key evidence from log (lines 200-214):**
```
[16:01:30] [INFO] [GrenadeBase] Timer activated! 4.0 seconds until explosion
...
[16:01:30] [ENEMY] [Enemy2] GRENADE DANGER: Entering EVADING_GRENADE state from IDLE
[16:01:30] [ENEMY] [Enemy3] GRENADE DANGER: Entering EVADING_GRENADE state from IDLE
[16:01:30] [ENEMY] [Enemy4] GRENADE DANGER: Entering EVADING_GRENADE state from IDLE
```

The enemies were in **IDLE** state (not aware of player) but immediately reacted to the grenade.

## Root Cause

The bug is in `scripts/components/grenade_avoidance_component.gd` lines 87-91:

```gdscript
# Skip grenades that haven't been thrown yet (still held by player/enemy)
# Check if grenade has is_timer_active method (GrenadeBase)
if grenade.has_method("is_timer_active"):
    if not grenade.is_timer_active():
        continue
```

**The problem:** This check only verifies if the timer is active, but the timer is activated when the player **pulls the pin** (starts throwing motion), NOT when the grenade is actually thrown.

**Grenade lifecycle:**
1. `_ready()`: Grenade created, added to "grenades" group, `freeze = true`
2. `activate_timer()`: Timer starts, `_timer_active = true` ← **Comment says "hasn't been thrown yet" but this is BEFORE throw**
3. `throw_grenade*()`: `freeze = false`, grenade starts moving ← **This is the actual throw**

## Solution

Add a proper check for whether the grenade has been **thrown** (unfrozen), not just whether the timer is active.

### Changes Required

1. **Add `is_thrown()` method to `grenade_base.gd`**
   - Returns `true` when `freeze == false` (grenade is physically moving)

2. **Update `grenade_avoidance_component.gd`**
   - Change the check from `is_timer_active()` to `is_thrown()`
   - This ensures enemies only react to grenades that are actually in flight or on the ground

## Impact

- Enemies will no longer have "sixth sense" about grenades the player is holding
- More realistic and tactical gameplay
- Players can now hold grenades without alerting unaware enemies
