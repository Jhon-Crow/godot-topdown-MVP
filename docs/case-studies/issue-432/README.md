# Case Study: Issue #432 - Shell Casings React to Explosions

## Issue Summary

**Issue**: [#432](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/432)
**Title**: гильзы на полу должны реагировать на взрывы (Shell casings on the floor should react to explosions)
**Author**: Jhon-Crow
**Status**: In Progress

## Requirements

The issue describes three requirements for shell casing behavior:

1. **Lethal blast zone**: Shell casings on the floor should scatter/fly away when they are within the lethal blast zone of an explosion.

2. **Proximity effect**: If casings are close to the lethal blast zone or close to the epicenter of a non-lethal explosion, they should move slightly (even weaker than when pushed by player/enemy).

3. **Multi-source compatibility**: This behavior should work with grenades from both the player and enemy.

## Timeline

| Date | Event |
|------|-------|
| 2026-02-03 | Issue created |
| 2026-02-03 | Implementation started |
| 2026-02-03 | Initial PR #434 opened |
| 2026-02-03 14:58 | User feedback #1: "grenades fly infinitely and don't explode" |
| 2026-02-03 17:51 | Investigation #1: Merged main branch to include latest fixes |
| 2026-02-03 18:06 | User feedback #2: Problem persists after rebuild |
| 2026-02-03 | Deep investigation: Identified C#/GDScript interop issue in exports |
| 2026-02-03 | Fix attempt #1: Added freeze state detection to auto-activate grenade logic |
| 2026-02-03 18:17 | User feedback #3: Problem persists - GDScript `_physics_process` not running |
| 2026-02-03 | Root cause confirmed: GDScript not executing at all in exported builds |
| 2026-02-03 | Fix #2: Created C# GrenadeTimer component for reliable explosion handling |

## User Feedback Investigation

### Bug Report
User reported: "гранаты теперь летят бесконечно и не взрываются" (grenades now fly infinitely and don't explode)

### Analysis of Game Log (`logs/game_log_20260203_180528.txt`)

**Key observations:**
1. Grenades are being thrown (log entries show "Grenade thrown!" at multiple timestamps)
2. NO subsequent grenade lifecycle logs appear:
   - Missing: `[GrenadeBase] Grenade created at...`
   - Missing: `[FragGrenade] Pin pulled...`
   - Missing: `[GrenadeBase] Grenade landed at...`
   - Missing: `[FragGrenade] Impact detected - exploding immediately!`
   - Missing: `[GrenadeBase] EXPLODED at...`

**Root cause investigation:**
The Issue #432 changes (adding casing scatter to explosions) cannot cause grenades to not explode because:
1. `casing.gd` change: Only adds casing to a group - does not affect grenade logic
2. `grenade_base.gd` change: Adds `_scatter_casings()` method - only called AFTER explosion
3. `frag_grenade.gd`/`flashbang_grenade.gd` changes: Call `_scatter_casings()` inside `_on_explode()` - only executes after explosion

**Alternative hypotheses:**
1. **Build version mismatch**: User may have been testing an older exported build
2. **Missing branch synchronization**: Branch was missing commits from main:
   - Issue #428 fix (grenade targeting physics compensation)
   - Issue #438 fix (enemies getting stuck in casings)

**Initial Resolution Attempt:**
Merged main branch to include all recent fixes. User reported problem persisted.

### Second Investigation (User Feedback #2)

**Analysis of Game Log (`logs/game_log_20260203_210514.txt`):**

After the user rebuilt with the merged branch, the same issue persisted. Deep analysis revealed:

1. **C# logs present**: `[Player.Grenade.Simple] Grenade thrown!` appears at 21:05:52
2. **GDScript logs missing**: No corresponding `[GrenadeBase] Simple mode throw!` or `[FragGrenade] Grenade thrown (simple mode)` logs

**Root Cause Identified:**
The C# code in `Player.cs` calls GDScript methods on the grenade object:
```csharp
_activeGrenade.Call("throw_grenade_simple", throwDirection, throwSpeed);
_activeGrenade.Call("activate_timer");
```

However, in the exported build, these `Call()` invocations appear to fail silently. The C# code has a fallback path that sets velocity directly:
```csharp
_activeGrenade.LinearVelocity = throwDirection * throwSpeed;
_activeGrenade.Freeze = false;
```

This makes the grenade visually fly correctly, but:
1. `_timer_active` is never set to `true` (for FlashbangGrenade)
2. `_is_thrown` is never set to `true` (for FragGrenade)
3. Therefore, explosion logic never triggers!

**Why this happens:**
Possible C#/GDScript interop issues in Godot 4.3 export builds where `HasMethod()` returns `true` but `Call()` fails silently, or method signature matching fails.

**Fix Applied:**
Added freeze state detection in `_physics_process()` to detect when the grenade is released by external code:

1. **grenade_base.gd**: Auto-activate timer when freeze changes from `true` to `false`
2. **frag_grenade.gd**: Auto-enable impact detection when freeze changes

This ensures grenades will explode even if GDScript methods are not called successfully from C#.

### Third Investigation (User Feedback #3)

**Analysis of Game Logs (`logs/game_log_20260203_211515.txt`, `logs/game_log_20260203_211643.txt`):**

After applying the freeze state detection fix, the problem still persisted. This confirmed that **the GDScript `_physics_process()` function itself was not being called** - meaning the entire GDScript wasn't running in the exported build.

**Key Evidence:**
1. C# logs present: `[Player.Grenade.Simple] Grenade thrown!`
2. NO GDScript logs of any kind:
   - Missing: `[GrenadeBase] Grenade created at...` (from `_ready()`)
   - Missing: `[GrenadeBase] CCD enabled...` (from `_ready()`)
   - Missing: `[GrenadeBase] Detected unfreeze...` (from our new `_physics_process()` fix)
   - Missing: `[GrenadeTimer] Timer activated!` (from GDScript timer)

This proves that the GDScript attached to grenade scenes is simply not executing in the exported build - a known issue with Godot 4 C#/GDScript mixed projects.

**Final Solution: C# GrenadeTimer Component**

Since GDScript cannot be relied upon in exported builds, we created a pure C# solution:

1. **`Scripts/Projectiles/GrenadeTimer.cs`**: New C# component that:
   - Handles timer-based explosion (for Flashbang grenades)
   - Handles impact-based explosion (for Frag grenades via landing detection and `BodyEntered` signal)
   - Applies explosion damage and effects
   - Spawns shrapnel (for Frag)
   - Scatters shell casings

2. **`Scripts/Characters/Player.cs`**: Modified to:
   - Add `GrenadeTimer` component to each grenade when created
   - Call `GrenadeTimer.ActivateTimer()` when pin is pulled
   - Call `GrenadeTimer.MarkAsThrown()` when grenade is released

This C# component works independently of the GDScript, ensuring grenades will always explode regardless of whether the GDScript is executing.

## Technical Analysis

### Current Implementation

#### Shell Casings (`scripts/effects/casing.gd`)

- **Type**: RigidBody2D
- **Physics**: gravity_scale = 0.0 (top-down game)
- **Key properties**:
  - Linear damping: 3.0
  - Angular damping: 5.0
  - Auto-land after 2.0 seconds
  - Collision layer 64 (layer 7)
- **Existing method**: `receive_kick(impulse: Vector2)` - Already handles being pushed by player/enemy
- **State tracking**: `_has_landed`, `_is_time_frozen`

#### Grenade System

**FragGrenade (`scripts/projectiles/frag_grenade.gd`)**:
- `effect_radius`: 225.0 pixels (lethal blast zone)
- `explosion_damage`: 99 (flat damage to all in zone)
- Explodes on impact (not timer-based)
- Spawns 4 shrapnel pieces

**FlashbangGrenade (`scripts/projectiles/flashbang_grenade.gd`)**:
- `effect_radius`: 400.0 pixels
- No damage (stun/blind effects only)
- Timer-based (4 second fuse)

### Proposed Solution

The solution leverages the existing `receive_kick()` method in the casing script. During grenade explosion (`_on_explode()`), we need to:

1. Find all casings in the "casings" group (need to add this group)
2. Calculate distance from explosion center to each casing
3. Apply impulse based on:
   - **Inside lethal zone**: Strong impulse (scatter effect)
   - **Just outside lethal zone**: Weak impulse (subtle push)
   - **Far away**: No effect

### Implementation Details

#### Force Calculations

Based on existing casing physics:
- Player kick force: `velocity.length() * CASING_PUSH_FORCE / 100.0` (from `player.gd`)
- CASING_PUSH_FORCE constant: ~3.0 (from player.gd line 60)
- Typical player velocity: 200-300 px/s
- Resulting typical kick: ~6-9 impulse units

For explosion effects, we'll use:
- **Lethal zone (inside radius)**: 30-60 impulse units (strong scatter)
- **Proximity zone (1.0-1.5x radius)**: 5-15 impulse units (weaker than player kick)

#### Direction Calculation

Impulse direction = normalized vector from explosion center to casing position

#### Inverse-square Falloff

Within lethal zone, closer casings receive stronger impulse:
```
impulse_strength = base_strength * (1.0 - (distance / effect_radius))^0.5
```

## Files Modified

### GDScript Changes (Issue #432 Feature - Casing Scatter)
1. `scripts/effects/casing.gd` - Add to "casings" group
2. `scripts/projectiles/grenade_base.gd` - Add shared method for casing scattering + freeze detection
3. `scripts/projectiles/frag_grenade.gd` - Call casing scatter on explosion + freeze detection
4. `scripts/projectiles/flashbang_grenade.gd` - Call casing scatter on explosion

### C# Changes (Grenade Explosion Fix)
5. `Scripts/Projectiles/GrenadeTimer.cs` - **NEW** - Reliable C# grenade timer and explosion handler
6. `Scripts/Characters/Player.cs` - Add GrenadeTimer component to grenades, call its methods

## Test Coverage

New tests to be added:
- `test_casing_explosion_reaction.gd` - Unit tests for casing scatter behavior

Test scenarios:
1. Casing inside lethal zone receives strong impulse
2. Casing at proximity zone receives weak impulse
3. Casing far away receives no impulse
4. Landed casings become mobile again after explosion
5. Time-frozen casings don't react to explosions
6. Works with both FragGrenade and FlashbangGrenade

## Related Issues

- Issue #392: Casings pushing player at spawn (fixed with collision delay)
- Issue #424: Reduce casing push force (fixed with 2.5x reduction)
- Issue #375: Enemy grenade safe distance

## References

- [Godot RigidBody2D Documentation](https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html)
- [Godot Physics - Impulse vs Force](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html)
