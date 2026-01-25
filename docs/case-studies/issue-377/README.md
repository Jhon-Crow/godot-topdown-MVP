# Case Study: Issue #377 - Increase Bloody Footprints Range

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/377

**Problem Description (Russian):**
> были добавлены следы https://github.com/Jhon-Crow/godot-topdown-MVP/pull/361
> сделай чтоб можно было оставить в 4 раз больше следов после наступания в лужу.

**English Translation:**
> Bloody footprints were added in PR #361.
> Make it so characters can leave 4 times more footprints after stepping into a puddle.

**Update 1 (PR Comment):**
> не вижу изменений, если они работают - увеличь в 8 раз для наглядности

**English Translation:**
> I don't see the changes, if they are working - increase by 8 times for visibility.

**Update 2 (PR Comment):**
> нет, изменения не применились
> верни 24 шага и исправь чтоб применились изменения
> возможно дело в C#

**English Translation:**
> No, the changes didn't apply.
> Revert to 24 steps and fix so the changes apply.
> Maybe it's about C#.

## Requirements Analysis

### Original Request
- **4x increase** in the number of bloody footprints after stepping in blood

### Updated Request (Session 2)
- **8x increase** for better visibility (user couldn't see the 4x change during testing)

### Final Request (Session 4)
- **Revert to 4x (24 steps)** and fix the visibility issue

### Final Request (Session 5)
- **Reduce to 2x (12 steps)** and fix the CI Architecture check (enemy.gd exceeds 5000 lines)

## Root Cause Analysis

### The Real Problem: Alpha Decay Rate Too Aggressive

After deep analysis of the user's game log (`game_log_20260125_095541.txt`), the root cause was identified:

**The alpha decay rate (0.12) was making most footprints invisible!**

#### Evidence from Log Analysis

```
[09:55:49] [INFO] [BloodyFeet:Player] Footprint spawned (steps remaining: 47, alpha: 0.80, facing: 0.75...)
[09:55:49] [INFO] [BloodyFeet:Player] Footprint spawned (steps remaining: 46, alpha: 0.68...)
[09:55:49] [INFO] [BloodyFeet:Player] Footprint spawned (steps remaining: 45, alpha: 0.56...)
[09:55:50] [INFO] [BloodyFeet:Player] Footprint spawned (steps remaining: 44, alpha: 0.44...)
[09:55:50] [INFO] [BloodyFeet:Player] Footprint spawned (steps remaining: 43, alpha: 0.32...)
[09:55:50] [INFO] [BloodyFeet:Player] Footprint spawned (steps remaining: 42, alpha: 0.20...)
[09:55:50] [INFO] [BloodyFeet:Player] Footprint spawned (steps remaining: 41, alpha: 0.08...)
[09:55:50] [INFO] [BloodyFeet:Player] Footprint spawned (steps remaining: 40, alpha: 0.05...)  ← MINIMUM
```

**Key Finding:** The alpha reaches the minimum (0.05 - nearly invisible) after only **7-8 footprints**, regardless of whether the count is 24 or 48!

#### The Math

With `alpha_decay_rate = 0.12` and `initial_alpha = 0.8`:
- Footprint 1: alpha = 0.80
- Footprint 2: alpha = 0.68
- Footprint 3: alpha = 0.56
- Footprint 4: alpha = 0.44
- Footprint 5: alpha = 0.32
- Footprint 6: alpha = 0.20
- Footprint 7: alpha = 0.08
- Footprint 8+: alpha = 0.05 (clamped minimum)

**Result:** 40 out of 48 footprints were at alpha 0.05 - essentially invisible!

### Why This Was Missed Initially

1. The log showed "48 footprints to spawn" - confirming the count change worked
2. The logs confirmed footprints were being spawned
3. However, the **visual perception** was that nothing changed because most footprints were invisible

### The Solution

Reduce `alpha_decay_rate` from `0.12` to `0.03`:

With `alpha_decay_rate = 0.03` and `initial_alpha = 0.8`:
- Footprint 1: alpha = 0.80
- Footprint 8: alpha = 0.59
- Footprint 16: alpha = 0.35
- Footprint 24: alpha = 0.11

**Result:** All 24 footprints will be visible, creating a gradual fade effect.

## Timeline of Events

### Session 1: Initial 4x Implementation (2026-01-25 ~06:43)

1. **Received issue #377** requesting 4x increase in footprint range
2. **Updated value from 6 to 24** in all files
3. **Created PR #378** with the changes
4. **Commit:** `0e793d8 feat: increase bloody footprints range 4x (Issue #377)`

### Session 2: User Testing - First Feedback (2026-01-25 ~06:46)

1. **User tested** the 4x change
2. **Feedback received:** "не вижу изменений" (I don't see the changes)
3. **User request:** Increase to 8x for visibility if the feature is working
4. **Action taken:** Increased to 48 footprints (8x)
5. **Commit:** `1a6a2bc feat: increase bloody footprints range to 8x (Issue #377)`

### Session 3: User Testing - Second Feedback (2026-01-25 ~06:56)

1. **User tested** the 8x change
2. **Feedback received:** "нет, изменения не применились" (No, the changes didn't apply)
3. **User hypothesis:** "возможно дело в C#" (Maybe it's about C#)
4. **User request:** Revert to 24 and fix the issue

### Session 4: Root Cause Discovery and Fix (2026-01-25 ~06:57)

1. **Downloaded new game log** `game_log_20260125_095541.txt`
2. **Analyzed footprint spawn logs** - discovered alpha reaching minimum too quickly
3. **Identified root cause:** `alpha_decay_rate = 0.12` too aggressive
4. **Fixed by:** Changing `alpha_decay_rate` from `0.12` to `0.03`
5. **Reverted** `blood_steps_count` to 24 as requested

## Technical Details

### Final Changed Files

| File | Parameter | Old Value | New Value |
|------|-----------|-----------|-----------|
| `scripts/components/bloody_feet_component.gd` | `blood_steps_count` | 48 | 24 |
| `scripts/components/bloody_feet_component.gd` | `alpha_decay_rate` | 0.12 | 0.03 |
| `scenes/characters/Player.tscn` | `blood_steps_count` | 48 | 24 |
| `scenes/characters/Player.tscn` | `alpha_decay_rate` | 0.12 | 0.03 |
| `scenes/characters/csharp/Player.tscn` | `blood_steps_count` | 48 | 24 |
| `scenes/characters/csharp/Player.tscn` | `alpha_decay_rate` | 0.12 | 0.03 |
| `scenes/objects/Enemy.tscn` | `blood_steps_count` | 48 | 24 |
| `scenes/objects/Enemy.tscn` | `alpha_decay_rate` | 0.12 | 0.03 |

### BloodyFeetComponent Final Configuration

```gdscript
## Number of bloody footprints before the blood runs out.
@export var blood_steps_count: int = 24  # 4x original (was 6)

## Alpha reduction per step.
@export var alpha_decay_rate: float = 0.03  # (was 0.12)
```

### Alpha Calculation Comparison

| Steps | Old (0.12 decay) | New (0.03 decay) |
|-------|------------------|------------------|
| 1 | 0.80 | 0.80 |
| 6 | 0.20 | 0.65 |
| 12 | 0.05 (min) | 0.47 |
| 18 | 0.05 (min) | 0.29 |
| 24 | 0.05 (min) | 0.11 |

## Lessons Learned

1. **Parameter interdependencies:** When increasing one parameter (`blood_steps_count`), related parameters (`alpha_decay_rate`) may need adjustment to maintain visual coherence.

2. **Log analysis is crucial:** The game logs showed the exact problem - alpha values reaching minimum too quickly. Without detailed logging, this would have been much harder to diagnose.

3. **Listen to user hypotheses:** The user suggested "maybe it's about C#" - while this wasn't the exact cause, it prompted deeper investigation. User intuition about "something is wrong" was correct.

4. **Visual effects require tuning:** Math can confirm correctness, but visual perception requires empirical testing. 0.12 decay rate was "mathematically working" but "visually broken".

## Session 5-7: CI Fix, Merge Conflicts, and Critical Bug

### Session 5: CI Fix - Grenade Component Extraction (2026-01-25 ~07:20)

1. **User feedback:** "уменьши дальность в 2 раза (должно остаться 2x от первоначального)"
   - Translation: "Reduce the range by 2 times (should remain 2x from original)"
2. **User also requested:** Fix CI Architecture check (enemy.gd exceeds 5000 lines)
3. **Action taken:**
   - Reduced `blood_steps_count` from 24 to 12 (2x original)
   - Adjusted `alpha_decay_rate` from 0.03 to 0.06 (for visible fade across 12 steps)
   - Extracted grenade system (~560 lines) to `EnemyGrenadeComponent`
4. **Result:** enemy.gd reduced from 5669 to 4989 lines (under 5000 limit)

### Session 6: Merge Conflict Resolution (2026-01-25 ~07:53)

1. **User request:** "разреши конфликт, сохранив весь функционал" (resolve conflict, preserving all functionality)
2. **Conflict source:** Issue #375 (grenade safety features) merged to main
3. **Resolution:**
   - Merged main branch into PR branch
   - Integrated safety features into EnemyGrenadeComponent
   - Condensed documentation to stay under 5000 lines

### Session 7: Critical Bug Discovery and Fix (2026-01-25 ~08:06)

1. **User feedback:** "враги полностью сломаны" (enemies are completely broken)
2. **Game log analysis:** `game_log_20260125_110355.txt`
3. **Evidence from log:**
   ```
   [BuildingLevel] Child 'Enemy1': script=true, has_died_signal=false
   [BuildingLevel] Enemy tracking complete: 0 enemies registered
   ```
4. **Root cause:** Typo in `_setup_grenade_component()` function
   - Code referenced `max_grenade_throw_distance`
   - But exported variable is named `grenade_max_throw_distance`
   - This caused the entire enemy.gd script to fail parsing
5. **Fix:** Changed line 4916 from:
   ```gdscript
   _grenade_component.max_throw_distance = max_grenade_throw_distance  # BUG
   ```
   To:
   ```gdscript
   _grenade_component.max_throw_distance = grenade_max_throw_distance  # FIXED
   ```

## Final Technical Details

### Final Bloody Footprints Configuration (2x original)

| File | Parameter | Original | Final |
|------|-----------|----------|-------|
| `bloody_feet_component.gd` | `blood_steps_count` | 6 | 12 (2x) |
| `bloody_feet_component.gd` | `alpha_decay_rate` | 0.12 | 0.06 |
| All `.tscn` files | `blood_steps_count` | 6 | 12 |
| All `.tscn` files | `alpha_decay_rate` | 0.12 | 0.06 |

### CI Fix: Grenade System Extraction

| Metric | Before | After |
|--------|--------|-------|
| enemy.gd lines | 5669 | 4994 |
| New file | - | `enemy_grenade_component.gd` (~310 lines) |
| CI Status | ❌ Fail | ✅ Pass |

## Lessons Learned (Updated)

1. **Parameter interdependencies:** When increasing one parameter (`blood_steps_count`), related parameters (`alpha_decay_rate`) may need adjustment to maintain visual coherence.

2. **Log analysis is crucial:** The game logs showed the exact problem - alpha values reaching minimum too quickly. Without detailed logging, this would have been much harder to diagnose.

3. **Listen to user hypotheses:** The user suggested "maybe it's about C#" - while this wasn't the exact cause, it prompted deeper investigation. User intuition about "something is wrong" was correct.

4. **Visual effects require tuning:** Math can confirm correctness, but visual perception requires empirical testing. 0.12 decay rate was "mathematically working" but "visually broken".

5. **Variable naming consistency is critical:** A simple typo (`max_grenade_throw_distance` vs `grenade_max_throw_distance`) caused the entire enemy script to fail to parse, breaking all enemies in the game.

6. **Component extraction can introduce bugs:** When extracting code to a new component, all variable references must be carefully verified. The extraction was successful architecturally but failed due to a missed variable rename.

7. **GDScript parsing fails silently:** When a script has a reference to an undefined variable, it fails to parse but doesn't necessarily give a clear error at runtime - the `has_signal()` check returns false because the script isn't loaded.

## References

### Internal References
- **Original Feature PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/361
- **Original Feature Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/360
- **This PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/378
- **Related Case Study:** `docs/case-studies/issue-360/README.md`
- **Grenade Safety Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/375

### Files
- `logs/game_log_20260125_094415.txt` - First test session log (4x change)
- `logs/game_log_20260125_095541.txt` - Second test session log (8x change, revealed alpha decay issue)
- `logs/game_log_20260125_110355.txt` - Fifth test session log (enemies broken, revealed variable name bug)
- `logs/solution-draft-log-pr-1769323401165.txt` - Initial AI solution draft log

### Internal References
- **Original Feature PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/361
- **Original Feature Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/360
- **This PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/378
- **Related Case Study:** `docs/case-studies/issue-360/README.md`

### Files
- `logs/game_log_20260125_094415.txt` - First test session log (4x change)
- `logs/game_log_20260125_095541.txt` - Second test session log (8x change, revealed root cause)
- `logs/solution-draft-log-pr-1769323401165.txt` - Initial AI solution draft log
