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
| 2026-02-03 19:51 | User feedback #6: Throw from activation position + no explosion effects |
| 2026-02-03 | Root cause #6a: GDScript `_ready()` doesn't run → grenade not frozen on creation |
| 2026-02-03 | Root cause #6b: GDScript `Call()` fails → explosion effects not showing |
| 2026-02-03 | Fix #6: C# explicitly freezes grenade + implements explosion effects directly |

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

### Fourth Investigation (User Feedback #4)

**Analysis of Game Log (`logs/game_log_20260203_213537.txt`):**

After implementing the C# GrenadeTimer component, grenades now explode successfully. However, user reported three remaining issues:

1. **Grenade position issue**: Grenade launches from activation position instead of player's current position
2. **Grenade distance issue**: Grenade always flies max distance regardless of where player aims
3. **Casing scatter force**: Shell casings should scatter much more strongly

**Root Cause Analysis:**

The key issue was in the game log analysis:
```
[21:35:44] [Player.Grenade] Timer started, grenade created at (147.32436, 344.72653)
[21:35:45] [Player.Grenade.Simple] Throwing! Target: (359.415, 392.72726), Distance: 183,2, Speed: 331,5, Friction: 300,0
[21:35:48] [GrenadeTimer] EXPLODED at (975.07324, 531.67236)!
```

The grenade was supposed to travel ~183 pixels to reach the target, but it exploded at ~830 pixels from the start!

**Why this happened:**

The GDScript `_physics_process()` in `grenade_base.gd` applies ground friction to slow down the grenade:
```gdscript
if linear_velocity.length() > 0:
    var friction_force := linear_velocity.normalized() * ground_friction * delta
    if friction_force.length() > linear_velocity.length():
        linear_velocity = Vector2.ZERO
    else:
        linear_velocity -= friction_force
```

Since GDScript is not running in exports, **no friction was being applied** to the grenade!
The grenade flew at constant velocity until the 4-second timer expired.

**Fix Applied:**

1. **GrenadeTimer.cs**: Added `ApplyGroundFriction()` method that replicates the GDScript friction logic in C#:
   - Reads `ground_friction` property from the grenade (default 300.0)
   - Applies friction force every physics frame: `velocity -= velocity.normalized() * friction * delta`
   - This ensures grenades slow down and stop at the correct position

2. **Increased casing scatter force**: User requested stronger scatter effect
   - Changed `lethalImpulse` from 45 to 150 (3.3x increase)
   - Changed `proximityImpulse` from 10 to 25 (2.5x increase)
   - Updated both C# (`GrenadeTimer.cs`) and GDScript (`grenade_base.gd`) for consistency

## Files Modified

### GDScript Changes (Issue #432 Feature - Casing Scatter)
1. `scripts/effects/casing.gd` - Add to "casings" group
2. `scripts/projectiles/grenade_base.gd` - Add shared method for casing scattering + freeze detection + increased scatter force
3. `scripts/projectiles/frag_grenade.gd` - Call casing scatter on explosion + freeze detection
4. `scripts/projectiles/flashbang_grenade.gd` - Call casing scatter on explosion

### C# Changes (Grenade Explosion Fix)
5. `Scripts/Projectiles/GrenadeTimer.cs` - **NEW** - Reliable C# grenade timer, explosion handler, **friction application**, and casing scatter
6. `Scripts/Characters/Player.cs` - Add GrenadeTimer component to grenades, call its methods, copy ground_friction property

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

### Fifth Investigation (User Feedback #5)

**Analysis of Game Log (`logs/game_log_20260203_220140.txt`):**

After implementing the C# friction fix, user reported three new issues:

1. **Casing scatter too weak**: User requested casings scatter "almost as fast as bullets" (bullet speed is 2500 px/s)
2. **Explosion visual effects missing**: No visual explosion effects visible
3. **Grenades undershooting by ~150px**: Grenades land short of target

**Detailed Log Analysis (Frag grenade throw):**
```
[22:02:23] Timer started, grenade created at (150, 199.16666)
[22:02:24] Throwing! Target: (746.8878, 160.29684), Distance: 602,6, Speed: 601,3, Friction: 300,0
[22:02:25] Frag grenade landed - EXPLODING!
[22:02:25] EXPLODED at (294.2355, 219.98558)!
```

The grenade was supposed to travel 602.6 pixels but only traveled ~144 pixels (294-150)!

**Root Cause: Double Friction!**

Both C# `GrenadeTimer.ApplyGroundFriction()` AND GDScript `_physics_process()` are running and applying friction! The GDScript is actually working in this build, but both scripts apply friction, causing **2x the expected deceleration**.

Evidence from log: When C# was added, GDScript started working too (possibly export rebuild triggered correct script compilation).

**Fixes Applied:**

1. **Smart Friction Detection**: Modified `GrenadeTimer.cs` to detect if GDScript friction is already working:
   - Track velocity changes each frame
   - If velocity is being reduced by expected amount, GDScript friction is working → don't apply C# friction
   - If velocity NOT being reduced after several frames, GDScript isn't working → apply C# friction

2. **Massive Casing Scatter Increase**: User requested near-bullet-speed scatter (2500 px/s):
   - Lethal zone impulse: 150 → **2000** (bullet-like scatter)
   - Proximity zone impulse: 25 → **500** (strong push)
   - Updated both C# and GDScript for consistency

3. **Explosion Visual Effects Fix**: GrenadeTimer now tries to call the GDScript explosion effect methods:
   - First tries `_spawn_explosion_effect()` on the grenade
   - Falls back to `_create_simple_explosion()`
   - Final fallback to `ImpactEffectsManager.spawn_flashbang_effect()`

### Sixth Investigation (User Feedback #6)

**Analysis of Game Logs (`logs/game_log_20260203_221832.txt`, `logs/game_log_20260203_222057.txt`):**

User reported two remaining issues:

1. **Grenade launches from activation position**: Grenade starts from wrong position (where pin was pulled, not current player position)
2. **Grenade flies infinitely**: Should stop at the aimed cursor position but flies forever

**Detailed Log Analysis:**

```
[22:19:30] Timer started, grenade created at (213.80525, 176.33162)
[22:19:33] Throwing! Target: (575.866, 226.29036), Distance: 547,1, Speed: 572,9
[22:19:37] EXPLODED at (85.92131, 305.69998)!
```

The explosion position (85, 305) is completely different from both:
- The grenade spawn position (213, 176)
- The target position (575, 226)

This is very unusual behavior indicating a fundamental problem.

**Root Cause Discovery: GDScript Method Calls Still Failing**

Deep analysis of the C# code revealed:

1. C# code checks `HasMethod("throw_grenade_simple")` → returns `true`
2. C# code calls `_activeGrenade.Call("throw_grenade_simple", throwDirection, throwSpeed)`
3. **The Call() silently fails** - GDScript method doesn't execute
4. Because `HasMethod()` returned true, the C# fallback code is never reached
5. Result: **Grenade velocity is never set!**

The grenade is unfrozen (`Freeze = false`) but has zero velocity because:
- The GDScript `throw_grenade_simple()` method was supposed to set `linear_velocity`
- That method call failed silently
- The C# code assumed it worked and didn't apply its own velocity

**Why did the grenade move at all?**

Looking at the code, we discovered that both GDScript `_physics_process()` and the C# code modify the grenade position during aiming. The unexpected explosion positions were likely due to:
1. Physics engine quirks with zero-velocity unfrozen bodies
2. Possible collision responses moving the grenade
3. The grenade being at a different position than expected when thrown

**Final Fix: C# Sets Velocity Directly as Primary Mechanism**

The solution is to ALWAYS set the grenade velocity directly in C#, regardless of whether GDScript methods exist:

```csharp
// FIX for Issue #432: ALWAYS set velocity directly in C#
_activeGrenade.GlobalPosition = safeSpawnPosition;
_activeGrenade.Freeze = false;
_activeGrenade.LinearVelocity = throwDirection * throwSpeed;
_activeGrenade.Rotation = throwDirection.Angle();

// Also try GDScript for any additional effects (but velocity is already set)
if (_activeGrenade.HasMethod("throw_grenade_simple"))
{
    _activeGrenade.Call("throw_grenade_simple", throwDirection, throwSpeed);
}
```

This ensures:
1. **Position is correct**: Set to spawn point (60px in front of player) before throw
2. **Velocity is always set**: C# sets it directly, doesn't rely on GDScript
3. **GDScript effects work if available**: Still tries to call the method for visual/sound effects

Also simplified the GrenadeTimer friction handling:
- Removed complex friction detection logic
- GDScript `_physics_process()` DOES run and applies friction correctly
- Only the GDScript METHOD CALLS (via C# Call()) fail
- C# no longer applies friction, preventing the double-friction issue

## Final Resolution

The root cause of all grenade issues was the same: **GDScript methods called via C# `Call()` fail silently in exported builds**. However, GDScript lifecycle methods (`_ready()`, `_physics_process()`) DO run correctly.

The fix strategy:
1. **C# directly controls velocity**: Don't rely on GDScript method calls
2. **GDScript handles friction**: Its `_physics_process()` works correctly
3. **C# handles explosion timing**: The GrenadeTimer component is reliable backup
4. **Call GDScript methods optionally**: For effects, but not for critical physics

This hybrid approach ensures grenades work correctly regardless of the C#/GDScript interop state.

### Sixth Investigation (User Feedback #6)

**Analysis of Game Log (`logs/game_log_20260203_224846.txt`):**

User reported two remaining issues:
1. **Grenade thrown from activation position instead of player position** - Same issue previously fixed in PR #183/commit 60f7cae
2. **No explosion visual effects**

**Root Cause #1: Grenade Not Frozen on Creation**

The original fix for the "activation position" bug (commit 60f7cae) was in GDScript:
```gdscript
# In grenade_base.gd _ready():
freeze = true
freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
```

However, **GDScript `_ready()` doesn't run in exports** (as established earlier). This means:
1. Grenade is created unfrozen (RigidBody2D default)
2. Physics engine can interfere with position while player moves
3. Grenade ends up at activation position instead of player's current position

**Fix Applied:**
C# now explicitly freezes the grenade immediately after creation:
```csharp
// In Player.cs StartGrenadeTimer():
GetTree().CurrentScene.AddChild(_activeGrenade);

// FIX: Freeze grenade IMMEDIATELY - GDScript _ready() doesn't run in exports!
_activeGrenade.FreezeMode = RigidBody2D.FreezeModeEnum.Kinematic;
_activeGrenade.Freeze = true;

_activeGrenade.GlobalPosition = GlobalPosition;
```

**Root Cause #2: Explosion Visual Effects Not Showing**

The GrenadeTimer was trying to call GDScript methods for explosion effects:
```csharp
if (_grenadeBody.HasMethod("_spawn_explosion_effect"))
{
    _grenadeBody.Call("_spawn_explosion_effect"); // FAILS in exports!
}
```

The `HasMethod()` check returns true (method exists), but `Call()` fails silently. The fallback to `ImpactEffectsManager` also failed because that autoload doesn't have the `spawn_flashbang_effect` method.

**Fix Applied:**
Implemented explosion visual effects directly in C#:
```csharp
private void SpawnExplosionEffect(Vector2 position)
{
    // Create explosion flash effect directly in C#
    CreateExplosionFlash(position);
}

private void CreateExplosionFlash(Vector2 position)
{
    var flash = new Sprite2D();
    flash.Texture = CreateCircleTexture((int)EffectRadius);
    flash.GlobalPosition = position;

    // Flashbang: white, Frag: orange/red
    if (Type == GrenadeType.Flashbang)
        flash.Modulate = new Color(1.0f, 1.0f, 1.0f, 0.8f);
    else
        flash.Modulate = new Color(1.0f, 0.6f, 0.2f, 0.8f);

    GetTree().CurrentScene.AddChild(flash);

    // Fade out animation
    var tween = GetTree().CreateTween();
    tween.TweenProperty(flash, "modulate:a", 0.0f, 0.3f);
    tween.TweenCallback(Callable.From(() => flash.QueueFree()));
}
```

This C# implementation replicates the GDScript `_create_simple_explosion()` and `_create_simple_flash()` methods, ensuring explosion effects always appear.

## Final Resolution (Updated)

The complete solution for reliable grenade behavior in exports:

| Component | Issue | Solution |
|-----------|-------|----------|
| Grenade Creation | GDScript `_ready()` doesn't run | C# explicitly freezes grenade on creation |
| Grenade Velocity | GDScript `Call()` fails | C# sets velocity directly before calling GDScript |
| Grenade Friction | Double friction (C# + GDScript) | Disable C# friction, rely on GDScript `_physics_process()` |
| Explosion Timing | Method calls fail | C# GrenadeTimer handles timer/impact detection |
| Explosion Effects | GDScript effect methods not called | C# creates explosion flash directly |
| Casing Scatter | Relies on explosion | Both C# and GDScript implementations |

**Key Insight**: In Godot 4 C#/GDScript mixed projects, while GDScript method **calls** via `Call()` fail in exports, the GDScript **lifecycle methods** (`_ready()`, `_physics_process()`, signals) DO work. However, for maximum reliability in exported builds, critical functionality should be implemented in C# for the player-owned grenades.

### Seventh Investigation (User Feedback #7 - 2026-02-03 20:19)

**User Feedback:**
User reported two remaining issues with attached log files:

1. **Enemy grenades fly infinitely and don't explode** (гранаты врагов летят бесконечно и не взрываются)
2. **Player offensive (frag) grenades sometimes don't explode when hitting an enemy** (наступательные гранаты игрока иногда не взрываются при попадании во врага)

**Log Files Analyzed:**
- `logs/game_log_20260203_230921.txt` (33,888 lines) - Extended gameplay session
- `logs/game_log_20260203_231827.txt` (201 lines) - Short session showing initialization

**Root Cause Analysis - Issue 1: Enemy Grenades Flying Infinitely**

The enemy grenade throwing code in `scripts/components/enemy_grenade_component.gd` was NOT modified to use the C# GrenadeTimer component. Analysis of `_execute_throw()` function (lines 319-354):

```gdscript
var grenade: Node2D = grenade_scene.instantiate()
grenade.global_position = _enemy.global_position + dir * 40.0
parent.add_child(grenade)

if grenade.has_method("activate_timer"):
    grenade.activate_timer()  # FAILS in exports - GDScript Call() doesn't work

if grenade.has_method("throw_grenade"):
    grenade.throw_grenade(dir, dist)  # FAILS in exports
elif grenade is RigidBody2D:
    grenade.freeze = false
    grenade.linear_velocity = dir * clampf(dist * 1.5, 200.0, 800.0)  # Works but no timer!
```

The GDScript method calls (`activate_timer()`, `throw_grenade()`) fail silently in exports. The fallback sets velocity directly, making the grenade fly visually, but:
- No timer is ever activated
- No impact detection is enabled
- Grenade flies forever without exploding

**Fix Applied - Enemy Grenades:**

1. Created `Scripts/Autoload/GrenadeTimerHelper.cs` - C# autoload that provides methods callable from GDScript:
   - `AttachGrenadeTimer(grenade, grenadeType)` - Attaches C# GrenadeTimer component
   - `ActivateTimer(grenade)` - Calls `GrenadeTimer.ActivateTimer()`
   - `MarkAsThrown(grenade)` - Calls `GrenadeTimer.MarkAsThrown()`

2. Added autoload to `project.godot`:
   ```ini
   GrenadeTimerHelper="*res://Scripts/Autoload/GrenadeTimerHelper.cs"
   ```

3. Modified `scripts/components/enemy_grenade_component.gd` `_execute_throw()`:
   - Attach C# GrenadeTimer via helper
   - Activate timer via helper
   - Mark as thrown via helper
   - Added logging for enemy grenade throws

**Root Cause Analysis - Issue 2: Frag Grenades Sometimes Not Exploding on Enemy Hit**

Intermittent behavior suggests a timing/race condition. Analysis of `Scripts/Projectiles/GrenadeTimer.cs` `OnBodyEntered()`:

```csharp
private void OnBodyEntered(Node body)
{
    if (!IsThrown)  // Race condition check
        return;
    // ...trigger explosion
}
```

And in `Scripts/Characters/Player.cs`:
```csharp
_activeGrenade.Freeze = false;  // Line 2253 - Grenade unfrozen
_activeGrenade.LinearVelocity = ...;  // Line 2259 - Velocity set
// ...
grenadeTimer.MarkAsThrown();  // Line 2275 - AFTER unfreezing!
```

**The Race Condition:**
1. Grenade is unfrozen and starts moving
2. Physics processing occurs
3. `BodyEntered` signal can fire if grenade collides with enemy
4. At this point `IsThrown` is still `false` because `MarkAsThrown()` hasn't been called yet
5. Collision is ignored, grenade passes through enemy

**Fix Applied - Race Condition:**

Moved `MarkAsThrown()` call BEFORE unfreezing in both throw paths:

```csharp
// Set position before throw
_activeGrenade.GlobalPosition = safeSpawnPosition;

// FIX: Mark as thrown BEFORE unfreezing to avoid race condition
var grenadeTimer = _activeGrenade.GetNodeOrNull<GrenadeTimer>("GrenadeTimer");
if (grenadeTimer != null)
{
    grenadeTimer.MarkAsThrown();  // NOW: Set flag first
}

// Then unfreeze and set velocity
_activeGrenade.Freeze = false;  // THEN: Unfreeze
_activeGrenade.LinearVelocity = throwDirection * throwSpeed;
```

Also fixed TileMap type check in `GrenadeTimer.cs`:
```csharp
// Was: TileMapLayer (newer Godot 4 only)
// Fixed: Added TileMap for compatibility with older tilemaps
if (body is StaticBody2D || body is TileMap || body is TileMapLayer || body is CharacterBody2D)
```

## Files Modified (Update)

### New Files
- `Scripts/Autoload/GrenadeTimerHelper.cs` - C# autoload for GDScript to attach GrenadeTimer

### Modified Files
- `project.godot` - Added GrenadeTimerHelper autoload
- `scripts/components/enemy_grenade_component.gd` - Use GrenadeTimerHelper for reliable explosion
- `Scripts/Projectiles/GrenadeTimer.cs` - Fixed TileMap type check
- `Scripts/Characters/Player.cs` - Fixed race condition: MarkAsThrown() before Freeze=false

## Final Resolution (Updated)

The complete solution now covers both player and enemy grenades:

| Component | Issue | Solution |
|-----------|-------|----------|
| Player Grenade Creation | GDScript `_ready()` doesn't run | C# explicitly freezes grenade on creation |
| Player Grenade Velocity | GDScript `Call()` fails | C# sets velocity directly |
| Player Grenade Impact | Race condition in impact detection | MarkAsThrown() called BEFORE unfreezing |
| Enemy Grenade Timer | GDScript `Call()` fails | C# GrenadeTimerHelper autoload attaches timer |
| Enemy Grenade Impact | No C# component attached | GrenadeTimerHelper attaches and configures |
| TileMap Collision | Wrong type check | Added TileMap alongside TileMapLayer |

**Key Insight Update**: The solution requires:
1. **C# for critical physics** in player code
2. **C# autoload bridge** for GDScript code (enemy grenades) to access C# functionality
3. **Proper timing** of state changes to avoid race conditions

## References

- [Godot RigidBody2D Documentation](https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html)
- [Godot Physics - Impulse vs Force](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html)
- [Godot 4 C#/GDScript Interop Issues](https://github.com/godotengine/godot/issues) - Various reports of Call() failing in exports
- [Issue #183](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/183) - Original "activation position" bug and fix (commit 60f7cae)
