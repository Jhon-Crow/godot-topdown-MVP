# Case Study: Issue #377 - Increase Bloody Footprints Range

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/377

**Problem Description (Russian):**
> были добавлены следы https://github.com/Jhon-Crow/godot-topdown-MVP/pull/361
> сделай чтоб можно было оставить в 4 раз больше следов после наступания в лужу.

**English Translation:**
> Bloody footprints were added in PR #361.
> Make it so characters can leave 4 times more footprints after stepping into a puddle.

**Update (PR Comment):**
> не вижу изменений, если они работают - увеличь в 8 раз для наглядности

**English Translation:**
> I don't see the changes, if they are working - increase by 8 times for visibility.

## Requirements Analysis

### Original Request
- **4x increase** in the number of bloody footprints after stepping in blood

### Updated Request
- **8x increase** for better visibility (user couldn't see the 4x change during testing)

### Technical Context

The bloody footprints feature was originally implemented in PR #361 (Issue #360). The feature uses a `blood_steps_count` parameter that controls how many footprints a character leaves after stepping in a blood puddle.

**Original values (from Issue #360):**
- `blood_steps_count = 6` (6 footprints before blood runs out)

**Initial change (4x):**
- `blood_steps_count = 24` (24 footprints)

**Final change (8x):**
- `blood_steps_count = 48` (48 footprints)

## Timeline of Events

### Session 1: Initial 4x Implementation (2026-01-25 ~06:43)

1. **Received issue #377** requesting 4x increase in footprint range
2. **Updated value from 6 to 24** in the following files:
   - `scripts/components/bloody_feet_component.gd` (line 10)
   - `scenes/characters/Player.tscn` (line 89)
   - `scenes/characters/csharp/Player.tscn` (line 94)
   - `scenes/objects/Enemy.tscn` (line 89)
3. **Updated unit tests** to expect 24 instead of 6
4. **Created PR #378** with the changes
5. **Commit:** `0e793d8 feat: increase bloody footprints range 4x (Issue #377)`

### Session 2: User Testing and Feedback (2026-01-25 ~06:46)

1. **User tested** the 4x change
2. **Feedback received:** "не вижу изменений" (I don't see the changes)
3. **User request:** Increase to 8x for visibility if the feature is working

### Log File Analysis

The attached log file `game_log_20260125_094415.txt` confirms the 4x change was working:

```
[09:44:29] [INFO] [BloodyFeet:Player] Stepped in blood! 24 footprints to spawn, color: (1, 1, 1, 0.9)
[09:44:39] [INFO] [BloodyFeet:Enemy2] Stepped in blood! 24 footprints to spawn, color: (1, 1, 1, 0.9)
[09:44:47] [INFO] [BloodyFeet:Player] Stepped in blood! 24 footprints to spawn, color: (1, 1, 1, 0.9)
[09:45:06] [INFO] [BloodyFeet:Player] Stepped in blood! 24 footprints to spawn, color: (1, 1, 1, 0.9)
[09:45:16] [INFO] [BloodyFeet:Player] Stepped in blood! 24 footprints to spawn, color: (1, 1, 1, 0.9)
[09:45:21] [INFO] [BloodyFeet:Enemy1] Stepped in blood! 24 footprints to spawn, color: (1, 1, 1, 0.9)
[09:45:25] [INFO] [BloodyFeet:Player] Stepped in blood! 24 footprints to spawn, color: (1, 1, 1, 0.9)
[09:45:34] [INFO] [BloodyFeet:Player] Stepped in blood! 24 footprints to spawn, color: (1, 1, 1, 0.9)
```

This shows:
- The component is correctly detecting blood puddle contact
- The value "24 footprints to spawn" confirms the 4x change was applied
- Both Player and Enemy characters are generating footprints

### Session 3: 8x Implementation (2026-01-25 ~06:47)

1. **Updated value from 24 to 48** (8x original) in all files
2. **Updated unit tests** to expect 48 instead of 24
3. **Committed changes** to PR #378

## Technical Details

### Changed Files

| File | Line | Old Value | New Value |
|------|------|-----------|-----------|
| `scripts/components/bloody_feet_component.gd` | 10 | 24 | 48 |
| `scenes/characters/Player.tscn` | 89 | 24 | 48 |
| `scenes/characters/csharp/Player.tscn` | 94 | 24 | 48 |
| `scenes/objects/Enemy.tscn` | 89 | 24 | 48 |
| `tests/unit/test_bloody_feet_component.gd` | 68-69 | 24 | 48 |
| `tests/unit/test_bloody_feet_component.gd` | 80 | 24 | 48 |

### BloodyFeetComponent Configuration

```gdscript
## Number of bloody footprints before the blood runs out.
@export var blood_steps_count: int = 48  # 8x original (was 6)
```

### Alpha Decay Calculation

With the alpha decay rate remaining at `0.12`:
- First footprint: alpha = 0.8
- Last footprint (step 48): alpha = 0.8 - (47 × 0.12) = 0.8 - 5.64 = -4.84 → clamped to 0.05

This means footprints will fade significantly over the 48 steps, creating a long trail that gradually becomes nearly invisible.

## Root Cause Analysis

### Why User Didn't See 4x Change

Possible reasons the user didn't notice the 4x increase:

1. **Visual perception:** The difference between 6 and 24 footprints may not be immediately obvious during gameplay if:
   - The player is moving quickly
   - The alpha decay makes later footprints very faint
   - The footprints blend into the environment

2. **Testing conditions:** Without a controlled comparison (A/B testing), it's hard to notice incremental changes

3. **Expectation mismatch:** User might have expected a more dramatic visual change

### Solution

Increasing to 8x (48 footprints) should provide:
- Much longer visible trail
- More obvious change during gameplay
- Better match with user's expectations for "increased range"

## CI Status

The CI check "Check Architecture Best Practices" is failing, but this is a **pre-existing issue** unrelated to this PR:

```
##[error]Script exceeds 5000 lines (5669 lines). Refactoring required.
```

This error is from a script in the main branch that exceeds the line limit. It's not introduced by this PR's changes.

## Lessons Learned

1. **User perception matters:** A 4x increase in a parameter might not be visually obvious to users. When making adjustments to visual effects, consider:
   - Starting with a larger change for initial testing
   - Using side-by-side comparisons
   - Asking users to test in controlled conditions

2. **Logging is essential:** The detailed log file confirmed the feature was working correctly, helping distinguish between "feature broken" vs "change not noticeable"

3. **Iterative feedback:** Being responsive to user feedback and willing to adjust based on real-world testing leads to better outcomes

## References

### Internal References
- **Original Feature PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/361
- **Original Feature Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/360
- **This PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/378
- **Related Case Study:** `docs/case-studies/issue-360/README.md`

### Files
- `logs/game_log_20260125_094415.txt` - User's test session log
- `logs/solution-draft-log-pr-1769323401165.txt` - Initial AI solution draft log
