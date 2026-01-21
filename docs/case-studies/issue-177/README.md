# Case Study: Issue #177 - Flashbang Grenade Not Working

## Problem Summary
The flashbang grenade feature was implemented in GDScript but the player could not use grenades in the game. Users reported:
- Tutorial is present
- Grenade does not appear or work
- Multiple attempts of the control sequence produced no result

## Timeline of Events

### Initial Implementation (commits ad09b21 and 9acb5da)
1. Grenade system was added to `scripts/characters/player.gd` (GDScript)
2. `GrenadeBase.gd` and `FlashbangGrenade.gd` were created
3. Tutorial was added to `scripts/levels/tutorial_level.gd`
4. Input actions `grenade_prepare` (G key) and `grenade_throw` (RMB) were added to `project.godot`

### User Testing
User (Jhon-Crow) reported in PR #180 comments:
- Log files: `game_log_20260121_165728.txt` and `game_log_20260121_165904.txt`
- No grenade-related log entries appeared despite multiple attempts

## Root Cause Analysis

### Evidence from Logs
The user's game logs showed:
- Standard game startup messages
- GUNSHOT sounds from AssaultRifle
- **ZERO grenade-related log entries**

Expected log entries that were missing:
- `[Player] Ready! Grenades: 3/3`
- `[Player.Grenade] Step 1 started...`
- `[GrenadeBase] Timer activated!`

### Investigation

1. **Checked Player.tscn**: Found it uses `scripts/characters/player.gd`
2. **Checked Level Scenes**: Found they use a **different** player scene!

```bash
$ grep -h "Player" scenes/levels/*.tscn
[ext_resource type="PackedScene" path="res://scenes/characters/csharp/Player.tscn" id="2_player"]
```

### Root Cause Identified
**The level scenes (`BuildingLevel.tscn`, `TestTier.tscn`) use `scenes/characters/csharp/Player.tscn` which is attached to `Scripts/Characters/Player.cs` (C#), NOT `scripts/characters/player.gd` (GDScript).**

The grenade system was implemented in the GDScript player, but the actual game uses the C# player which had **no grenade functionality**.

## Architecture Issue
The project has two player implementations:
1. `scenes/characters/Player.tscn` + `scripts/characters/player.gd` (GDScript)
2. `scenes/characters/csharp/Player.tscn` + `Scripts/Characters/Player.cs` (C#)

The levels reference the C# version, but new features were added to the GDScript version.

## Solution
Added the complete 3-step grenade throwing mechanic to `Scripts/Characters/Player.cs`:

### Changes Made
1. Added grenade-related fields:
   - `GrenadeScene` (PackedScene export)
   - `MaxGrenades` (configurable, default 3)
   - `_currentGrenades` (current count)
   - `_grenadeState` (state machine)
   - `_activeGrenade` (reference to held grenade)

2. Added grenade state machine:
   - `GrenadeState.Idle` - waiting for input
   - `GrenadeState.TimerStarted` - pin pulled, timer running
   - `GrenadeState.Preparing` - LMB held
   - `GrenadeState.ReadyToAim` - LMB + RMB held
   - `GrenadeState.Aiming` - ready to throw

3. Implemented 3-step throwing mechanic:
   - Step 1: G + RMB drag right -> starts 4s timer
   - Step 2: LMB held -> RMB pressed -> LMB released -> prepare
   - Step 3: RMB held -> drag and release -> throw

4. Added signals:
   - `GrenadeChangedEventHandler(int current, int maximum)`
   - `GrenadeThrownEventHandler()`

5. Added logging via `LogToFile()` method for debugging

## Lessons Learned

1. **Dual Implementation Risk**: Having both GDScript and C# implementations of the same component creates maintenance burden and risk of features being added to the wrong version.

2. **Integration Testing**: Features should be tested in the actual game context, not just in isolation. The GDScript implementation may have worked in unit tests but never executed in the real game.

3. **Log Analysis is Critical**: The absence of expected log messages was the key indicator that the code wasn't running at all, pointing to a scene/script binding issue rather than a logic bug.

4. **Architecture Documentation**: Projects with mixed language implementations should clearly document which versions are used where.

## Files Changed
- `Scripts/Characters/Player.cs` - Added complete grenade system (~400 lines)

## Log Files
- `logs/game_log_20260121_165728.txt` - First test session
- `logs/game_log_20260121_165904.txt` - Second test session with multiple attempts
- `logs/game_log_20260121_185409.txt` - Third test session (throwing issues reported)

---

# Follow-Up: Throwing Mechanics Issues (2026-01-21)

## Reported Problems
User (Jhon-Crow) reported in PR #180 comments at 2026-01-21T16:00:29Z:
1. **Slow swings produce fast throws**: "бросок при медленном размахе должен быть медленным и граната должна лететь не далеко" (slow swing throws should be slow and grenade should not fly far)
2. **Throwing upward doesn't work**: "бросок вверх всё ещё не работает"

## Root Cause Analysis

### Issue 1: All Throws Are at Maximum Speed

**Evidence from logs** (`game_log_20260121_185409.txt`):
```
[GrenadeBase] Thrown! Direction: (0.989059, -0.147522), Speed: 3840.0
[GrenadeBase] Thrown! Direction: (0.97786, -0.209259), Speed: 3840.0
[GrenadeBase] Thrown! Direction: (0.154324, -0.98802), Speed: 3840.0
```
Every throw had the same speed: 3840.0 (the maximum), regardless of drag distance.

**Root Cause**: Double multiplication of sensitivity multipliers:
1. In `Player.cs` line 1097: `adjustedDragDistance = dragDistance * 9.0f`
2. In `grenade_base.gd` line 109: `throw_speed = drag_distance * drag_to_speed_multiplier` (12.0)

Result: Even a short drag of 50px → 50 * 9 * 12 = 5400, clamped to max 3840.

**Fix Applied**:
1. Removed the 9x multiplier from `Player.cs`
2. Set reasonable values in `grenade_base.gd`:
   - `max_throw_speed`: 3840 → 2500 (still travels far enough)
   - `min_throw_speed`: 150 → 100 (gentler minimum)
   - `drag_to_speed_multiplier`: 12 → 2 (linear mapping: ~1250px drag = max speed)

### Issue 2: Throwing Upward "Doesn't Work"

**Evidence from logs**:
```
Direction: (0.15432426, -0.9880203)  // Nearly straight up
Player rotated for throw: 0 -> -1.4158529
[GrenadeBase] Thrown! Direction: (0.154324, -0.98802), Speed: 3840.0
```
The grenade IS thrown upward (negative Y = up in Godot), so the direction was correct.

**Root Cause**: Grenade collision_mask = 7 (layers 1|2|4 = player|enemies|obstacles).
When thrown upward, the grenade could immediately collide with the player's collision shape, even with a 60px spawn offset.

**Fix Applied**:
1. Changed `collision_mask` from 7 to 6 (layers 2|4 = enemies|obstacles only)
2. Grenades no longer physically collide with the player, allowing throws in any direction

## Technical Details

### Before Fix (Speed Calculation)
```
Drag: 194px
C# multiplier: 194 * 9 = 1746
GDScript: 1746 * 12 = 20952 → clamped to 3840
Result: Short drag = max speed ❌
```

### After Fix (Speed Calculation)
```
Drag: 194px
No C# multiplier
GDScript: 194 * 2 = 388
Result: Short drag = slow throw ✓

Drag: 1000px (long swing)
GDScript: 1000 * 2 = 2000
Result: Long drag = fast throw ✓

Drag: 1300px (full swing)
GDScript: 1300 * 2 = 2600 → clamped to 2500
Result: Maximum throw speed ✓
```

### Collision Layers Reference
| Layer | Value | Description |
|-------|-------|-------------|
| 1     | 1     | Player      |
| 2     | 2     | Enemies     |
| 3     | 4     | Obstacles   |
| 6     | 32    | Grenades    |

## Files Changed
- `Scripts/Characters/Player.cs` - Removed 9x sensitivity multiplier
- `scripts/projectiles/grenade_base.gd` - Updated speed parameters and collision mask
- `scenes/projectiles/FlashbangGrenade.tscn` - Updated speed values and collision mask

---

# Follow-Up: Grenade Spawn Position Bug (2026-01-21)

## Reported Problem
User (Jhon-Crow) reported at 2026-01-21T16:20:22Z:
- "сейчас бросок происходит с позиции активации гранаты, а не с позиции игрока"
  (Currently the throw happens from the activation position, not from the player's position)
- Attached log file: `game_log_20260121_191036.txt`

## Root Cause Analysis

### Evidence from Logs
The user's game log showed grenades being created at a fixed position regardless of player movement:

```
[19:10:39] [INFO] [GrenadeBase] Grenade created at (450, 1250)
[19:10:44] [INFO] [GrenadeBase] Grenade created at (450, 1250)
[19:10:47] [INFO] [GrenadeBase] Grenade created at (450, 1250)
[19:10:53] [INFO] [GrenadeBase] Grenade created at (450, 1250)
[19:11:01] [INFO] [GrenadeBase] Grenade created at (543.8889, 1250)  // Only X changed slightly
```

The position `(450, 1250)` matches the player's spawn position in `BuildingLevel.tscn`:
```gdscript
[node name="Player" parent="Entities" instance=ExtResource("2_player")]
position = Vector2(450, 1250)
```

### Root Cause Identified

**Order of Operations Bug in Node Instantiation**

The bug was in both `Player.cs` and `player.gd`:

```csharp
// BEFORE (buggy):
_activeGrenade = GrenadeScene.Instantiate<RigidBody2D>();
_activeGrenade.GlobalPosition = GlobalPosition;  // Set position BEFORE adding to scene
GetTree().CurrentScene.AddChild(_activeGrenade); // _ready() logs old position
```

**Why this fails**:
1. `GlobalPosition` cannot be properly set on a node that is not yet in the scene tree
2. When `AddChild()` is called, the node's `_ready()` function executes
3. At that point, the node might still have its default/scene position, not the position we tried to set

### Fix Applied

Changed the order to set position AFTER adding to the scene tree:

```csharp
// AFTER (fixed):
_activeGrenade = GrenadeScene.Instantiate<RigidBody2D>();
GetTree().CurrentScene.AddChild(_activeGrenade);  // Add to scene first
_activeGrenade.GlobalPosition = GlobalPosition;   // NOW set position (works correctly)
```

## Technical Details

### Godot Node Lifecycle
In Godot, a node's `GlobalPosition` property only works correctly when the node is part of the scene tree. Before being added:
- The node has no parent, so global transforms are meaningless
- Setting `GlobalPosition` may appear to work but the value isn't properly propagated

### Files Changed
- `Scripts/Characters/Player.cs` - Reordered AddChild/GlobalPosition in `StartGrenadeTimer()`
- `scripts/characters/player.gd` - Reordered add_child/global_position in `_start_grenade_timer()`

---

# Feature Addition: Grenade Training Area (2026-01-21)

## User Request
User (Jhon-Crow) requested at 2026-01-21T16:20:22Z:
- "добавь тренировочную площадку для метания гранат (с мишенями, которые можно и которые нельзя задевать)"
  (Add a training area for grenade throwing with targets that can and cannot be hit)

## Implementation

### New Components Created

1. **GrenadeTarget Script** (`scripts/objects/grenade_target.gd`)
   - Similar to regular Target but specifically for grenade training
   - `is_valid_target` property: `true` for enemies (red), `false` for friendlies (green)
   - Emits `grenade_hit(is_valid_target: bool)` signal when affected
   - Shows different colors based on target type and status effects

2. **GrenadeTarget Scene** (`scenes/objects/GrenadeTarget.tscn`)
   - 64x64 pixel target with collision shape
   - Label showing target type (ВРАГ/СВОИ)
   - Color-coded: red for enemies, green for friendlies

3. **Expanded Tutorial Level** (`scenes/levels/csharp/TestTier.tscn`)
   - Enlarged level (1864x1264 instead of 928x720)
   - Two distinct zones:
     - **Shooting Zone** (top half) - Original shooting targets
     - **Grenade Training Area** (bottom half) - New grenade practice area

### Grenade Training Area Layout
- 6 enemy targets (red) - should be hit
- 4 friendly targets (green) - should NOT be hit
- Walls and cover objects for practicing angled throws
- Visual instructions explaining target colors

### Target Positions
**Enemy Targets (should hit):**
| Target | Position |
|--------|----------|
| EnemyTarget1 | (500, 850) |
| EnemyTarget2 | (700, 950) |
| EnemyTarget3 | (900, 800) |
| EnemyTarget4 | (1100, 900) |
| EnemyTarget5 | (1300, 1000) |
| EnemyTarget6 | (1500, 850) |

**Friendly Targets (should NOT hit):**
| Target | Position |
|--------|----------|
| FriendlyTarget1 | (600, 1050) |
| FriendlyTarget2 | (850, 1100) |
| FriendlyTarget3 | (1200, 1080) |
| FriendlyTarget4 | (1550, 1050) |

### Files Changed
- `scripts/objects/grenade_target.gd` - NEW: Grenade target script
- `scenes/objects/GrenadeTarget.tscn` - NEW: Grenade target scene
- `scenes/levels/csharp/TestTier.tscn` - Expanded with grenade training area
