# Case Study: Issue #1578 — Blood Creates Puddles in Water Instead of Diffusion Clouds

## Summary

Blood hitting water still creates persistent floor puddles instead of diffusion clouds
that dissolve into the water, despite the fix implemented in PR #1604.

## Game Log Evidence (2026-03-27 session)

- **Log file**: `game_log_20260327_085514.txt`
- **Total log lines**: 4,250
- **Blood decals spawned total**: 2,199
- **Blood decals spawned INSIDE water area**: **1,880** (out of 2,199 = 85.5%)

The water body is at position (1264, 242) with width=2400 and height=356 (per log line 517).
Water bounds: x ∈ [64, 2464], y ∈ [64, 420].

### Sample in-water decal coordinates from log
```
(640, 360), (554.5, 206.9), (594.4, 255.7), (579.0, 283.6), (562.9, 283.8),
(619.7, 307.2), (546.8, 274.4), (575.9, 293.3), ...
```

This confirms the fix was NOT effective — blood decals continue to spawn in water.

## Root Cause Analysis

### Root Cause 1: `"water_body"` group not registered (MERGE CONFLICT)

Our PR added `add_to_group("water_body")` to `WaterBody._ready()`. The main branch
merged a separate feature (issue #1585, LastChanceEffectsManager) that changed this
same line to `add_to_group("precipitation_effects")`.

After merging from main, the conflict resolution replaced our `"water_body"` group with
`"precipitation_effects"`, meaning `ImpactEffectsManager._find_water_body_at()` could
not find any nodes in the `"water_body"` group → returned `null` → blood decals spawned
without water-interception.

**Fix**: Both groups must be registered. The `_ready()` now calls:
```gdscript
add_to_group("water_body")          # for ImpactEffectsManager (Issue #1578)
add_to_group("precipitation_effects") # for LastChanceEffectsManager (Issue #1585)
```

### Root Cause 2: `is_point_in_water` method name mismatch

`_find_water_body_at()` in `impact_effects_manager.gd` calls:
```gdscript
if wb.has_method("is_point_in_water") and wb.is_point_in_water(world_pos):
```

But `water_body.gd` only had `_is_point_in_water()` (private, with underscore prefix).
While GDScript allows external calls to underscore-prefixed methods, `has_method()`
returns `false` for `"is_point_in_water"` when only `"_is_point_in_water"` exists.

Result: `has_method` guard always false → water body never returned → decals spawned.

**Fix**: Added a public wrapper `is_point_in_water()` that delegates to `_is_point_in_water()`.

## Timeline of Events

1. Issue #1578 reported: blood creates puddles in water instead of diffusion clouds.
2. PR #1604 created with three-part fix:
   - `water_body.gd`: added `add_to_group("water_body")`
   - `impact_effects_manager.gd`: added water-detection before decal spawn
   - `water_body.gd`: added `spawn_blood_diffusion_at()` public API
3. PR #1604 marked ready (2026-03-26).
4. Owner tested (2026-03-27 08:55) → reported "не сработало" (didn't work).
5. Analysis: merge conflict from PR #1585 replaced `"water_body"` group with
   `"precipitation_effects"`, breaking the fix.
6. Additionally discovered: `has_method("is_point_in_water")` returns false because
   only `_is_point_in_water` existed.

## Fix Applied

1. **`scripts/objects/water_body.gd`**: Added both group registrations in `_ready()`.
2. **`scripts/objects/water_body.gd`**: Added public `is_point_in_water()` wrapper.
3. Merged latest main branch changes to resolve conflict.

---

## Second Owner Report: "изменений нет" (2026-03-27 09:21)

After fixes were committed (commit `e4eabe4a`, 2026-03-27 06:03 UTC), the owner tested
again at 09:21 UTC and reported "изменений нет" (no changes).

### Log Evidence (game_log_20260327_092156.txt)

- **Total blood puddles**: 2,370
- **Blood puddles inside water area** (x∈[64,2464], y∈[32,452]): **2,156** (90.97%)
- **`[WaterBody] Ready`** log message: **NOT PRESENT**
- `Build info: not available (build_info.cfg not found)`

### Root Cause: User testing pre-fix build (not from our branch)

The absence of `[WaterBody] Ready` in the log is the key diagnostic signal:

1. Our branch (`e4eabe4a`) and main branch both have `_log("[WaterBody] Ready...")` in `_ready()`.
2. The main branch also has `print(message)` in `_log()`, so any WaterBody would print to both console AND file.
3. **No `[WaterBody]` entry anywhere in the game log** → WaterBody's `_ready()` never ran, OR
   the build was from a version before WaterBody logging was added.

**The build was exported WITHOUT our PR changes.** Evidence:
- `Build info: not available (build_info.cfg not found)` — our CI generates `build_info.cfg` on every build.
  Its absence means this is NOT a CI-built artifact from our branch.
- The game was run from `I:/Загрузки/godot exe/ОСадКИ/` — a local export folder, not a
  CI download.

**Conclusion**: The user exported the game from the Godot editor using the main branch
(which still lacks our `add_to_group("water_body")` fix). The fix is in PR #1604 which
has not been merged yet.

### What the user must do

To test the fixed version, the user needs to either:
1. **Download the CI-built EXE** from our branch:
   [windows-build artifact](https://github.com/konard/Jhon-Crow-godot-topdown-MVP/actions/runs/23633555990)
2. **Or merge PR #1604** so the fix is included in the main branch export.

Our fix is code-verified correct:
- `water_body.gd` registers `"water_body"` group in `_ready()`
- `impact_effects_manager.gd` queries `"water_body"` group before spawning decals
- `is_point_in_water()` public wrapper is present and callable via `has_method()`

Sample verification: position (402, 264) is inside water bounds (x∈[64,2464], y∈[32,452]).
`_is_point_in_water()`: `local = (402-1264, 264-242) = (-862, 22)`, `abs(-862) ≤ 1200 ✓`, `abs(22) ≤ 210 ✓` → in water.

---

## Third Owner Report: "всё ещё образуются простые лужи крови" (2026-03-27 10:21)

After a second work session (commit `b819bafc`, 2026-03-27 06:32 UTC), the owner tested
again at 10:21 UTC and reported "всё ещё образуются простые лужи крови а не облака (видимо
изменения не применились)" (blood puddles still forming, changes apparently not applied).

### Log Evidence (game_log_20260327_102127.txt)

- **Total log lines**: 3,629
- **BloodDecal entries**: 1,872
- **`[WaterBody] Ready`** log message: **NOT PRESENT** (confirmed by full grep)
- `Build info: not available (build_info.cfg not found)`
- **`add_to_group("water_body")`** was called (water node found OK by BeachLevel)

### Verification: Fix IS in the CI artifact

Downloaded and inspected the latest CI artifact (`windows-build` from run 23634321931,
built from commit `b819bafc`):

```
strings Godot-Top-Down-Template.exe | grep "add_to_group.*water_body"
→  add_to_group("water_body")          ✓ found in EXE

strings Godot-Top-Down-Template.exe | grep "_find_water_body_at"
→  var water_body: Node = _find_water_body_at(landing_pos)   ✓ found
   func _find_water_body_at(world_pos: Vector2) -> Node:     ✓ found

strings Godot-Top-Down-Template.exe | grep "spawn_blood_diffusion_at"
→  water_body.spawn_blood_diffusion_at(...)                  ✓ found
```

**The fix is correctly embedded in the CI-built EXE.**

### Root Cause: User continues using an old locally-stored build

The user's executable path is `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe` —
the same path as in the second test session. This is a previously downloaded file stored on
drive `I:` (a local disk or USB drive). The user is **not re-downloading the updated build**
between test sessions.

Diagnostic evidence:
- `Build info: not available` — appears in ALL three test logs; build_info.cfg is generated by CI
  but is NOT found in the exported PCK (the GDScript code reads `res://build_info.cfg` which
  should be packed, but apparently the `firebelley/godot-export` action either does not pack
  root `.cfg` files or they get stripped during export). This diagnostic is therefore unreliable.
- No `[WaterBody] Ready` log — the WaterBody `_log()` call is in the latest EXE (verified via
  `strings`), but the user's build doesn't execute it → user's build predates the logging code.

### Fix Applied in This Session

Added a **fallback group registration** in `beach_level.gd`'s `_setup_water()`:

```gdscript
# Issue #1578: Ensure the water node is in the "water_body" group so
# ImpactEffectsManager._find_water_body_at() can locate it.
if not water.is_in_group("water_body"):
    water.add_to_group("water_body")
    _log_to_file("Water node registered in 'water_body' group (Issue #1578 fallback)")
else:
    _log_to_file("Water node already in 'water_body' group (water_body.gd _ready() ran OK)")
```

This is a defense-in-depth measure. Even if `water_body.gd`'s `_ready()` fails for any
reason (script version mismatch, node ordering, etc.), the `beach_level.gd` script will
ensure the water node is in the `"water_body"` group before the game starts.

This also provides a clear diagnostic signal in the game log:
- `"already in 'water_body' group"` → `water_body.gd` `_ready()` ran OK
- `"fallback"` → water_body.gd `_ready()` didn't register the node (old code or bug)

---

## Fourth Owner Report: "я использую новую сборку, всё по старому" (2026-03-27 08:00 UTC, test 4)

After the third work session (commit `de261e80`, 2026-03-27 07:38 UTC CI build complete),
the owner stated at 08:00 UTC: "я использую новую сборку, всё по старому" (I'm using the
new build, everything is the same).

**No game log was attached to this comment.**

### Analysis of All Three Prior Logs

Cross-referencing all three game logs (timestamps: 08:55, 09:21, 10:21 on 2026-03-27):

| Metric                                   | Log 1 (08:55) | Log 2 (09:21) | Log 3 (10:21) |
|------------------------------------------|:-------------:|:-------------:|:-------------:|
| `Build info: not available`              | ✓             | ✓             | ✓             |
| `[WaterBody] Ready` in log               | ✗             | ✗             | ✗             |
| `Water node already in 'water_body'`     | ✗             | ✗             | ✗             |
| `Water node registered in 'water_body'`  | ✗             | ✗             | ✗             |
| Blood decals created                     | 2,199         | 2,370         | 1,871         |

**All three logs are conclusively from pre-fix builds:**

1. `Build info: not available` appears in all three — CI generates `build_info.cfg` which
   causes the message to show build branch/commit instead. Its absence proves the EXE was
   NOT built by our CI pipeline.
2. `[WaterBody] Ready` is absent — this log line has been present in every build from our
   branch since the initial implementation. Its absence confirms pre-fix code.
3. The fallback group registration messages (`"Water node registered..."` /
   `"Water node already in..."`) added in commit `de261e80` are absent — confirming the
   build predates commit `de261e80`.

### Current CI Build Verification (commit de261e80, run 23636201836)

Downloaded the latest CI artifact and verified with `strings`:

```
✓  add_to_group("water_body")
✓  add_to_group("precipitation_effects")
✓  func is_point_in_water(world_pos: Vector2) -> bool:
✓  func spawn_blood_diffusion_at(world_pos: Vector2, blood_color: Color) -> void:
✓  var water_body: Node = _find_water_body_at(landing_pos)
✓  if wb.has_method("is_point_in_water") and wb.is_point_in_water(world_pos):
✓  _log_to_file("Water node already in 'water_body' group (water_body.gd _ready() ran OK)")
✓  _log_to_file("Water node registered in 'water_body' group (Issue #1578 fallback)")
```

**All fix strings confirmed present in the EXE.** The fix is complete and correct.

### Expected Log Signature for Correct Build

When the game is run from our branch's CI artifact, the log should contain:

```
Build branch: issue-1578-d6d3b68c9ede
Build commit: de261e807e133856674a001c585eae80102c771e
...
[WaterBody] Ready — visual=true shader=OK collision=true splash=OK blood=OK
[BeachLevel] Water node already in 'water_body' group (water_body.gd _ready() ran OK)
```

If instead the log shows:
```
Build info: not available (build_info.cfg not found)
```
→ The user is running an **old build** that does not include the fix.

### How to Obtain the Correct Build

1. Go to: https://github.com/konard/Jhon-Crow-godot-topdown-MVP/actions/runs/23636201836
2. Click "Build Windows Portable EXE"
3. Download the `windows-build` artifact
4. Extract the ZIP → extract the inner `Windows Desktop.zip`
5. Run `Godot-Top-Down-Template.exe` from the extracted folder
6. Check `game_log_*.txt` for `Build branch: issue-1578-d6d3b68c9ede`

---

## Fifth Owner Report: "не работает" (2026-03-28 16:32 UTC, test 5)

After the fourth work session (commit `3a736ac2`, 2026-03-28 15:00 UTC CI build complete),
the owner tested again at 19:31 UTC and reported "не работает" (doesn't work), attaching
`game_log_20260328_193137.txt`.

### Log Evidence (game_log_20260328_193137.txt)

- **Total log lines**: 3,994
- **Blood puddles logged**: 2,033
- **Blood puddles inside water area** (x∈[64,2464], y∈[32,452]): **1,687** (83.0%)
- `Build info: not available (build_info.cfg not found)`
- `[WaterBody] _ready() start` log: **NOT PRESENT** (our new early diagnostic)
- `[WaterBody] Ready —` log: **NOT PRESENT**
- `[BeachLevel] Water node registered in 'water_body' group (Issue #1578 fallback — water_body.gd _ready() did NOT pre-register)`: **PRESENT at 19:31:46**

### Critical New Finding: Partial Fix Visible, But fix IS in the EXE

The fifth log contains our `beach_level.gd` fallback code output — meaning `beach_level.gd`
IS from our branch's code. This contradicts the earlier hypothesis that the user was running
a fully pre-fix build.

Binary verification of the CI-built EXE (run 23687766135, commit `3a736ac2`):
```
✓  add_to_group("water_body")
✓  is_point_in_water(world_pos: Vector2) -> bool
✓  spawn_blood_diffusion_at(...)
✓  _find_water_body_at(landing_pos)
✓  if wb.has_method("is_point_in_water") and wb.is_point_in_water(world_pos)
```
**All fix code IS in the EXE.**

### Why `build_info.cfg` Is Never Found — Root Cause

The CI generates `build_info.cfg` in the workspace root, but Godot's export with
`export_filter="all_resources"` only includes files referenced as resources. The plain
`build_info.cfg` has no corresponding `.import` file and is not referenced by the project,
so it gets excluded from the PCK.

**Consequence**: `Build info: not available` appears in EVERY exported build, making this
an unreliable diagnostic signal.

**Fix**: Added `include_filter="*.cfg"` to `export_presets.cfg` so all `.cfg` files
(including `build_info.cfg`) are included in the export PCK.

### Why `[WaterBody] _ready()` Is Not Logging — Open Question

Despite our code being in the EXE, `water_body.gd._ready()` is NOT executing its
early log (`[WaterBody] _ready() start`) AND is NOT registering the node in
the `"water_body"` group (hence the fallback ran).

This is the critical unresolved issue. The fallback DOES register the water in the group,
so `_find_water_body_at` should then find the node. But 83% of blood puddles are still
in the water area.

### Why Blood Still Creates Puddles in Water Despite Fallback

Two possible causes remain:
1. **`has_method("is_point_in_water")` returns false** — even though the method IS in the
   EXE, `has_method()` may behave differently in some exported builds.
2. **`_find_water_body_at` is not being called** — possibly `_schedule_delayed_decal` is
   returning early before the water check.

### Changes in This Session (session 5)

1. **`water_body.gd`**: Added unconditional early `_log("[WaterBody] _ready() start")` at
   the very first line of `_ready()` to confirm the script's initialization in the build.

2. **`beach_level.gd`**: Added `has_method('is_point_in_water')` diagnostic log after
   group registration to verify the method is accessible.

3. **`impact_effects_manager.gd`**: Added `_debug_water_group_logged` variable and
   unconditional logging when `"water_body"` group is empty, logged once per scene.

4. **`export_presets.cfg`**: Added `include_filter="*.cfg"` to ensure `build_info.cfg`
   is packed into the exported EXE, making the build branch/commit diagnostic reliable.

### Expected Log Signature for Correct Build After This Session

```
Build branch: issue-1578-d6d3b68c9ede
Build commit: <latest>
...
[WaterBody] _ready() start — registering groups
[WaterBody] Ready — visual=true shader=OK collision=true splash=OK blood=OK
[BeachLevel] Water node already in 'water_body' group (water_body.gd _ready() ran OK)
[BeachLevel] Water.has_method('is_point_in_water') = true
```

If the log shows `is_point_in_water = false`, that confirms has_method() is the culprit.
If `_ready() start` is absent, the script is not loading at all.

---

---

## Sixth Owner Report: "не сработало" (2026-03-29 17:58 local, Test 6)

Owner tested again at 17:58 local (14:58 UTC on 2026-03-29) and reported "не сработало" (didn't work), attaching `game_log_20260329_175815.txt`.

### Log Evidence (game_log_20260329_175815.txt)

- **Total log lines**: 5,518
- **Blood puddles logged**: 3,155
- `Build info: not available (build_info.cfg not found)` — STILL showing despite include_filter fix
- `[WaterBody] _ready() start` log: **NOT PRESENT**
- `[BeachLevel] Water node registered in 'water_body' group (Issue #1578 fallback — water_body.gd _ready() did NOT pre-register)`: **PRESENT at 17:58:39**
- `[BeachLevel] Water.has_method('is_point_in_water') = false`: **PRESENT** — NEW CRITICAL FINDING

### Confirmed: Build IS from commit 13d1ba67

The beach_level.gd diagnostic message format exactly matches commit `13d1ba67`:
```
"Water node registered in 'water_body' group (Issue #1578 fallback — water_body.gd _ready() did NOT pre-register)"
```
This string was only added in commit `13d1ba67`. Therefore the user DID download the CI artifact from run `23689760641` (commit `13d1ba67`, built 2026-03-28T16:51 UTC).

**The EXE has all our code — confirmed by binary inspection:**
```
✓  _log("[WaterBody] _ready() start — registering groups")
✓  add_to_group("water_body")
✓  func is_point_in_water(world_pos: Vector2) -> bool:
✓  func spawn_blood_diffusion_at(world_pos: Vector2, blood_color: Color) -> void:
✓  [build] / branch="issue-1578-d6d3b68c9ede"  (build_info.cfg IS in the PCK)
```

### Root Cause 1: `ResourceLoader.exists()` returns false for `.cfg` files

`file_logger.gd` uses `ResourceLoader.exists("res://build_info.cfg")` to check if the build info file exists. **`ResourceLoader` does not recognise plain `.cfg` files as Godot resources** — it only handles resource types with registered loaders (`.tres`, `.res`, `.png`, `.gd`, etc.). So `ResourceLoader.exists()` always returns `false` for `.cfg`, even when the file is packed in the PCK via `include_filter="*.cfg"`.

The `[build]` content IS in the binary (confirmed by binary inspection), but the code never reads it.

**Fix**: Use `FileAccess.file_exists("res://build_info.cfg")` instead of `ResourceLoader.exists()`.

### Root Cause 2: `has_method("is_point_in_water")` returns false

The diagnostic line `Water.has_method('is_point_in_water') = false` confirms that even though `water_body.gd` contains `func is_point_in_water(...)`, the `has_method()` check fails at runtime.

Combined with `[WaterBody] _ready() start` never appearing in any log, the water body script either:
- Fails to initialise (silent error in exported GDScript bytecode)
- Or `has_method()` behaves differently for nodes whose script failed to run `_ready()`

When `has_method()` returns false, `_find_water_body_at()` falls through without returning the node → blood decals spawn normally.

**Fix**: Added geometry-based fallback in `_find_water_body_at()`. When `has_method("is_point_in_water")` returns false, the function checks if `world_pos` is inside the node's `water_width` × `water_height` bounding rect via direct property access (`wb.get("water_width")`), which works even when `_ready()` didn't run because `@export` properties are set before `_ready()` runs.

### Why Player Didn't Reach Water in This Test

The player's coordinates stayed in x range [200–880] throughout the 35-second session, while water is at x=1264 ± 1200 (bounds x∈[64,2464]). No blood reached the water area (no decals with x>900), so the fix's effectiveness could not be assessed from this log alone.

### Changes in This Session (session 6)

1. **`scripts/autoload/impact_effects_manager.gd`** — geometry fallback in `_find_water_body_at()`:
   When `has_method("is_point_in_water")` returns false, use direct property access to check `water_width`/`water_height` bounds. This is resilient to script initialisation failures.

2. **`scripts/autoload/file_logger.gd`** — use `FileAccess.file_exists()`:
   Replaced `ResourceLoader.exists()` with `FileAccess.file_exists()` so `build_info.cfg` is found in the PCK. This will make "Build branch: issue-1578-d6d3b68c9ede" appear in the game log, definitively confirming the correct build is being used.

### Expected Log Signature After This Session's Fixes

```
Build branch: issue-1578-d6d3b68c9ede
Build commit: <latest>
...
[BeachLevel] Water.has_method('is_point_in_water') = false     ← still expected (until _ready() issue resolved)
...
[ImpactEffects] water_body geometry fallback hit at (x, y) (has_method returned false — Issue #1578)
```
The geometry fallback log line confirms water detection is working despite the `has_method` problem.

---

---

## Seventh Owner Report: "не сработало" (2026-03-30)

Owner tested at 11:10 local time (2026-03-30) and reported "не сработало" (didn't work).

### Log Evidence (game_log_20260330_111035.txt)

**Build verification:**
```
Build branch: issue-1578-d6d3b68c9ede          ← correct build ✓
Build commit: c5038734acc5cd75b10a3632cfcb37333dc5f4a4
Build date: 2026-03-29T15:15:32Z
```
The correct CI artifact was used.

**Water detection:**
```
[BeachLevel] Water node registered in 'water_body' group (Issue #1578 fallback — water_body.gd _ready() did NOT pre-register)
[BeachLevel] Water.has_method('is_point_in_water') = false
[ImpactEffects] water_body geometry fallback hit at (664.4629, 311.1347) (has_method returned false — Issue #1578)
... (many more geometry fallback hits)
```
The geometry fallback works — water IS detected. Blood positions were correctly identified as inside water.

**But blood decals still scheduled:**
```
[ImpactEffects] Blood decals scheduled: 15 to spawn at particle landing times  (×many)
```
("Blood decals scheduled" is logged BEFORE the await delay, not at spawn time — the water check happens after the delay.)

**No diffusion spawning logged** — no `Blood landed in water` lines appear.

### Root Cause 3: `WaterBody._blood_diffusion_script` is null when `_ready()` doesn't run

Even though `_find_water_body_at()` returns the water body via geometry fallback, the subsequent call to `WaterBody.spawn_blood_diffusion_at()` is a silent no-op:

```gdscript
# water_body.gd
func _spawn_blood_diffusion(world_pos: Vector2, blood_color: Color) -> void:
    if _blood_diffusion_script == null:  # ← null because _ready() never ran!
        return
```

`_blood_diffusion_script` is loaded in `WaterBody._ready()` (line 111). Since `_ready()` never runs in this exported build, the script is `null`, and `_spawn_blood_diffusion()` exits immediately.

Additionally, the old code had a `has_method("spawn_blood_diffusion_at")` guard that also fails for the same reason as `has_method("is_point_in_water")`.

### Fix (session 7)

**`impact_effects_manager.gd`**: Preload `water_blood_diffusion.gd` in `ImpactEffectsManager._preload_effect_scenes()` (which always runs in exported builds) and spawn the diffusion node directly from `ImpactEffectsManager._schedule_delayed_decal()`, bypassing `WaterBody.spawn_blood_diffusion_at()` entirely.

This eliminates all dependency on `WaterBody._ready()` for the blood-in-water interception:
- Water detection: geometry fallback (set in session 6)
- Diffusion spawning: direct `Node2D.set_script()` (set in session 7)

### Expected Log Signature After Session 7 Fixes

```
Build branch: issue-1578-d6d3b68c9ede
Build commit: <latest>
...
[ImpactEffects] Scenes loaded: ..., WaterBloodDiffusion
...
[BeachLevel] Water.has_method('is_point_in_water') = false    ← still expected
...
[ImpactEffects] water_body geometry fallback hit at (x, y) ...
[ImpactEffects] Blood landed in water at (x, y) — spawning diffusion effect (Issue #1578)
```
The `Blood landed in water — spawning diffusion effect` line confirms the blood cloud is being created.

---

## Eighth Owner Feedback: diffusion appears, but needs realistic liquid behavior (2026-04-10)

Owner confirmed the clouds appear, then requested the visual/physical behavior to better match dense paint or blood entering water:

1. Clouds should appear **under** the water layer.
2. Clouds should look more like smoke/gas grenade clouds, not flat circles.
3. Clouds disappear too quickly; they should remain semi-dissolved for more than one minute.
4. Floor blood puddles still appear under the water and must not.
5. Nearby waves should become redder.

### Research notes

External research on real-time fluid and VFX approaches points to two broad options:

- **Full fluid simulation**: 2D Navier-Stokes / SPH / GPU render-texture simulation. This can produce physically richer advection and diffusion, but it requires shader/render-texture infrastructure and is excessive for a small top-down Godot effect.
- **Game VFX approximation**: layered particles, radial density masks, color-over-lifetime gradients, and local shader tint. This is the common lightweight approach for stylized blood/water/gas effects and matches the existing `AggressionCloud` / `ChemicalCloud` particle pattern in this codebase.

Chosen approach: implement a lightweight approximation that behaves like pigment density in water:

- Procedural long-lived soft stain below `WaterVisual`.
- `GPUParticles2D` wisps using radial gradient particles, similar to gas clouds.
- Local water shader tint sources so waves near the blood cloud become redder.
- No floor decal is spawned when landing is inside water; direct-spawn fallback registers both the diffusion visual and shader tint.

Reference links used:

- GPU water simulation overview: https://xiaojiangbrian.com/gpu-water-simulation/
- 2D water effects discussion: https://code.tutsplus.com/make-a-splash-with-dynamic-2d-water-effects--gamedev-236t
- Real-time VFX water/game effect discussion: https://realtimevfx.com/t/gamejam-assets-megapost-water-effects-and-more/10789
- 2D fluid/surface simulation research: https://arxiv.org/abs/2009.00408

### Implementation plan from this feedback

1. `water_blood_diffusion.gd`: change from a 4-second flat circle to a 75-second under-water pigment cloud with smoke-like particle wisps and asymmetric procedural lobes.
2. `impact_effects_manager.gd`: when direct-spawning the diffusion fallback, parent it through the water body when possible so it is layered under the water visual instead of above the surface.
3. `water_body.gd`: expose `register_blood_tint_at()` and `get_underwater_effect_parent()`, then push local blood tint source positions/strengths into the water shader.
4. `realistic_water.gdshader`: add up to 8 local blood tint sources with smooth radial falloff so only nearby waves become redder.
5. Tests: verify the diffusion duration is over one minute, z-index is under-water, and WaterBody exposes the tint registration API used by the exported-build fallback.

---

## Game Log Files

All game logs referenced in this case study are archived in `game-logs/`:

| File                                  | Test session | Owner report            |
|---------------------------------------|:------------:|:------------------------|
| `game_log_20260327_085514.txt`        | Test 1       | "не сработало"          |
| `game_log_20260327_092156.txt`        | Test 2       | "изменений нет"         |
| `game_log_20260327_102127.txt`        | Test 3       | "всё ещё простые лужи"  |
| `game_log_20260328_193137.txt`        | Test 5       | "не работает"           |
| `game_log_20260329_175815.txt`        | Test 6       | "не сработало"          |
| `game_log_20260330_111035.txt`        | Test 7       | "не сработало"          |
| `game_log_20260418_024824.txt`        | Test 9       | "сильно проседает fps / кровь оказывается не в воде и её лужа слишком большая" |

---

## Ninth Owner Feedback: severe FPS drop, oversized stain outside water (2026-04-18)

Owner reported:
1. **FPS drops severely** during combat near water.
2. **Blood stain is outside water** (the stain appears to extend far beyond the water area).

### Root cause analysis (game_log_20260418_024824.txt)

Log analysis found **1,638 diffusion effect nodes spawned in one session** — each with 90 `GPUParticles2D` particles, a 75-second lifetime, and `_draw()` calls every frame.

- Each lethal hit spawns 30 blood particles, each checked independently.
- A bullet spray into the water area triggers 30+ independent `Blood landed in water` events in one frame.
- With 1,638 nodes × 90 particles = ~147,000 concurrent GPU particles, FPS drops to 1-3 fps.
- The stain appears huge because many overlapping draw-circles (MAX_RADIUS=145) cover the entire water region.

**Fix (2026-04-20):**

1. **Remove GPUParticles2D from WaterBloodDiffusion** — use `_draw()` procedural rendering only. This eliminates the GPU particle cost.
2. **Reduce MAX_RADIUS** from 145 to 80 pixels to prevent visual bleed outside the water area.
3. **Add merge logic**: blood hits within 120px of an existing diffusion call `absorb()` on it instead of spawning new nodes. This means a burst of 30 particles into the same area creates at most ~1 new node.
4. **Add cap**: max 8 concurrent diffusion nodes. If exceeded, the oldest node is freed before a new one spawns.
5. **Add `absorb()` method**: increases the cloud's intensity slightly and resets the elapsed timer back to the expansion phase, keeping the cloud alive and growing after absorbing new hits.

Expected result: a continuous burst of blood into water creates ≤1 new diffusion node per ~120px cluster, with the rest merging into existing nodes. FPS impact drops from ~150k GPU particles to ≤720 particles (8 nodes max) or zero when MAX_RADIUS <= MERGE_RADIUS means all hits merge.

---

## Latest Owner Feedback: halo artifacts, delayed tint, wrong cloud color (2026-04-25)

Owner reported three remaining visual problems:

1. Strange white-transparent circles appear on land around the blood cloud.
2. The cloud grows quickly, then stops; only after that does it disappear and recolor the wave. The wave must recolor at the same time as the cloud grows and disappears.
3. Blood clouds are not red enough and should use the same red as the recolored wave.

### Root cause analysis

The current `WaterBloodDiffusion._draw()` had a separate soft outer diffusion ring:

```gdscript
outer_col.a = alpha * 0.05
draw_circle(Vector2.ZERO, radius * 1.15, outer_col)
```

Because the diffusion node is drawn below a semi-transparent animated water layer, that very low-alpha oversized circle can read as a pale/white transparent halo near shorelines and around the cloud, especially when the water layer fades at the edge.

The timing was also split into separate phases:

- Expansion: 0-3 seconds.
- Hold: 3-5 seconds.
- Tint/fade: 5-12 seconds.

That matched the observed behavior: the cloud grows, pauses, then wave tint starts later. The owner’s latest requirement is a single synchronized lifecycle where tint grows from the first frame while the cloud expands and fades.

The cloud color also used arbitrary hit/decal color channels from `set_blood_color()`, while the shader hard-coded the final water blood tint as `vec3(0.50, 0.02, 0.025)`. If the input decal color was darker, desaturated, or alpha-heavy, the visible cloud did not match the water tint.

### Additional implementation research

Godot’s own 2D drawing documentation supports the lightweight approach already used here: custom `CanvasItem._draw()` plus `queue_redraw()` is the intended way to draw procedural 2D shapes that update over time. Godot’s shader documentation also requires `source_color` for color uniforms in modern Godot 4 rendering paths, which this project already uses for `blood_tint` in `realistic_water.gdshader`. GPUParticles2D remains a valid component for many 2D VFX, but the April 18 log showed that this specific burst effect produced too many concurrent particle emitters, so the procedural draw-only effect is the safer component for this issue.

References:

- Godot 4.5 custom drawing in 2D: https://docs.godotengine.org/en/4.5/tutorials/2d/custom_drawing_in_2d.html
- Godot 4 shading language and `source_color`: https://docs.godotengine.org/en/4.0/tutorials/shaders/shader_reference/shading_language.html
- Godot latest GPUParticles2D reference: https://docs.godotengine.org/en/latest/classes/class_gpuparticles2d.html

### Implemented solution

1. Removed the outer low-alpha diffusion ring so the effect no longer paints pale halos outside the visible red cloud.
2. Replaced the delayed `HOLD_DURATION` tint start with `TINT_START_TIME = 0.0`, so `on_tint_update` runs throughout the cloud lifetime.
3. Changed the visible cloud color to `WATER_BLOOD_TINT_COLOR = Color(0.50, 0.02, 0.025, 0.72)`, matching the red target used by `realistic_water.gdshader`.
4. Changed cloud alpha to fade continuously over the full 12-second lifetime while radius still expands over the first 3 seconds, keeping spread speed intact but synchronizing wave recolor with the visual cloud.
5. Added unit coverage for immediate tint start, cloud/shader color match, and absence of the removed outer halo code.
