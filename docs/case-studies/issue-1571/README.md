# Case Study: Issue #1571 — Snowfall Broken After Fade-Out Fix

## Summary

After PR #1572 was submitted to fix snowflake fade-out (issue #1571), the owner reported
**"вообще не работает снегопад"** ("the snowfall doesn't work at all") with a game log
(`game_log_20260326_142911.txt`). This case study documents the root cause analysis and fix.

---

## Timeline of Events

| Date (UTC) | Event |
|---|---|
| 2026-03-26 11:15 | PR #1572 submitted — adds `color_ramp` gradient for fade-out |
| 2026-03-26 11:17 | Automated monitor marks PR "ready to merge" |
| 2026-03-26 11:30 | Owner tests the build and reports snowfall completely broken |
| 2026-03-26 14:29 | Game log captured (timestamp in filename: 20260326_142911) |
| 2026-03-26 21:01 | New AI work session started to investigate |
| 2026-03-26 21:02 | Root cause identified and fix committed |

---

## Game Log Analysis

File: `game_log_20260326_142911.txt`

- **Platform:** Windows, Godot 4.3-stable (official), release build
- **Scene navigated to:** `WinterForestLevel` (at 14:29:26)
- **SnowEffect log entries:** **None** — the `[SnowEffect]` logger never fired
- **Errors found:** Only one unrelated error: `Invalid resource (falling back to sync): res://scenes/levels/csharp/TestTier.tscn`
- **Snow-related errors:** **None logged** — the scene loaded silently broken

The absence of any `[SnowEffect]` log entries is significant: `snow_effect.gd` logs
`"Snow started (continuous mode, world-space emitters)"` in `_ready()`. The fact that this
message never appeared in the log means the `SnowEffect` node either was not instantiated,
or failed to load its scene resource at all.

---

## Root Cause Analysis

### Root Cause 1: Forward Reference in `.tscn` File (PRIMARY)

In Godot's `.tscn` (text scene) format, **sub-resources must be declared before they are
referenced**. The scene parser reads top-to-bottom; a reference to a sub-resource that has
not yet been declared results in a `null` property — or in strict cases, a scene parse failure.

**Before the fix** (`scenes/effects/SnowEffect.tscn`):

```
[sub_resource type="ParticleProcessMaterial" id="ParticleProcessMaterial_large"]
...
color_ramp = SubResource("GradientTexture1D_fade_out")   ← references line 68 from line 34!

[sub_resource type="ParticleProcessMaterial" id="ParticleProcessMaterial_small"]
...
color_ramp = SubResource("GradientTexture1D_fade_out")   ← references line 68 from line 62!

[sub_resource type="Gradient" id="Gradient_fade_out"]   ← DEFINED AFTER USE
...
[sub_resource type="GradientTexture1D" id="GradientTexture1D_fade_out"]   ← DEFINED AFTER USE
```

When Godot's scene loader encountered `color_ramp = SubResource("GradientTexture1D_fade_out")`
but `GradientTexture1D_fade_out` had not yet been parsed, the `color_ramp` was assigned `null`.
This likely caused the `ParticleProcessMaterial` resources to fail validation, resulting in the
entire `SnowEffect.tscn` scene being unloadable — hence zero particles and no log output.

### Root Cause 2: Incorrect `load_steps` (SECONDARY)

The `load_steps` header was `9` but the actual count of resources was:
- 1 ext_resource (script)
- 9 sub_resources
- 1 scene node

`load_steps` should equal `ext_resources + sub_resources + 1 = 11`.

When PR #1572 added `Gradient_fade_out` and `GradientTexture1D_fade_out` (2 new sub-resources),
`load_steps` was not updated from the original `9`. An incorrect `load_steps` count can cause
Godot to abort scene loading prematurely or emit parsing warnings.

---

## Fix Applied

**File:** `scenes/effects/SnowEffect.tscn`

1. Moved `Gradient_fade_out` and `GradientTexture1D_fade_out` sub-resource declarations to
   **before** `ParticleProcessMaterial_large` and `ParticleProcessMaterial_small`.
2. Updated `load_steps` from `9` to `11`.

**Corrected resource order:**
```
[sub_resource type="Gradient" id="Gradient_fade_out"]          ← now at line 30
[sub_resource type="GradientTexture1D" id="GradientTexture1D_fade_out"]  ← now at line 34
[sub_resource type="ParticleProcessMaterial" id="ParticleProcessMaterial_large"]  ← line 37
...
color_ramp = SubResource("GradientTexture1D_fade_out")         ← line 52 (valid forward ref now)
```

---

## Lessons Learned

1. **Godot `.tscn` sub-resources must be declared before use.** When manually editing `.tscn`
   files (not using the Godot editor GUI), always ensure referenced sub-resources appear earlier
   in the file than their references.

2. **Update `load_steps` when adding/removing resources.** The formula is:
   `load_steps = (number of [ext_resource] entries) + (number of [sub_resource] entries) + 1`

3. **Silent failures are dangerous.** A broken particle scene loads without errors logged to
   the game log, making diagnosis harder. The absence of expected log lines (like
   `[SnowEffect] Snow started`) is itself a diagnostic signal.

4. **Automated "ready to merge" checks are insufficient for visual effects.** The CI/automated
   checks passed, but the visual effect was completely broken at runtime. Visual/behavioral
   testing by a human tester is needed for particle effects.

---

## Attached Artifacts

- `game_log_20260326_142911.txt` — Game log from the owner's test session showing the broken state
