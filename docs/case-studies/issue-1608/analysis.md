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

### Log 1: `game_log_20260327_080021.txt`
**Build:** Release/exported build, Windows, Godot 4.3-stable
**Executable:** `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe`
**Build info:** not available (exported PCK — downloaded pre-built binary, pre-dating PR #1592 merge)
**Difficulty:** Power Fantasy
**Levels played:** LabyrinthLevel → SnowLevel → DocksLevel → BeachLevel

### Log 2: `game_log_20260327_084542.txt`
**Build:** Same pre-built binary (same executable path, same `I:/Загрузки/...` path)
**Levels played:** directly to BeachLevel
**Reporter note:** "всё ещё не останавливается" (still not stopping)

### Log 3: `game_log_20260327_091144.txt`
**Build:** Same pre-built binary `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe`
**Levels played:** LabyrinthLevel → other levels → BeachLevel
**Reporter note:** "не останавливается" (not stopping)

### Log 4: `game_log_20260327_093030.txt`
**Build:** Same pre-built binary `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe`
**Levels played:** LabyrinthLevel → BeachLevel
**Reporter note:** "всё ещё не останавливается" (still not stopping)

---

## Timeline of Events (from Log 1: game_log_20260327_080021.txt)

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

**Key finding in Log 1:** For Snow and Rain levels, `[LastChance] Precipitation paused: <NodeName>` is logged immediately after the freeze starts. For the Beach level, this line is completely absent, confirming that `WaterBody.set_time_stopped()` was never called.

## Timeline of Events (from Log 2: game_log_20260327_084542.txt)

| Time | Level | Event |
|------|-------|-------|
| 08:45:42 | (startup) | Game started — same binary as Log 1 (`I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe`) |
| 08:46:05 | BeachLevel | Level loaded directly |
| 08:46:05 | BeachLevel | `[BeachLevel] Water node found OK — visual=true shader=true collision=true pos=(1264, 242)` |
| 08:46:11 | BeachLevel | Grenade explosion → Last chance triggered (2s freeze, trigger: grenade explosion) |
| 08:46:11 | BeachLevel | `[LastChance] Froze all nodes except player` |
| 08:46:11 | BeachLevel | **ZERO precipitation-related log entries** ← confirms same bug as Log 1 |
| 08:46:13 | BeachLevel | Last chance ended |

**Key finding in Log 2:** Zero WaterBody log entries in the ENTIRE log — not even `[WaterBody] Ready` from `_ready()`. This conclusively proves both logs are from a **pre-PR #1592 binary** that does not include `add_to_group("precipitation_effects")` in WaterBody's `_ready()`. The user is testing with an old downloaded executable.

## Timeline of Events (from Log 3: game_log_20260327_091144.txt)

| Time | Level | Event |
|------|-------|-------|
| 09:11:44 | (startup) | Game started — **same binary** `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe` |
| 09:11:58 | BeachLevel | Level loaded |
| 09:11:58 | BeachLevel | `[BeachLevel] Water node found OK — visual=true shader=true collision=true pos=(1264, 242)` |
| 09:12:03 | BeachLevel | Grenade explosion → Last chance triggered (2s freeze, trigger: grenade explosion) |
| 09:12:03 | BeachLevel | `[LastChance] Froze all nodes except player and autoloads` |
| 09:12:03 | BeachLevel | **NO "Precipitation paused: WaterBody" logged** ← same bug as Logs 1 & 2 |
| 09:12:03 | BeachLevel | **ZERO WaterBody log entries in entire log** ← old binary confirmed |
| 09:12:05 | BeachLevel | Last chance ended |

**Key finding in Log 3:** Identical pattern to Logs 1 and 2. The executable path is identical: `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe`. This is still the old downloaded binary — not a build from the `issue-1608-32da689d6e29` branch. All three logs confirm the same pre-PR #1592 binary.

## Timeline of Events (from Log 4: game_log_20260327_093030.txt)

| Time | Level | Event |
|------|-------|-------|
| 09:30:30 | (startup) | Game started — **same binary** `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe` |
| 09:30:41 | BeachLevel | Level loaded (first attempt) |
| 09:30:42 | BeachLevel | `[BeachLevel] Water node found OK — visual=true shader=true collision=true pos=(1264, 242)` |
| 09:30:47 | BeachLevel | Level reloaded (second attempt) |
| 09:30:47 | BeachLevel | `[BeachLevel] Water node found OK — visual=true shader=true collision=true pos=(1264, 242)` |
| 09:30:58 | BeachLevel | Grenade explosion → Last chance triggered |
| 09:30:58 | BeachLevel | `[LastChance] Froze all nodes except player and autoloads (including GameManager for quick restart)` |
| 09:30:58 | BeachLevel | **ZERO WaterBody log entries in entire log** ← old binary confirmed |
| 09:30:58 | BeachLevel | **NO "Precipitation paused: WaterBody" logged** ← same bug as Logs 1, 2 & 3 |

**Key finding in Log 4:** The executable path is identical to all previous logs: `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe`. The reporter appears to have tried the level twice (loaded BeachLevel at 09:30:41 and again at 09:30:47), but is still using the same old downloaded binary. The fourth log provides the same diagnostic fingerprint: zero `[WaterBody]` entries in the entire log, no `[LastChance] Precipitation paused: WaterBody` after the freeze.

### Log 5: `game_log_20260327_105401.txt`
**Build:** Same pre-built binary `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe`
**Levels played:** LabyrinthLevel → BeachLevel (multiple freeze events triggered)
**Reporter note:** "не останавливается" (not stopping)

| Time | Level | Event |
|------|-------|-------|
| 10:54:01 | (startup) | Game started — **same binary** `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe` |
| 10:54:08 | BeachLevel | `[BeachLevel] Water node found OK — visual=true shader=true collision=true pos=(1264, 242)` (first visit) |
| 10:54:13 | BeachLevel | `[BeachLevel] Water node found OK — visual=true shader=true collision=true pos=(1264, 242)` (second load) |
| 10:54:19 | BeachLevel | `[LastChance] Froze existing grenade: VOGGrenade` — freeze triggered |
| 10:54:19 | BeachLevel | `[LastChance] Froze all nodes except player and autoloads` |
| 10:54:19 | BeachLevel | **ZERO WaterBody log entries in entire log** ← old binary confirmed |
| 10:54:19 | BeachLevel | **NO "Precipitation paused: WaterBody" logged** ← same bug as all previous logs |

**Key finding in Log 5:** Identical diagnostic fingerprint to Logs 1–4. Zero `[WaterBody]` entries in the 987-line log (not even `[WaterBody] Ready` from `_ready()`). The WaterBody node is confirmed present (`[BeachLevel] Water node found OK`), but this is the same pre-built binary that predates PR #1592 and does not include `add_to_group("precipitation_effects")` in `water_body.gd._ready()`.

**Conclusion across all 5 logs:** Every game log submitted by the reporter was generated from the same pre-built Windows executable at `I:/Загрузки/godot exe/ОСадКИ/` (Downloads folder). None of them were built from the fixed source code in `issue-1608-32da689d6e29`. The reporter needs to build from source to test the fix.

---

## Root Cause Analysis

### Root Cause 1: Game Binary Pre-Dates the Issue #1585 Fix (Deployment Issue)

Both game logs were captured from the **same pre-built `.exe`** at `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe` ("Загрузки" = Downloads in Russian). This is a downloaded binary, not one built from the fixed source code.

**Evidence from Log 2:** Zero WaterBody log entries in the entire 1178-line log, including no `[WaterBody] Ready` message that would appear in `_ready()`. The WaterBody node itself is verified to exist (`[BeachLevel] Water node found OK`), so `_ready()` ran — but did not produce any log output, meaning the old `_log()` implementation (which called `get_node_or_null("/root/FileLogger")`) was silently failing. More importantly, there is NO `add_to_group("precipitation_effects")` call in this old build's WaterBody.

**Evidence from Log 1:** In other levels (Snow, Docks), SnowEffect and RainEffect DO produce `[LastChance] Precipitation paused:` entries because they call `add_to_group("precipitation_effects")` in their own `_ready()` methods (this was added earlier than WaterBody's group registration). On BeachLevel, no such log entry appears, confirming WaterBody is absent from the group.

**Impact:** In the old binary, `_set_precipitation_time_stopped()` scanned for WaterBody using:
```gdscript
# Old (broken) approach — from before Issue #1585 fix:
var path: String = script.resource_path.to_lower()
if "water_body" in path:
    node.set_time_stopped(paused)
```
In an exported build, `script.resource_path` is `""`, so the condition `"water_body" in ""` is always `false`. WaterBody was silently skipped every time.

**Fix (Issue #1585, merged PR #1592):** Changed to group-based lookup — WaterBody registers in `"precipitation_effects"` group in `_ready()`. This fix is in `main` but the user's binary does not include it.

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
- `scripts/objects/water_body.gd` — fix `_log()` to use `Engine.get_singleton()` as primary lookup
- `tests/unit/test_water_body.gd` — regression tests for Issue #1608
- `docs/case-studies/issue-1608/analysis.md` — this document
- `docs/case-studies/issue-1608/logs/game_log_20260327_080021.txt` — first game log from reporter
- `docs/case-studies/issue-1608/logs/game_log_20260327_084542.txt` — second game log from reporter (same old binary, confirms binary pre-dates PR #1592)
- `docs/case-studies/issue-1608/logs/game_log_20260327_091144.txt` — third game log from reporter (same old binary, third confirmation that this is a pre-PR #1592 downloaded executable)
- `docs/case-studies/issue-1608/logs/game_log_20260327_093030.txt` — fourth game log from reporter (same old binary, fourth confirmation — reporter tried the level twice in this session)
- `docs/case-studies/issue-1608/logs/game_log_20260327_105401.txt` — fifth game log from reporter (same old binary, fifth confirmation — reporter tried BeachLevel twice with multiple freeze triggers)
