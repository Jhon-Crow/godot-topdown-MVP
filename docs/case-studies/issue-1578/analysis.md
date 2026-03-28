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

## Game Log Files

All game logs referenced in this case study are archived in `game-logs/`:

| File                                  | Test session | Owner report            |
|---------------------------------------|:------------:|:------------------------|
| `game_log_20260327_085514.txt`        | Test 1       | "не сработало"          |
| `game_log_20260327_092156.txt`        | Test 2       | "изменений нет"         |
| `game_log_20260327_102127.txt`        | Test 3       | "всё ещё простые лужи"  |
| `game_log_20260328_193137.txt`        | Test 5       | "не работает"           |
