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
2026-02-03 15:23:13 - Owner reports bugs in PR comment
2026-02-03 17:53:33 - Fix session started
```

## Related Resources

- [Hotline Miami Scoring Wiki](https://hotlinemiami.fandom.com/wiki/Scoring)
- [CodePen HM2 Score Recreation](https://codepen.io/nmbusman/pen/oLybYW)
- [Godot Forum: Animated Numbers](https://forum.godotengine.org/t/score-counter-for-a-game-over-screen/74208)
- [Free Retro Arcade Sounds](https://www.themotionmonkey.co.uk/free-resources/retro-arcade-sounds/)
