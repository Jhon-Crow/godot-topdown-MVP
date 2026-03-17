# Case Study: Issue #944 - Tutorial Hint Animation System

## Issue Summary

**Issue**: [#944 - update строки обучения](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/944)
**PR**: [#1012](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1012)

### Original Requirements (Russian)
1. выполненное действие зачёркивается толстой линией и исчезает (добавь эту анимацию).
2. нажатое сочетание клавиш в многосоставном действии должно зачёркиваться с анимацией (не вся строка, а только пройденный шаг). после завершения многосоставного действия строка не должна зачёркиваться второй раз, а просто исчезает.
3. появление новых строк обучения должно происходить с анимацией

### Translated Requirements
1. Completed action should be struck through with a thick line and disappear (add this animation).
2. Pressed key combination in multi-step actions should be struck through with animation (not the whole line, only the completed step). After completing a multi-step action, the line should NOT be struck through a second time - it should just disappear.
3. New tutorial hint lines should appear with animation.

## Timeline of Events

### Initial Solution Draft (Session 1)
- Created fade-in animation for new hints (0.3s duration)
- Implemented strikethrough using BBCode `[s]` tags before fade-out
- Added tracking for multi-step hints to prevent double strikethrough
- **Location**: Only applied to `tutorial_level.gd`

### Feedback from Repository Owner
The owner (Jhon-Crow) provided feedback on the PR:

> 1. анимации добавились в Training а должны добавиться везде, где есть строки обучения
> 2. зачёркивание должно происходить с анимацией (черта должна проводиться слева направо).

Translation:
1. Animations were added to Training but should be added everywhere tutorial hints exist
2. Strikethrough should happen WITH animation (the line should be drawn from left to right)

## Root Cause Analysis

### Problem 1: Incomplete Scope
The initial implementation only modified `tutorial_level.gd` but tutorial hints also exist in:
- `labyrinth_level.gd` (Laboratory level)

Both levels have independent implementations of `_add_tutorial_hint()` and `_dismiss_tutorial_hint()` functions. The animations were not propagated to the labyrinth level.

### Problem 2: Misunderstanding of "Animated Strikethrough"
The original requirement "зачёркивается с анимацией" (struck through with animation) was interpreted as:
- Adding `[s]` BBCode tag instantly, then fading out

However, the owner clarified that the strikethrough line itself should animate:
- "черта должна проводиться слева направо" (the line should be drawn from left to right)

This requires a more sophisticated approach:
- Option A: Custom RichTextEffect shader that reveals strikethrough progressively
- Option B: Character-by-character strikethrough reveal using `visible_characters` or similar
- Option C: Overlay Line2D or custom drawing that animates across the text

## Technical Research

### Godot BBCode Limitations
Standard BBCode `[s]` tag applies strikethrough instantly - there is no built-in animation support.

### Possible Solutions for Animated Strikethrough

1. **Custom RichTextEffect** (Recommended)
   - Create a GDScript class extending `RichTextEffect`
   - Use `_process_custom_fx()` to control per-character effects
   - Animate based on `char_fx.elapsed_time` and `char_fx.absolute_index`
   - References: [Godot RichTextEffect Documentation](https://docs.godotengine.org/en/stable/classes/class_richtexteffect.html)

2. **Line2D Overlay**
   - Draw a horizontal Line2D over the text
   - Animate its end point from left to right
   - Simpler but less integrated with text rendering

3. **Character-by-character [s] tag reveal**
   - Progressively wrap more characters in `[s]` tags over time
   - Update `label.text` each frame with growing strikethrough region

## Files Involved

| File | Role | Animation Status |
|------|------|------------------|
| `scripts/levels/tutorial_level.gd` | Tutorial (Training) level hints | Has animations |
| `scripts/levels/labyrinth_level.gd` | Laboratory level hints | Missing animations |

## Solution Plan

1. **Copy animation logic from tutorial_level.gd to labyrinth_level.gd**
   - Add animation constants (HINT_FADE_IN_DURATION, HINT_FADE_OUT_DURATION, HINT_STRIKETHROUGH_DURATION)
   - Add animation tracking variables (_animating_hints, _hint_is_multistep_completed)
   - Update `_add_tutorial_hint()` with fade-in animation
   - Update `_dismiss_tutorial_hint()` with strikethrough + fade-out animation
   - Add helper functions for animations

2. **Implement animated strikethrough (left-to-right)**
   - Create custom RichTextEffect for progressive strikethrough
   - Register the effect with RichTextLabel
   - Use custom BBCode tag like `[anim_strike]` instead of `[s]`

## Implemented Solution (Session 3)

After receiving additional feedback from the owner:
> - анимированное зачёркивание должно быть вместо каждого зачёркивания (сейчас выглядит некрасиво - зачёркивается уже зачёркнутое)
> - то есть зачёркивание должно продлеваться после выполненного действия
> - так же анимированное зачёркивание сейчас работает не на все строки
> - зачёркивающая линия слишком непрозрачная

Translation:
- Animated strikethrough should replace EVERY strikethrough (currently looks ugly - already struck text gets struck again)
- The strikethrough should EXTEND after each completed action
- Animated strikethrough doesn't work on ALL hint lines
- The strikethrough line is too opaque

### Final Implementation

**Approach: Persistent Line2D with Progressive Extension**

Instead of using BBCode `[s]` tags, we now use a persistent Line2D overlay attached to each hint:

1. **Line2D Creation**: Each hint gets a Line2D child when created via `_add_hint()`
2. **Progressive Extension**: As each step completes, `_extend_hint_strikethrough()` animates the Line2D from its current position to the new target position
3. **Visual Styling**: Line2D is semi-transparent (0.6 opacity) and thin (1.5px width) to match the subtle appearance of standard strikethrough
4. **Dismissal Animation**: When the hint is dismissed, the Line2D extends to 100% width before the label fades out

### Key Changes

| Before | After |
|--------|-------|
| BBCode `[s]` tags for instant strikethrough | Line2D overlay for animated strikethrough |
| Strikethrough applied per-step via BBCode | Progressive Line2D extension via tweens |
| Solid grey `[s]` appearance | Semi-transparent Line2D (0.6 opacity, 1.5px) |
| Double strikethrough on multi-step hints | Single progressive strikethrough line |

### New Functions Added

- `_extend_hint_strikethrough(hint_key, target_progress)` - Animates Line2D extension
- `_hint_strike_lines: Dictionary` - Tracks Line2D nodes per hint
- `_hint_strike_progress: Dictionary` - Tracks current strikethrough progress (0.0-1.0)

### Files Modified

| File | Changes |
|------|---------|
| `scripts/levels/tutorial_level.gd` | Replaced BBCode [s] with Line2D, added progressive extension |
| `scripts/levels/labyrinth_level.gd` | Same changes applied |

## Session 4: Multi-line Support and Positioning Fixes

After Session 3, the owner provided additional feedback (comment #4042518360):

> 1. анимация выглядит хорошо, но черта слишком высоко (должна быть по центру строки)
> 2. если обучение состоит из 2 и более строк (как на скриншоте) должны зачёркиваться все строки по очереди (сейчас только верхняя)
> 3. некоторые действия зачёркиваются не полностью

Translation:
1. Animation looks good, but the line is too high (should be centered on the text line)
2. If tutorial consists of 2+ lines, ALL lines should be struck through sequentially (currently only the top one)
3. Some actions are not fully struck through

### Root Cause Analysis (Session 4)

**Issue 1: Line positioned too high**
- `line_y := 10.0` was hardcoded, assuming font size ~20 with center at ~10
- However, Line2D position is relative to label origin, and baseline/center varies
- Fix: Calculate vertical center based on font metrics (~55% of line height for proper center)

**Issue 2: Only top line struck through**
- The code assumed single-line text with just 2 Line2D points
- Multi-line text (e.g., "Передёрни затвор" wrapping to second line) needs multiple line segments
- Fix: Detect line count via `get_content_height()` and create 2 points per line

**Issue 3: Incomplete strikethrough**
- Using `custom_minimum_size.x` (300) as width, but actual text content width may differ
- Fix: Use `get_content_width()` for actual rendered text width

### Technical Solution (Session 4)

**Multi-line Strikethrough Architecture:**

1. **Line Count Detection**: After label is added to scene tree, use `call_deferred()` to calculate:
   ```gdscript
   var content_height := label.get_content_height()
   var line_count := maxi(1, roundi(content_height / LINE_HEIGHT))
   ```

2. **Line2D Point Setup**: Create 2 points per line (start and end):
   ```gdscript
   for line_idx in range(line_count):
       var line_y := line_idx * LINE_HEIGHT + LINE_HEIGHT * 0.55
       strike_line.add_point(Vector2(0, line_y))  # Start point
       strike_line.add_point(Vector2(0, line_y))  # End point (animated)
   ```

3. **Progress Distribution**: Progress 0.0-1.0 spans all lines:
   - 2 lines: progress 0.5 = line 1 fully struck, line 2 not started
   - 2 lines: progress 0.75 = line 1 fully struck, line 2 at 50%

4. **Per-line Progress Calculation**:
   ```gdscript
   var line_start_progress := float(line_idx) / line_count
   var line_end_progress := float(line_idx + 1) / line_count
   var line_progress := clamp((progress - line_start_progress) / (line_end_progress - line_start_progress), 0.0, 1.0)
   ```

### New Data Structures

| Variable | Type | Purpose |
|----------|------|---------|
| `_hint_line_counts` | Dictionary (String -> int) | Tracks line count per hint |

### New Functions Added

| Function | Purpose |
|----------|---------|
| `_setup_strikethrough_lines()` | Deferred setup of Line2D points after layout |
| `_update_strikethrough_points()` | Update all Line2D segments based on progress |

### Constants Used

| Constant | Value | Purpose |
|----------|-------|---------|
| `LINE_HEIGHT` | 26.0 | Font size (20) + default line spacing |
| Vertical center | `LINE_HEIGHT * 0.55` | Proper center accounting for baseline |

## Session 5: Fix Diagonal Connector Between Lines

After Session 4, the owner provided additional feedback (comment #4069575813):

> уже ближе к тому, что я хочу, но в конце строки линия должна прерываться, сейчас она тянется к началу следующей строки

Translation:
> Already closer to what I want, but at the end of a line the line should break — currently it extends to the beginning of the next line.

### Root Cause Analysis (Session 5)

**Problem: Line2D polyline connects all points sequentially**

The previous implementation used a **single Line2D** with 2 points per text line (e.g., 4 points for a 2-line hint). The problem is that `Line2D` draws a continuous polyline connecting all points in order:

```
point[0] (0, line_y_0) → point[1] (text_width, line_y_0)  ← Line 1 ✓
                                   ↓  (diagonal connector!)
point[2] (0, line_y_1) ← point[1] connects here ← Bug!
point[2] (0, line_y_1) → point[3] (text_width, line_y_1)  ← Line 2 ✓
```

Because Line2D is a polyline (all points connected), when line 1 ends at `(text_width, line_y_0)` and line 2 starts at `(0, line_y_1)`, there is an unwanted diagonal segment connecting them.

### Technical Solution (Session 5)

**Use separate Line2D nodes per text line:**

Instead of one Line2D with 4 points, use two Line2D nodes each with 2 points. Each Line2D only renders its own line segment with no connection to other lines.

**Before (broken):**
```gdscript
# Single Line2D: points connected sequentially, creates diagonal
var strike_line := Line2D.new()
strike_line.add_point(Vector2(0, line_y_0))       # Line 1 start
strike_line.add_point(Vector2(text_width, line_y_0))  # Line 1 end  ← connects to ↓
strike_line.add_point(Vector2(0, line_y_1))       # Line 2 start (diagonal connector)
strike_line.add_point(Vector2(text_width, line_y_1))  # Line 2 end
```

**After (fixed):**
```gdscript
# Separate Line2D per line: no cross-line connections
for line_idx in range(line_count):
    var seg := Line2D.new()
    seg.add_point(Vector2(0, line_y))        # Start
    seg.add_point(Vector2(0, line_y))        # End (animated)
    label.add_child(seg)
    lines.append(seg)
_hint_strike_lines[hint_key] = lines  # Array instead of single Line2D
```

### Data Structure Change

| Variable | Before | After |
|----------|--------|-------|
| `_hint_strike_lines` | `Dict[String → Line2D]` | `Dict[String → Array[Line2D]]` |
| `_tutorial_hint_strike_lines` | `Dict[String → Line2D]` | `Dict[String → Array[Line2D]]` |

### Functions Updated

| Function | Change |
|----------|--------|
| `_add_hint()` / `_add_tutorial_hint()` | Stores `[]` (empty array), no pre-created Line2D |
| `_setup_strikethrough_lines()` | Creates one Line2D per line, stores in array |
| `_extend_hint_strikethrough()` | Accepts array, checks `is_empty()` instead of `is_instance_valid()` |
| `_update_strikethrough_points()` | Iterates array, updates end point of each Line2D |
| `_animate_hint_strikethrough_and_fade()` | Works with array |

## References

- [BBCode in RichTextLabel - Godot Docs](https://docs.godotengine.org/en/stable/tutorials/ui/bbcode_in_richtextlabel.html)
- [RichTextEffect - Godot Docs](https://docs.godotengine.org/en/stable/classes/class_richtexteffect.html)
- [Line2D - Godot Docs](https://docs.godotengine.org/en/stable/classes/class_line2d.html)
- [godot-text_effects plugin](https://github.com/teebarjunk/godot-text_effects)
- [Godot Forum - Custom RichTextEffect](https://godotforums.org/d/26200-custom-richtexteffect-help)

## Directory Contents

- `logs/solution-draft-log-pr-1773260976452.txt` - Complete execution trace of initial solution
- `issue-details.json` - GitHub issue metadata
- `pr-details.json` - Pull request metadata
- `pr-comments.json` - Pull request comments
- `pr-diff.txt` - Current PR diff
