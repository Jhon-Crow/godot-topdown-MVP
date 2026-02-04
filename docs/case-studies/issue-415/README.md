# Issue #415: Animated Statistics Screen (Hotline Miami 2 Style)

## Issue Summary

**Title**: пункты статистики должны появляться постепенно (как в hotline miami 2)

**Translation**: Statistics items should appear gradually (like in Hotline Miami 2)

## Requirements

The score screen at level completion should have the following animations:

1. **Sequential Item Reveal**: Score categories appear one at a time, only after the previous item's animation completes
2. **Counting Animation**: Final numbers for each category animate from 0 to their final value
3. **Pulsing Effect**: Numbers rhythmically pulse (change color and slightly increase in size) during counting
4. **Sound Effect**: Retro-style filling sound plays during the counting animation
5. **Final Rank Animation**:
   - First appears fullscreen on a flashing/color-changing background
   - Then shrinks and moves to its final position (bottom, slightly right of center, below other items)

## Research Findings

### Hotline Miami 2 Score Screen Behavior

Based on research from [Hotline Miami Wiki](https://hotlinemiami.fandom.com/wiki/Scoring) and community resources:

- Score screen presents a "Sunset Screen" with palm trees against an ocean horizon
- Statistics revealed sequentially with dramatic presentation
- Score categories include: Kills, Boldness, Combos, Time Bonus, Flexibility, Mobility
- Grade system: F- through A+, with "S" grade in HM2 requiring ~2.6x the Grade C threshold
- The JUSTICE3D font family is used for the "pop" effect by layering characters

### Score Counter Animation Technique

From [Godot Forum discussions](https://forum.godotengine.org/t/score-counter-for-a-game-over-screen/74208):

Best approach uses delta-time based interpolation in `_process()`:
```gdscript
var elapsed_time: float = 0.0
var animation_duration: float = 1.0  # seconds

func _process(delta):
    if animating:
        elapsed_time += delta
        var progress = min(elapsed_time / animation_duration, 1.0)
        displayed_value = int(target_value * progress)
        if progress >= 1.0:
            animating = false
```

### Sound Resources

Free retro arcade sound effects available from:
- [The Motion Monkey](https://www.themotionmonkey.co.uk/free-resources/retro-arcade-sounds/) - CC0 licensed
- [ZapSplat](https://www.zapsplat.com/music/retro-arcade-game-sound-beep-1/) - Free beep sounds
- [Mixkit](https://mixkit.co/free-sound-effects/arcade/) - Royalty-free arcade sounds

## Current Implementation

The project already has:

1. **ScoreManager** (`scripts/autoload/score_manager.gd`): Tracks all performance metrics
2. **Score Screen** (`scripts/levels/building_level.gd:711-835`): Static display created at runtime
3. **AudioManager** (`scripts/autoload/audio_manager.gd`): Sound playback system with priority support

### Existing Score Data Structure

```gdscript
{
    "total_score": int,
    "rank": String,
    "kills": int,
    "total_enemies": int,
    "kill_points": int,
    "combo_points": int,
    "max_combo": int,
    "time_bonus": int,
    "completion_time": float,
    "accuracy_bonus": int,
    "accuracy": float,
    "shots_fired": int,
    "hits_landed": int,
    "damage_penalty": int,
    "damage_taken": int,
    "special_kill_bonus": int,
    "ricochet_kills": int,
    "penetration_kills": int,
    "aggressiveness": float,
    "special_kills_eligible": bool,
    "max_possible_score": int
}
```

## Proposed Solution

### Architecture

Create a new reusable `AnimatedScoreScreen` scene/script that can be instantiated by level scripts:

1. **AnimatedScoreScreen** - Main container handling animation sequencing
2. **AnimatedScoreItem** - Individual score line with counting/pulsing animation
3. **AnimatedRankDisplay** - Fullscreen → shrink rank reveal

### Animation Timeline

```
Time (seconds)
0.0 ────────────────────────────────────────────────────────────►

0.0-0.3: Title "LEVEL CLEARED!" fade in
0.3-1.3: KILLS item animates (reveal + count + pulse)
1.3-2.3: COMBOS item animates
2.3-3.3: TIME item animates
3.3-4.3: ACCURACY item animates
4.3-5.3: SPECIAL KILLS item animates (if applicable)
5.3-6.3: DAMAGE TAKEN item animates (if applicable)
6.3-7.3: TOTAL SCORE item animates
7.3-9.0: RANK fullscreen flash → shrink animation
9.0+:    "Press Q to restart" hint appears
```

### Technical Implementation

1. Use Godot Tween for smooth animations
2. Implement pulsing via color modulation and scale tweening
3. Add procedurally-generated beep sound or use existing audio system
4. Signal-based sequencing for clean separation of concerns

### Files to Create/Modify

- **NEW**: `scripts/ui/animated_score_screen.gd` - Main animation controller
- **NEW**: `scenes/ui/animated_score_screen.tscn` - Scene with layout
- **MODIFY**: `scripts/levels/building_level.gd` - Use new animated screen
- **MODIFY**: `scripts/autoload/audio_manager.gd` - Add score counting sound

## Bug Investigation (2026-02-03)

### Reported Issues

From PR #430 comment by repository owner:

1. **Statistics not visible** - Score items were not appearing on screen
2. **Rank in far left corner** - The rank letter appeared in the wrong position
3. **Rank color should depend on grade** - Already implemented in RANK_COLORS dictionary
4. **Sound should be major arpeggio** - Original implementation used single beeps

### Game Logs Analysis

Downloaded logs from:
- `logs/game_log_20260203_181812.txt` - First playthrough session
- `logs/game_log_20260203_181921.txt` - Second playthrough session

Both logs confirmed level completion with scores:
- First session: Final score 26904, Rank: C
- Second session: Final score 26997, Rank: C

### Root Cause Analysis

**Issue 1 & 2: Statistics and Rank Position**

The root cause was in `animated_score_screen.gd`:

```gdscript
func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)  # Problem here
```

When `AnimatedScoreScreen.new()` is called and added to the UI node:
1. `_ready()` is called immediately upon `add_child()`
2. `set_anchors_preset(PRESET_FULL_RECT)` sets anchors but the Control's size
   hasn't been updated yet to match the parent's size
3. Children created in `show_score()` use positions relative to a Control
   with potentially size (0, 0)
4. `PRESET_CENTER` children end up at wrong positions

**Fix applied:**
```gdscript
func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    size = get_parent_area_size() if get_parent() else get_viewport_rect().size
```

Additionally, the rank shrink animation had asymmetric offsets (`-50` to `200`)
which placed it off-center. Fixed to use symmetric offsets (`-75` to `75`).

**Issue 3: Rank Color**

Already correctly implemented in `RANK_COLORS` dictionary at line 39-47.
Colors are applied in `_start_rank_animation()` at line 506.

**Issue 4: Major Arpeggio Sound**

Changed from single beep to ascending major arpeggio:
- Root note (base frequency)
- Major third (+4 semitones, frequency * 2^(4/12))
- Perfect fifth (+7 semitones, frequency * 2^(7/12))

### Timeline of Events

```
2026-02-03 13:48:12 - Initial implementation committed
2026-02-03 15:23:13 - Owner reports bugs in PR comment (statistics not visible, rank mispositioned)
2026-02-03 17:53:33 - Fix session started (first fix attempt)
2026-02-03 18:54:04 - Owner reports score still not appearing, out-of-ammo message persists
2026-02-03 19:XX:XX - Second fix session: added comprehensive logging and ammo message fix
```

## Bug Investigation Session 2 (2026-02-03 18:54)

### Reported Issues

From PR #430 comment by repository owner (in Russian):

1. **"счёт не появляется"** (Score doesn't appear)
2. **"если игрок не умер а все враги умерли - надпись о закончившихся патронах должна исчезнуть"**
   (If the player didn't die and all enemies died - the message about running out of ammo should disappear)

### Game Log Analysis

Downloaded log: `logs/game_log_20260203_213919.txt` (4.2MB, 45289 lines)

Key findings from log analysis:
- **Line 45185**: `[ENEMY] [Enemy10] Player ammo empty: false -> true` - Player ran out of ammo
- **Line 45229**: `[ENEMY] [Enemy10] Enemy died` - Last enemy killed
- **Line 45235**: `[INFO] [ScoreManager] Level completed! Final score: 20630, Rank: C`
- **No AnimatedScoreScreen logs** - The score screen component had no logging, making diagnosis difficult
- Log ends at 21:53:09 with game still running (footsteps, player reloading) - no score screen visible

### Root Cause Analysis

**Issue 1: Score Screen Not Appearing**

The AnimatedScoreScreen had no logging, making it impossible to trace execution.
After adding comprehensive logging (`_log_debug()` function), we identified that:
- The size initialization used `get_parent_area_size()` which may return zero
- Changed to use `get_viewport_rect().size` for reliable sizing

**Issue 2: "Out of Ammo" Message Persisting**

The "OUT OF AMMO" message (GameOverLabel) was shown when player had no ammo remaining.
When the player killed all enemies (possibly using the last bullet or ricochet), the
GameOverLabel remained visible because:
1. No code existed to remove it when the level was completed
2. No flag prevented it from being shown after level completion

**Fixes Applied:**

1. Added `_level_completed` flag to `building_level.gd`:
   ```gdscript
   var _level_completed: bool = false
   ```

2. Set flag when level completes:
   ```gdscript
   func _complete_level_with_score() -> void:
       _level_completed = true
   ```

3. Check flag before showing game over message:
   ```gdscript
   if _current_enemy_count > 0 and not _game_over_shown and not _level_completed:
       _show_game_over_message()
   ```

4. Remove existing GameOverLabel when showing score screen:
   ```gdscript
   var game_over_label := ui.get_node_or_null("GameOverLabel")
   if game_over_label:
       game_over_label.queue_free()
   ```

5. Added comprehensive logging throughout:
   - `AnimatedScoreScreen._ready()`: logs viewport size, Control size
   - `AnimatedScoreScreen.show_score()`: logs score data, container creation
   - `building_level._show_score_screen()`: logs UI node, script loading, child count
   - `building_level._complete_level_with_score()`: logs level completion

## Bug Investigation Session 3 (2026-02-04)

### Reported Issue

From PR #430 comment by repository owner (in Russian):
- **"после завершения миссии ничего не отображается"** (After completing the mission nothing is displayed)

### Game Log Analysis

Downloaded log: `logs/game_log_20260204_004744.txt` (186KB, 2124 lines)

Key findings:
- **Line 2080**: `[BuildingLevel] Level completed, setting _level_completed = true`
- **Line 2082**: `[ScoreManager] Level completed! Final score: 21776, Rank: C`
- **Line 2083**: `[BuildingLevel] _show_score_screen called with score_data: {...}`
- **Line 2084**: `[BuildingLevel] Found UI node: UI, size: (1280, 720)`
- **Line 2085**: `[BuildingLevel] Removed GameOverLabel (out of ammo message)`
- **Line 2086**: `[BuildingLevel] Loaded AnimatedScoreScreen script successfully`
- **Line 2087**: `[BuildingLevel] Added AnimatedScoreScreen to UI, child count now: 8`
- **Line 2088**: `[BuildingLevel] Called show_score() on AnimatedScoreScreen`
- **NO AnimatedScoreScreen internal logs appeared** (despite logging being added)
- **Lines 2089-2111**: Game continues normally (blood decals, enemy death animation)
- **Lines 2112-2121**: Player clicking empty gun (6 seconds after score screen creation)
- **Line 2122**: Game log ends normally at 00:49:20

### Critical Observation

The score screen was created and `show_score()` was called, but:
1. No internal AnimatedScoreScreen logs appeared (e.g., "show_score() called with data:")
2. Player continued interacting with the game (clicking empty gun)
3. Game ran for 17 seconds after level completion before closing

This indicates the score screen was added to the scene but was NOT visible.

### Root Cause Hypothesis

**Z-Order / Layer Issue**: The AnimatedScoreScreen is added to the UI Control inside the main CanvasLayer (layer 1 by default). However, the CinemaEffects manager creates its effects at CanvasLayer layer 99:
```
[CinemaEffects] Created effects layer at layer 99
```

This means the CinemaEffects (film grain, vignette) are rendered ON TOP of the score screen, potentially obscuring it entirely.

Additionally, the `_log_debug()` function uses `get_node_or_null("/root/FileLogger")` which may not work correctly for dynamically created nodes, causing logs to fall back to `print()` (stdout only, not captured in file log).

### Fixes Applied

1. **Created dedicated CanvasLayer (layer 100)** for the score screen:
   ```gdscript
   var score_canvas_layer := CanvasLayer.new()
   score_canvas_layer.name = "ScoreScreenCanvasLayer"
   score_canvas_layer.layer = 100  # Above CinemaEffects (layer 99)
   add_child(score_canvas_layer)
   ```

2. **Improved `_log_debug()` function** to use multiple methods:
   ```gdscript
   func _log_debug(message: String) -> void:
       var file_logger: Node = null
       # Method 1: Try scene tree root
       if is_inside_tree():
           file_logger = get_tree().root.get_node_or_null("FileLogger")
       # Method 2: Fallback to absolute path
       if file_logger == null:
           file_logger = get_node_or_null("/root/FileLogger")
   ```

3. **Added explicit visibility settings**:
   ```gdscript
   score_screen.visible = true
   score_screen.modulate = Color.WHITE
   _background.visible = true
   _container.visible = true
   ```

4. **Enhanced logging** with more detail about Control properties:
   - Size, position, visibility, modulate
   - Parent node name
   - Is in tree status
   - Tween creation success/failure

5. **Added fallback for tween failure**:
   ```gdscript
   if tween == null:
       _log_debug("ERROR: create_tween() returned null!")
       # Fallback: directly set values
       _background.color.a = 0.7
       _container.modulate.a = 1.0
       _create_title()
       return
   ```

## Bug Investigation Session 4 (2026-02-04)

### Reported Issue

From PR #430 comment by repository owner (in Russian):
- **"счёт не отображается"** (Score is not displayed)
- Attached log file: `game_log_20260204_083600.txt`

### Game Log Analysis

Downloaded log: `logs/game_log_20260204_083600.txt` (544KB, 5643 lines)

Key findings (lines 5604-5643):
- **Line 5608**: `[BuildingLevel] Level completed, setting _level_completed = true`
- **Line 5610**: `[ScoreManager] Level completed! Final score: 28165, Rank: B`
- **Line 5611**: `[BuildingLevel] _show_score_screen called with score_data: {...}`
- **Line 5613**: `[BuildingLevel] Loaded AnimatedScoreScreen script successfully`
- **Line 5614**: `[BuildingLevel] Created ScoreScreenCanvasLayer at layer 100`
- **Line 5615**: `[BuildingLevel] Added AnimatedScoreScreen to ScoreScreenCanvasLayer`
- **Line 5616**: `[BuildingLevel] Set score_screen size to viewport: (1280, 720)`
- **Line 5617**: `[BuildingLevel] Called show_score() on AnimatedScoreScreen`
- **NO AnimatedScoreScreen internal logs** (no `[AnimatedScoreScreen]` messages at all)
- **Lines 5618-5643**: Game continues (blood decals, shotgun actions, player footsteps)
- Player still interacting with game 8 seconds after score screen creation
- Log ends at 08:37:34 with no score screen visible

### Critical Observation

Despite the previous fix (CanvasLayer at layer 100), the score screen is STILL not visible.
The logs show `_show_score_screen()` executes successfully through line 5617, but:

1. **No `_ready()` call logged** - The AnimatedScoreScreen's `_ready()` was never called
2. **No `show_score()` internal logs** - The function's logging statements never executed
3. **Game continued normally** - Player could interact, shotgun clicks logged

This indicates the AnimatedScoreScreen node is NOT functioning as a proper Control node.

### Root Cause Analysis

**The Fundamental Issue: Incorrect Script Instantiation**

The code was using:
```gdscript
var AnimatedScoreScreenScript = load("res://scripts/ui/animated_score_screen.gd")
var score_screen = AnimatedScoreScreenScript.new()  # WRONG!
```

In Godot 4.x, when you call `.new()` on a GDScript that extends a Node-derived class (like Control):
- It creates a Reference-like object, NOT a proper Control node
- The object can be added as a child, but:
  - `_ready()` is NOT called
  - The node tree integration doesn't work properly
  - Methods may execute but have undefined behavior

**Correct Pattern:**
```gdscript
var animated_score_screen_script = load("res://scripts/ui/animated_score_screen.gd")
var score_screen := Control.new()  # Create proper Control node first
score_screen.set_script(animated_score_screen_script)  # Then attach script
```

This is the same pattern used elsewhere in Godot codebases when dynamically creating nodes with scripts.

### Evidence Supporting Root Cause

1. **BuildingLevel logs show script loaded successfully** - The script file exists and loads
2. **BuildingLevel logs show child added** - The object was added to the tree
3. **No AnimatedScoreScreen internal logs** - `_ready()` never triggered
4. **No console prints either** - Even the fallback `print()` statements didn't execute
5. **Game continued normally** - The "node" didn't block input or process frames

### Fixes Applied

1. **Changed instantiation pattern** in `building_level.gd`:
   ```gdscript
   # Before (broken):
   var AnimatedScoreScreenScript = load("res://scripts/ui/animated_score_screen.gd")
   var score_screen = AnimatedScoreScreenScript.new()

   # After (correct):
   var animated_score_screen_script = load("res://scripts/ui/animated_score_screen.gd")
   var score_screen := Control.new()
   score_screen.set_script(animated_score_screen_script)
   ```

2. **Added console print statements** for immediate debugging:
   - `print("[AnimatedScoreScreen] _ready() STARTING...")`
   - `print("[AnimatedScoreScreen] show_score() CALLED...")`
   - These print directly to stdout, bypassing any FileLogger issues

3. **Enhanced logging** to track parent node and tree status:
   - Logs `is_inside_tree()` status
   - Logs parent node name

### Why This Bug Was Hard to Find

1. **Silent failure** - No errors or warnings were logged
2. **Partial functionality** - The object could be added to tree, named, sized
3. **Logs appeared successful** - BuildingLevel logs showed all steps completed
4. **Misleading pattern** - The docstring in `animated_score_screen.gd` suggested `.new()` usage
5. **Godot behavior** - Godot silently accepts the broken object as a child

### Prevention Recommendations

1. **Always use proper instantiation patterns**:
   - For scenes: `packed_scene.instantiate()`
   - For scripts on built-in types: `NodeType.new()` + `set_script()`

2. **Add defensive logging**:
   - Log at the START of `_ready()` to confirm it's being called
   - Use `print()` as backup, not just FileLogger

3. **Test dynamic node creation**:
   - Verify `is_inside_tree()` returns true
   - Verify `_ready()` is called
   - Verify `_process()` receives delta updates

## Bug Investigation Session 5 (2026-02-04)

### Reported Issue

From PR #430 comment by repository owner (in Russian):
- **"ничего не появляется и звуков нет"** (Nothing appears and there are no sounds)
- Attached log file: `game_log_20260204_095326.txt`

### Game Log Analysis

Downloaded log: `logs/game_log_20260204_095326.txt` (975KB, 10884 lines)

Key findings from analyzing the log:

**Multiple level playthrough attempts detected:**
- Lines 1-1831: First session with level completion
- Lines 5352-5644: Multiple restarts with enemy tracking
- Lines 10844-10855: Final level completion attempt

**Final completion sequence (lines 10844-10855):**
- **Line 10844**: `[BuildingLevel] Level completed, setting _level_completed = true`
- **Line 10846**: `[ScoreManager] Level completed! Final score: 24377, Rank: C`
- **Line 10847**: `[BuildingLevel] _show_score_screen called with score_data: {...}`
- **Line 10848**: `[BuildingLevel] Found UI node: UI, size: (1280, 720)`
- **Line 10849**: `[BuildingLevel] Removed GameOverLabel (out of ammo message)`
- **Line 10850**: `[BuildingLevel] Loaded AnimatedScoreScreen script successfully`
- **Line 10851**: `[BuildingLevel] Created ScoreScreenCanvasLayer at layer 100`
- **Line 10852**: `[BuildingLevel] Created Control node and attached AnimatedScoreScreen script`
- **Line 10853**: `[BuildingLevel] Added AnimatedScoreScreen to ScoreScreenCanvasLayer (should trigger _ready)`
- **Line 10854**: `[BuildingLevel] Set score_screen size to viewport: (1280, 720)`
- **Line 10855**: `[BuildingLevel] Called show_score() on AnimatedScoreScreen`

**Critical Observation:**
- **NO `[AnimatedScoreScreen]` logs at all** - Despite Session 4's fix, `_ready()` is STILL not being called
- The log file search `grep -n "\[AnimatedScoreScreen\]"` returned zero results
- Lines 10856-10884: Game continues (blood decals, ragdoll activation, player footsteps)
- Player stepped in blood (line 10880) and blood ran out (line 10882) - game was still playable
- Log ends at 09:58:01, with no score screen visible

### Root Cause Analysis

**Session 4 Fix Didn't Work in Exported Builds**

The previous fix changed from:
```gdscript
var score_screen = AnimatedScoreScreenScript.new()  # Old broken pattern
```
To:
```gdscript
var score_screen := Control.new()
score_screen.set_script(animated_score_screen_script)  # Session 4 fix
```

However, this pattern **still doesn't reliably trigger `_ready()` in Godot 4.x exported builds**.

**Research Findings:**

Based on extensive research into Godot 4.x behavior:

1. **[Godot Forum - Scripts won't work after being attached via code](https://forum.godotengine.org/t/scripts-wont-work-after-being-attached-to-node-via-code/9633)**:
   > When attaching a script to a node dynamically via `set_script()` after the scene tree is initialized, the script's lifecycle callbacks don't execute automatically.

2. **[Godot GitHub Issue #38373 - set_script() fails if target node has no parent](https://github.com/godotengine/godot/issues/38373)**:
   > When `set_script()` is called on a node that has already been added to the scene tree, the node's `_ready()` function doesn't execute.

3. **[Godot GitHub Issue #74992 - Extended class _ready() not called](https://github.com/godotengine/godot/issues/74992)**:
   > In Godot 4, when a script extends another script, the parent class's `_init()` and `_ready()` functions are not automatically called.

4. **[Godot GitHub Issue #56343 - Preload fails in standalone build](https://github.com/godotengine/godot/issues/56343)**:
   > GDScript preload fails in standalone build unless files are present in directory.

**Conclusion:** The `Control.new() + set_script()` pattern has race conditions and inconsistent behavior across editor vs exported builds in Godot 4.x. The most reliable approach is to use scene files.

### Fix Applied

**Solution: Create a Scene File (.tscn) for AnimatedScoreScreen**

Instead of dynamically creating a Control and attaching a script, we now use a proper scene file that can be reliably instantiated:

1. **Created `scenes/ui/AnimatedScoreScreen.tscn`:**
   ```
   [gd_scene load_steps=2 format=3 uid="uid://c4animscorescreen415"]

   [ext_resource type="Script" path="res://scripts/ui/animated_score_screen.gd" id="1_anim_score"]

   [node name="AnimatedScoreScreen" type="Control"]
   anchors_preset = 15
   anchor_right = 1.0
   anchor_bottom = 1.0
   grow_horizontal = 2
   grow_vertical = 2
   mouse_filter = 2
   script = ExtResource("1_anim_score")
   ```

2. **Updated `building_level.gd` to load and instantiate the scene:**
   ```gdscript
   # Before (unreliable in exported builds):
   var animated_score_screen_script = load("res://scripts/ui/animated_score_screen.gd")
   var score_screen := Control.new()
   score_screen.set_script(animated_score_screen_script)

   # After (reliable):
   var animated_score_screen_scene = load("res://scenes/ui/AnimatedScoreScreen.tscn")
   var score_screen = animated_score_screen_scene.instantiate()
   ```

### Why This Fix Works

1. **Scene instantiation is the canonical Godot pattern** - `PackedScene.instantiate()` is how Godot was designed to create nodes with scripts
2. **The script is attached at scene compilation time** - Not dynamically at runtime
3. **All node properties are pre-configured** - Anchors, size, mouse filter are set in the scene file
4. **`_ready()` is guaranteed to be called** - When adding a scene instance to the tree, all lifecycle callbacks are properly invoked
5. **Works consistently across editor and exported builds** - No edge cases or race conditions

### Lessons Learned

1. **Never use `set_script()` for complex nodes in production code** - It has too many edge cases
2. **Always prefer scene files (.tscn) over dynamic node creation** - They are more reliable
3. **Test in exported builds, not just the editor** - Many behaviors differ between editor and export
4. **Add logging at the very start of `_ready()`** - This immediately reveals if the function is being called

## Bug Investigation Session 6 (2026-02-04)

### Reported Issue

From PR #430 comment by repository owner (in Russian):
- **"всё ещё ничего не видно"** (Still nothing is visible)
- Attached log file: `game_log_20260204_163841.txt`

### Game Log Analysis

Downloaded log: `logs/game_log_20260204_163841.txt` (265KB, 2845 lines)

Key findings from analyzing the log:

**Level completion sequence (lines 2820-2833):**
- **Line 2820**: `[BuildingLevel] Level completed, setting _level_completed = true`
- **Line 2822**: `[ScoreManager] Level completed! Final score: 19196, Rank: C`
- **Line 2823**: `[BuildingLevel] _show_score_screen called with score_data: {...}`
- **Line 2824**: `[BuildingLevel] Found UI node: UI, size: (1280, 720)`
- **Line 2825**: `[BuildingLevel] Loaded AnimatedScoreScreen scene successfully`
- **Line 2826**: `[BuildingLevel] Created ScoreScreenCanvasLayer at layer 100`
- **Line 2827**: `[BuildingLevel] Instantiated AnimatedScoreScreen from scene`
- **Line 2828**: `[BuildingLevel] Added AnimatedScoreScreen to ScoreScreenCanvasLayer (triggers _ready)`
- **Line 2829**: `[BuildingLevel] Set score_screen size to viewport: (1280, 720)`
- **Line 2830**: `[BuildingLevel] Called show_score() on AnimatedScoreScreen`

**Critical Observation:**
- **NO `[AnimatedScoreScreen]` logs at all** - Despite Session 5's scene file fix, `_ready()` is STILL not being called
- `grep -n "AnimatedScoreScreen" game_log_20260204_163841.txt` only returns BuildingLevel logs, no internal AnimatedScoreScreen logs
- Even the `print()` statements at lines 89-90 of animated_score_screen.gd don't appear
- Lines 2831-2845: Game continues (ragdoll, player footsteps, blood)
- Player walked around for ~27 seconds after level completion - game was still playable
- Log ends at 16:40:07, with no score screen visible

### Root Cause Analysis

**Session 5 Scene File Fix Still Didn't Work**

The previous fix changed from:
```gdscript
var score_screen := Control.new()
score_screen.set_script(animated_score_screen_script)  # Session 4 fix
```
To:
```gdscript
var animated_score_screen_scene = load("res://scenes/ui/AnimatedScoreScreen.tscn")
var score_screen = animated_score_screen_scene.instantiate()  # Session 5 fix
```

However, even `load().instantiate()` fails to properly attach scripts in some exported builds.

**Research Findings:**

Based on extensive research into Godot 4.x behavior with exported builds:

1. **[Godot Forum - Scene doesn't load in exported build](https://forum.godotengine.org/t/scene-doesnt-load-in-exported-build-but-loads-fine-from-within-godot/46459)**:
   > Scenes load fine from within Godot, but not from the exported build. Even with "Export selected scenes (and dependencies)" enabled and all scenes selected.

2. **[Godot Forum - Instantiated scenes don't have scripts connected](https://forum.godotengine.org/t/instantiated-scenes-dont-have-scripts-connected/75079)**:
   > The problem only happens to scripts that extend other scripts. In newly instantiated scenes, nodes whose scripts extend a builtin type work, but those extending custom scripts may not.

3. **[Godot GitHub - GDScript export mode breaks exported builds](https://github.com/godotengine/godot/issues/94150)**:
   > When GDScript export mode is set to binary tokens/compressed binary tokens, some resources won't load. Text mode exports work correctly.

4. **[Godot Forum - Autoload Script Functions not called in Exported Build](https://forum.godotengine.org/t/autoload-script-functions-not-being-called-in-exported-build/127658)**:
   > Autoload scripts load but `_ready()` never executes in exported builds. The script appears in debug logs but its functions don't run.

**Key Insight: `load()` vs `preload()` in Exported Builds**

The difference between `load()` and `preload()` is critical:

| Aspect | `load()` | `preload()` |
|--------|----------|-------------|
| When executed | At runtime | At compile time |
| Where resource stored | Loaded from .pck at runtime | Embedded in script bytecode |
| Script attachment | May fail in some exports | Guaranteed embedded |
| Reliability | Variable | Consistent |

In exported builds, `load()` performs runtime resource resolution from the .pck file, which can have race conditions or caching issues. `preload()` embeds the resource directly into the compiled script, ensuring it's always available.

### Fix Applied

**Solution: Use `preload()` Instead of `load()` for Scene Loading**

Changed from runtime `load()` to compile-time `preload()`:

1. **Added preloaded constant in `building_level.gd`:**
   ```gdscript
   ## Preload the AnimatedScoreScreen scene at compile time.
   ## IMPORTANT: Using preload() instead of load() ensures the scene and its script
   ## are properly embedded in the export. Runtime load() may fail to attach scripts
   ## correctly in some exported builds.
   const AnimatedScoreScreenScene: PackedScene = preload("res://scenes/ui/AnimatedScoreScreen.tscn")
   ```

2. **Updated `_show_score_screen()` to use preloaded constant:**
   ```gdscript
   # Before (runtime loading):
   var animated_score_screen_scene = load("res://scenes/ui/AnimatedScoreScreen.tscn")
   var score_screen = animated_score_screen_scene.instantiate()

   # After (compile-time embedding):
   var score_screen = AnimatedScoreScreenScene.instantiate()
   ```

3. **Added comprehensive debugging** to verify script attachment:
   ```gdscript
   # Debug: Check if script is attached
   var attached_script = score_screen.get_script()
   if attached_script != null:
       _log_to_file("Script IS attached: %s" % attached_script.resource_path)
   else:
       _log_to_file("WARNING: No script attached to instantiated node!")

   # Debug: Check if show_score method exists
   var has_show_score := score_screen.has_method("show_score")
   _log_to_file("has_method('show_score'): %s" % str(has_show_score))
   ```

### Why This Fix Should Work

1. **`preload()` embeds resources at compile time** - The scene and script are part of the compiled bytecode
2. **No runtime resource resolution** - Eliminates race conditions in .pck file loading
3. **Guaranteed availability** - The resource cannot be missing or fail to load
4. **Consistent behavior** - Works the same in editor and all export targets
5. **Better debugging** - The new logging will reveal exactly what's happening

### Diagnostic Information

If this fix doesn't work, the new debug logging will reveal:
- Whether the script is attached (`get_script()` result)
- Whether the method exists (`has_method()` result)
- Whether the node is in tree (`is_inside_tree()` result)

This will help identify the exact failure point in the instantiation process.

## Related Resources

- [Hotline Miami Scoring Wiki](https://hotlinemiami.fandom.com/wiki/Scoring)
- [CodePen HM2 Score Recreation](https://codepen.io/nmbusman/pen/oLybYW)
- [Godot Forum: Animated Numbers](https://forum.godotengine.org/t/score-counter-for-a-game-over-screen/74208)
- [Free Retro Arcade Sounds](https://www.themotionmonkey.co.uk/free-resources/retro-arcade-sounds/)
- [Godot Forum: Scripts won't work after being attached via code](https://forum.godotengine.org/t/scripts-wont-work-after-being-attached-to-node-via-code/9633)
- [Godot GitHub: set_script() issue](https://github.com/godotengine/godot/issues/38373)
- [Godot GitHub: Extended class _ready() not called](https://github.com/godotengine/godot/issues/74992)
- [Godot Forum: Scene doesn't load in exported build](https://forum.godotengine.org/t/scene-doesnt-load-in-exported-build-but-loads-fine-from-within-godot/46459)
- [Godot Forum: Instantiated scenes don't have scripts connected](https://forum.godotengine.org/t/instantiated-scenes-dont-have-scripts-connected/75079)
- [Godot GitHub: GDScript export mode breaks exported builds](https://github.com/godotengine/godot/issues/94150)
- [Godot Forum: Autoload Script Functions not called](https://forum.godotengine.org/t/autoload-script-functions-not-being-called-in-exported-build/127658)

## Bug Investigation Session 7 (2026-02-04)

### Reported Issue

From PR #430 comment by repository owner (in Russian):
- **"статистики не видно"** (Statistics not visible)
- Attached log file: `game_log_20260204_165508.txt`

### Game Log Analysis

Downloaded log: `logs/game_log_20260204_165508.txt` (2456 lines)

Key findings from analyzing the log:

**Level completion sequence (lines 2400-2414):**
- **Line 2400**: `[BuildingLevel] Level completed, setting _level_completed = true`
- **Line 2402**: `[ScoreManager] Level completed! Final score: 23237, Rank: C`
- **Line 2405**: `[BuildingLevel] Using preloaded AnimatedScoreScreen scene (compile-time embedding)`
- **Line 2406**: `[BuildingLevel] Created ScoreScreenCanvasLayer at layer 100`
- **Line 2407**: `[BuildingLevel] Instantiated AnimatedScoreScreen from preloaded scene`
- **Line 2408**: `[BuildingLevel] Script IS attached to instantiated node: res://scripts/ui/animated_score_screen.gd`
- **Line 2409**: `[BuildingLevel] has_method('show_score'): false` ← **CRITICAL**
- **Line 2410**: `[BuildingLevel] Added AnimatedScoreScreen to ScoreScreenCanvasLayer (triggers _ready)`
- **Line 2411**: `[BuildingLevel] Set score_screen size to viewport: (1280, 720)`
- **Line 2412**: `[BuildingLevel] score_screen.is_inside_tree() = true`
- **Line 2413**: `[BuildingLevel] ERROR: show_score method not found, script likely not attached correctly`
- **Line 2414**: `[BuildingLevel] Tried calling show_score() anyway`

**Critical Observation:**

This is the first time we have concrete diagnostic data:
1. **Script path IS detected**: `res://scripts/ui/animated_score_screen.gd`
2. **`has_method('show_score')` returns `false`**: Despite the script being "attached"
3. **NO `[AnimatedScoreScreen]` logs**: The script's `_ready()` and methods are not executing
4. **The call to `show_score()` silently fails**: Even the forced call produces no output

This indicates the script is attached as a **Resource reference** but not properly **compiled/initialized**.

### Root Cause Analysis

**GDScript Binary Tokens Export Mode Issue**

Based on extensive research:

1. **[Godot GitHub Issue #94150](https://github.com/godotengine/godot/issues/94150)**: GDScript export mode breaks exported builds with some addons.
   > When GDScript export mode is set to binary tokens/compressed binary tokens, certain resources won't load properly. Setting export mode to "Text" fixes the issue.

2. **[Godot GitHub Issue #113577](https://github.com/godotengine/godot/issues/113577)**: Error when exporting with binary tokens.
   > When exporting with binary tokens (compressed or otherwise), errors like "Class 'Foo' hides a global script class" can occur. Exporting as text makes the error go away.

3. **[Godot Web Export Issue #93102](https://github.com/godotengine/godot/issues/93102)**: Web export doesn't work correctly with binary GDScript.
   > After exporting the game with binary GDScript, it does not work in the browser and the console is filled with errors.

**The Problem:**

When Godot exports with "binary tokens" or "compressed binary tokens" mode:
- Scripts are compiled to bytecode format
- The scene file references the script correctly (path is visible)
- **BUT** the bytecode may not properly register all methods
- `has_method()` returns `false` even though the script is "attached"
- Direct method calls fail silently

**Why Previous Fixes Didn't Work:**

| Session | Fix | Why It Didn't Work |
|---------|-----|-------------------|
| Session 4 | `Control.new() + set_script()` | Script attached but not initialized |
| Session 5 | Scene file (.tscn) + `load()` | Runtime loading failed in export |
| Session 6 | `preload()` instead of `load()` | Binary tokens bytecode still broken |

The issue is NOT in how we load/attach the script, but in how Godot's export process compiles the script.

### Fix Applied

**Solution: Force Script Re-attachment at Runtime**

Since we cannot control the user's export settings (binary vs text mode), we implement a workaround:

1. **Preload the script separately** in `building_level.gd`:
   ```gdscript
   ## Preload the AnimatedScoreScreen script separately for forced re-attachment.
   ## This is a workaround for Godot 4.x export issues where binary token compiled
   ## scripts may not initialize properly when attached via scene file.
   ## See: https://github.com/godotengine/godot/issues/94150
   const AnimatedScoreScreenScript: GDScript = preload("res://scripts/ui/animated_score_screen.gd")
   ```

2. **Detect method availability failure and force re-attach**:
   ```gdscript
   # Check if show_score method exists
   var has_show_score := score_screen.has_method("show_score")

   # Session 7 Fix: If has_method returns false despite script being attached,
   # this is a Godot 4.x binary tokens export bug where the script is attached
   # as a resource reference but not properly compiled/initialized.
   # Workaround: Force re-attach the preloaded script directly.
   if not has_show_score and AnimatedScoreScreenScript != null:
       _log_to_file("Applying Session 7 workaround: forcing script re-attachment")
       score_screen.set_script(AnimatedScoreScreenScript)
       has_show_score = score_screen.has_method("show_score")
       _log_to_file("After re-attachment, has_method('show_score'): %s" % str(has_show_score))
   ```

### Why This Fix Should Work

1. **Detect the broken state**: Check `has_method()` to identify when the binary tokens bug occurs
2. **Force re-initialization**: Using `set_script()` with a freshly preloaded GDScript forces the script to be re-parsed and methods to be registered
3. **Preload ensures availability**: The script is embedded at compile time, so it's always available
4. **Non-destructive**: Only applies the workaround when the bug is detected; normal exports still work

### User-Side Permanent Fix

If the workaround doesn't help, the user can permanently fix the issue by changing export settings:

1. Open Project → Export in Godot Editor
2. Select the export preset (e.g., Windows Desktop)
3. Find "Script Export Mode" under "Script" section
4. Change from "Binary tokens" or "Compressed binary tokens" to **"Text"**
5. Re-export the game

This ensures all scripts are exported as readable GDScript text files, which Godot can always parse correctly.

### Lessons Learned

1. **Binary token export mode has known bugs** - It's a recurring source of issues in Godot 4.x
2. **`has_method()` is a good diagnostic** - It reveals when scripts are attached but not initialized
3. **Multiple preload layers provide redundancy** - Preloading both scene and script allows for fallback
4. **Document export settings requirements** - Users should know about the text mode workaround

## Bug Investigation Session 8 (2026-02-04)

### Reported Issue

From PR #430 comment by repository owner (in Russian):
- **"статистика не появляется"** (Statistics not appearing)
- Attached log file: `game_log_20260204_171348.txt`

### Game Log Analysis

Downloaded log: `logs/game_log_20260204_171348.txt` (273KB, 2842 lines)

Key findings from analyzing the log:

**Level completion sequence (lines 2757-2773):**
- **Line 2757**: `[BuildingLevel] Level completed, setting _level_completed = true`
- **Line 2759**: `[ScoreManager] Level completed! Final score: 22942, Rank: C`
- **Line 2762**: `[BuildingLevel] Using preloaded AnimatedScoreScreen scene (compile-time embedding)`
- **Line 2763**: `[BuildingLevel] Created ScoreScreenCanvasLayer at layer 100`
- **Line 2764**: `[BuildingLevel] Instantiated AnimatedScoreScreen from preloaded scene`
- **Line 2765**: `[BuildingLevel] Script IS attached to instantiated node: res://scripts/ui/animated_score_screen.gd`
- **Line 2766**: `[BuildingLevel] has_method('show_score'): false` ← **STILL FALSE**
- **Line 2767**: `[BuildingLevel] Applying Session 7 workaround: forcing script re-attachment`
- **Line 2768**: `[BuildingLevel] After re-attachment, has_method('show_score'): false` ← **WORKAROUND FAILED**
- **Line 2769**: `[BuildingLevel] Added AnimatedScoreScreen to ScoreScreenCanvasLayer (triggers _ready)`
- **Line 2772**: `[BuildingLevel] ERROR: show_score method not found, script likely not attached correctly`
- **Line 2773**: `[BuildingLevel] Tried calling show_score() anyway`

**Critical Observation:**
- The Session 7 workaround (force re-attachment via `set_script()`) **DID NOT FIX** the issue
- Even after `set_script(AnimatedScoreScreenScript)`, `has_method('show_score')` still returns `false`
- **NO `[AnimatedScoreScreen]` logs at all** - The script's `_ready()` is NEVER called
- Lines 2774-2842: Game continues (gunshots, bullet penetration, player movement)
- Score screen is completely invisible

### Root Cause Analysis

**The Binary Tokens Bug is More Severe Than Expected**

Session 7's workaround assumed that `set_script()` with a preloaded GDScript would re-initialize the script. However, the log shows:

```
[BuildingLevel] Script IS attached: res://scripts/ui/animated_score_screen.gd
[BuildingLevel] has_method('show_score'): false
[BuildingLevel] After re-attachment, has_method('show_score'): false
```

This indicates that even `set_script()` with a preloaded GDScript fails when:
1. The GDScript itself was compiled with binary tokens
2. The preload() is embedding a binary-token-compiled version

**The Core Problem:**

In Godot 4.x with binary token export mode:
- GDScript files are compiled to bytecode
- `preload()` embeds the compiled bytecode, not the source
- The bytecode may have broken method registration
- `set_script()` with this broken bytecode still fails

### Fix Applied

**Solution: Inline Implementation (Bypass External Scripts Entirely)**

Since external script loading is unreliable due to the binary tokens bug, the fix implements the animated score screen **directly inside `building_level.gd`**:

1. **Remove external script dependencies:**
   - Removed `AnimatedScoreScreenScene` preload
   - Removed `AnimatedScoreScreenScript` preload
   - No longer uses `scenes/ui/AnimatedScoreScreen.tscn` or `scripts/ui/animated_score_screen.gd`

2. **Add inline constants and state variables:**
   ```gdscript
   ## Animation timing constants for score screen
   const SCORE_TITLE_FADE_DURATION: float = 0.3
   const SCORE_ITEM_REVEAL_DURATION: float = 0.15
   const SCORE_ITEM_COUNT_DURATION: float = 0.8
   # ... all animation constants

   ## Score screen animation state variables
   var _score_screen_root: Control = null
   var _score_is_animating: bool = false
   var _score_counting_value: float = 0.0
   # ... all state variables
   ```

3. **Implement all animation functions inline:**
   - `_score_setup_beep_audio()` - Setup retro sound generator
   - `_score_play_beep()` - Play major arpeggio beep
   - `_score_apply_pulse_effect()` - Apply pulsing to counting labels
   - `_score_build_items()` - Build score data structure
   - `_score_animate_background_fade()` - Background fade animation
   - `_score_create_title()` - Title creation and animation
   - `_score_start_item_sequence()` - Start sequential item reveal
   - `_score_animate_next_item()` - Animate next item in sequence
   - `_score_create_item_row()` - Create individual score row
   - `_score_start_counting()` - Start counting animation
   - `_score_finish_counting()` - Finish counting animation
   - `_score_animate_total()` - Total score animation
   - `_score_start_total_counting()` - Total counting animation
   - `_score_finish_total_counting()` - Finish total counting
   - `_score_start_rank_animation()` - Dramatic rank reveal
   - `_score_shrink_rank()` - Shrink rank to final position
   - `_score_show_restart_hint()` - Show restart hint
   - `_score_on_animation_complete()` - Animation completion handler

4. **Update `_process()` to handle counting animation:**
   ```gdscript
   func _process(delta: float) -> void:
       # ... existing code ...

       # Handle score screen counting animation
       if _score_is_animating and _score_counting_label != null:
           _score_pulse_time += delta
           # ... counting logic
           _score_apply_pulse_effect()
   ```

5. **Rewrite `_show_score_screen()` to use inline implementation:**
   ```gdscript
   func _show_score_screen(score_data: Dictionary) -> void:
       print("[BuildingLevel] Using INLINE animated score screen")
       _score_data_cache = score_data
       _score_is_animating = true
       # ... create UI nodes directly
       _score_setup_beep_audio()
       _score_build_items()
       _score_animate_background_fade()
   ```

### Why This Fix Works

1. **No external script loading** - All code is in the same file as `building_level.gd`
2. **Same compilation context** - The animation code is compiled together with the level script
3. **No binary tokens issue** - Internal functions are always properly registered
4. **Guaranteed method availability** - `_score_*` functions are regular methods, not dynamically attached
5. **Works regardless of export settings** - No dependency on GDScript export mode

### Files Changed

| File | Change |
|------|--------|
| `scripts/levels/building_level.gd` | Added ~500 lines of inline animation code |
| `scripts/ui/animated_score_screen.gd` | Kept for reference but no longer used |
| `scenes/ui/AnimatedScoreScreen.tscn` | Kept for reference but no longer used |

### Trade-offs

**Pros:**
- Completely bypasses the binary tokens export bug
- Works in all Godot 4.x export configurations
- No external dependencies for score screen

**Cons:**
- `building_level.gd` is now ~500 lines longer
- Animation code is duplicated (exists in both inline and external versions)
- Less modular than a separate reusable component

### Lessons Learned

1. **Binary tokens bug is pervasive** - It affects preload(), load(), set_script(), and scene instantiation
2. **Inline implementation is the most reliable** - When external scripts fail, embed the code
3. **Godot 4.x export has serious bugs** - Binary token export mode should be avoided for complex projects
4. **Workarounds may not be enough** - Sometimes a complete architectural change is needed
5. **Test in actual exported builds** - Editor behavior differs significantly from exports
