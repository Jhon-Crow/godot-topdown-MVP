# Case Study: Issue #1608 — Beach Water Animation Not Stopping During Last Chance Time Freeze

## Issue Summary

**Reporter:** Jhon-Crow
**Title:** fix воду (fix water)
**Description:** На карте Пляж при остановке времени (при особом последнем шансе) не останавливается анимация воды.
(On the Beach map during time stop [last chance effect], the water animation does not stop.)

**Related issues:**
- Issue #1585 — Prior fix: rain/snow disappear and water waves not stopping on time freeze
- Issue #1550 — Added surf-foam animation to the water shader
- Issue #1445 — Original realistic water shader for the Beach level

---

## Evidence

**Game log:** `game_log_20260327_080021.txt`
**Build:** Release/exported build, Windows, Godot 4.3-stable
**Executable:** `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe`
**Build info:** not available (exported PCK, pre-dating Issue #1585 fix merge)
**Difficulty:** Power Fantasy

---

## Timeline of Events (from game log)

| Time | Level | Event |
|------|-------|-------|
| 08:00:21 | LabyrinthLevel | Game started, all autoloads initialized |
| 08:00:32 | SnowLevel | Level loaded |
| 08:00:34 | SnowLevel | Grenade explosion → Last chance triggered (2s freeze) |
| 08:00:34 | SnowLevel | `[SnowEffect] Snow paused (time stopped)` |
| 08:00:34 | SnowLevel | `[LastChance] Precipitation paused: SnowEffect` ✓ |
| 08:00:36 | SnowLevel | Last chance ended — snow resumed |
| 08:00:40 | DocksLevel | Level loaded |
| 08:00:40 | DocksLevel | Grenade explosion → Last chance triggered (2s freeze) |
| 08:00:40 | DocksLevel | `[RainEffect] Rain paused (time stopped)` |
| 08:00:40 | DocksLevel | `[LastChance] Precipitation paused: RainEffect` ✓ |
| 08:00:42 | DocksLevel | Last chance ended — rain resumed |
| 08:00:45 | BeachLevel | Level loaded |
| 08:00:45 | BeachLevel | `[BeachLevel] Water node found OK — visual=true shader=true` |
| 08:00:50 | BeachLevel | Grenade explosion → Last chance triggered (2s freeze) |
| 08:00:50 | BeachLevel | `[LastChance] Froze all nodes except player` |
| 08:00:50 | BeachLevel | **NO "Precipitation paused: WaterBody" logged** ← Bug evidence |
| 08:00:50 | BeachLevel | **NO "[WaterBody] Wave animation paused" logged** ← Bug evidence |
| 08:00:52 | BeachLevel | Last chance ended |

**Key finding:** For Snow and Rain levels, `[LastChance] Precipitation paused: <NodeName>` is logged immediately after the freeze starts. For the Beach level, this line is completely absent, confirming that `WaterBody.set_time_stopped()` was never called.

---

## Root Cause Analysis

### Root Cause 1: Game Binary Pre-Dates the Issue #1585 Fix (Deployment Issue)

The game log was captured from a pre-built `.exe` exported **before** Issue #1585's fix was merged to `main` at `2026-03-27 07:45:03 +0300`. The log timestamp (`08:00:21` local = `05:00:21 UTC`) is only ~15 minutes after the merge — far too short to rebuild and re-export a Windows binary.

**Evidence:** No `[WaterBody]` log entries appear anywhere in the log (not even from `_ready()`). The `water_body.gd` file included `add_to_group("precipitation_effects")` only after the Issue #1585 fix. In the old binary, WaterBody was found via `find_children + script.resource_path` check, which silently failed in exported builds because `script.resource_path` returns `""` in PCK exports.

**Impact:** In the old build, `_set_precipitation_time_stopped()` scanned for WaterBody using:
```gdscript
# Old (broken) approach — from before Issue #1585 fix:
var path: String = script.resource_path.to_lower()
if "water_body" in path:
    node.set_time_stopped(paused)
```
In an exported build, `script.resource_path` is `""`, so the condition `"water_body" in ""` is always `false`. WaterBody was silently skipped every time.

**Fix (Issue #1585):** Changed to group-based lookup — WaterBody registers in `"precipitation_effects"` group in `_ready()`. Merged in PR #1592.

---

### Root Cause 2: Hardcoded `TIME * 0.15` in Surf-Phase X-Variation (Shader Bug)

Even after the Issue #1585 fix correctly calls `WaterBody.set_time_stopped(true)` (zeroing `wave_speed`, `ripple_speed`, `surf_speed`), the surf-foam animation continued to move on the Beach level.

**Root cause:** `realistic_water.gdshader` (added in Issue #1550) contained a hardcoded `TIME * 0.15` in the surf-foam phase x-variation term:

```glsl
// BEFORE FIX (broken):
float surf_phase = uv.y * surf_frequency - TIME * surf_speed;
surf_phase += sin(uv.x * 2.0 + TIME * 0.15) * 0.15;  // ← hardcoded! bypasses surf_speed
```

The `set_time_stopped(true)` call correctly zeroed `surf_speed` via `set_shader_parameter("surf_speed", 0.0)`, which froze the main surf-band scroll (`uv.y * surf_frequency - TIME * 0.0 = constant`). However, the x-variation term used the literal constant `0.15` instead of referencing `surf_speed`. This meant:
- `uv.y * surf_frequency - TIME * 0.0` → surf bands stop scrolling vertically ✓
- `sin(uv.x * 2.0 + TIME * 0.15)` → surf bands continue to shift horizontally ✗

**Visible result:** The surf-foam streaks stop advancing toward the shoreline but continue to "shimmer" and shift side-to-side, making the water appear to still be animated.

**Code path:** `last_chance_effects_manager.gd` → `_set_precipitation_time_stopped(true)` → `water_body.gd:set_time_stopped(true)` → `mat.set_shader_parameter("surf_speed", 0.0)` → **INSUFFICIENT** because shader uses `TIME * 0.15` independently.

**Fix (Issue #1608 / PR #1609):** Changed the hardcoded constant to reference `surf_speed`:
```glsl
// AFTER FIX (correct):
surf_phase += sin(uv.x * 2.0 + TIME * surf_speed * 0.5) * 0.15;
```
When `surf_speed = 0.0`, `TIME * 0.0 * 0.5 = 0.0`, freezing the x-variation completely.

---

### Root Cause 3: WaterBody (Area2D) Gets Frozen Before `set_time_stopped` Is Called (Secondary Issue)

`_freeze_node_except_player` in `last_chance_effects_manager.gd` explicitly handles `Area2D` nodes:

```gdscript
if node is Area2D:
    _original_process_modes[node] = node.process_mode
    node.process_mode = Node.PROCESS_MODE_DISABLED
```

Since `WaterBody extends Area2D`, the WaterBody node is set to `PROCESS_MODE_DISABLED` during the freeze. Then `_set_precipitation_time_stopped(true)` is called *after* this freeze. While GDScript method calls work on disabled nodes (GDScript does not gate method calls on process mode), and shader parameter updates via `ShaderMaterial.set_shader_parameter()` also work regardless of process mode, this ordering creates a subtle inconsistency: the WaterBody is disabled for physics/splash detection but its shader parameters are then explicitly modified.

**Impact:** This is NOT the root cause of the visual bug (shader parameter updates still work), but it means WaterBody's `_process()` — which updates obstacle shader params every frame — is correctly paused. When time resumes, `PROCESS_MODE_INHERIT` is restored, and `_process()` resumes.

**Status:** This is acceptable behavior, not a bug. No fix needed.

---

## Complete Call Chain

```
LastChanceEffectsManager._freeze_time()
  └─► _freeze_node_except_player(scene_root)
        └─► WaterBody (Area2D) → process_mode = DISABLED
  └─► _set_precipitation_time_stopped(true)
        └─► get_tree().get_nodes_in_group("precipitation_effects")
              └─► [In new build] WaterBody.set_time_stopped(true)
                    └─► ShaderMaterial.set_shader_parameter("wave_speed", 0.0)
                    └─► ShaderMaterial.set_shader_parameter("ripple_speed", 0.0)
                    └─► ShaderMaterial.set_shader_parameter("surf_speed", 0.0)
                          └─► [In old shader] surf_phase x-variation STILL uses TIME*0.15 ← Bug
                          └─► [In fixed shader] x-variation = TIME*surf_speed*0.5 = 0 ✓
```

---

## Shader TIME Usage Audit

All uses of `TIME` in `realistic_water.gdshader` after the Issue #1608 fix:

| Line | Expression | Controlled by | Zeroed on freeze? |
|------|------------|---------------|-------------------|
| Primary wave | `TIME * wave_speed` | `wave_speed` | ✓ Yes |
| Primary wave 2 | `TIME * wave_speed * 0.6` | `wave_speed` | ✓ Yes |
| Ripple wave | `TIME * ripple_speed` | `ripple_speed` | ✓ Yes |
| Ripple wave 2 | `TIME * ripple_speed * 0.5` | `ripple_speed` | ✓ Yes |
| Surf scroll | `TIME * surf_speed` | `surf_speed` | ✓ Yes |
| Surf x-var (old) | `TIME * 0.15` | **NOTHING** | ✗ No (BUG) |
| Surf x-var (new) | `TIME * surf_speed * 0.5` | `surf_speed` | ✓ Yes |

---

## Fix Summary

**PR #1609** (branch `issue-1608-32da689d6e29`) fixes Root Cause 2:

**File:** `scripts/shaders/realistic_water.gdshader`
```diff
-surf_phase += sin(uv.x * 2.0 + TIME * 0.15) * 0.15;
+surf_phase += sin(uv.x * 2.0 + TIME * surf_speed * 0.5) * 0.15;
```

Root Cause 1 was already fixed in PR #1592 (merged to `main`).

---

## Proposed Solutions

### Solution A (Implemented): Fix Shader TIME Reference

Change `TIME * 0.15` to `TIME * surf_speed * 0.5` so all surf-foam motion responds to `surf_speed = 0`.

**Pros:** Minimal change. Exactly targets the hardcoded constant. Factor `0.5` preserves natural variation magnitude.
**Cons:** None.

### Solution B: Alternative — Introduce Separate `time_stopped` Uniform

Add a `uniform bool time_stopped = false` to the shader. When `true`, replace all `TIME * speed` with `0.0` directly in the shader.

**Pros:** More explicit freeze in shader code. Could handle any future missed constants.
**Cons:** Requires additional shader parameter and more complex GLSL branching.

**Decision:** Solution A was chosen — it's simpler and sufficient. The shader had exactly one hardcoded constant, and fixing it directly is the minimal correct fix.

---

## Prevention / Lessons Learned

1. **Any `TIME * constant` in a "pauseable" shader is a bug.** All `TIME` multipliers must reference a speed uniform so they can be zeroed via `set_shader_parameter()` during game-world freezes.

2. **Test shader time-stop in exported builds, not just in the Godot editor.** The Godot editor's shader preview and in-editor play mode may behave differently from exported PCK builds.

3. **When adding new animation terms to an existing pauseable shader, always check whether the new term references the correct speed uniform** — not a hardcoded literal.

4. **Log `set_time_stopped` calls from within the affected node** (WaterBody, RainEffect, SnowEffect) to make the audit trail visible in game logs. Note: WaterBody's `_log()` currently does not produce entries in the game log because `get_node_or_null("/root/FileLogger")` may fail in some contexts. Consider adding the `[WaterBody]` prefix directly like SnowEffect/RainEffect do.

---

## Files Changed

- `scripts/shaders/realistic_water.gdshader` — replace `TIME * 0.15` with `TIME * surf_speed * 0.5`
- `tests/unit/test_water_body.gd` — regression tests for Issue #1608
- `docs/case-studies/issue-1608/analysis.md` — this document
- `docs/case-studies/issue-1608/game_log_20260327_080021.txt` — game log from reporter
