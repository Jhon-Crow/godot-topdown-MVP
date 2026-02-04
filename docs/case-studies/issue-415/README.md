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

## Related Resources

- [Hotline Miami Scoring Wiki](https://hotlinemiami.fandom.com/wiki/Scoring)
- [CodePen HM2 Score Recreation](https://codepen.io/nmbusman/pen/oLybYW)
- [Godot Forum: Animated Numbers](https://forum.godotengine.org/t/score-counter-for-a-game-over-screen/74208)
- [Free Retro Arcade Sounds](https://www.themotionmonkey.co.uk/free-resources/retro-arcade-sounds/)
