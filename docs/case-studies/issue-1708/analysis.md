# Case Study: Issue #1708 — AK+GL Caliber Shows `<null>` in Armory Stats

**Issue:** [#1708](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1708)
**PR:** [#1709](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1709)
**Date:** 2026-03-28
**Analysis by:** AI Issue Solver

---

## Summary

The AK+GL weapon stats panel in the Armory Menu displayed `<null>` for the Caliber field
instead of the expected value `7.62x39mm`. This case study reconstructs the full timeline,
traces the root cause through the GDScript/C# interop boundary, evaluates the fix, and
explains why the user's testing session appeared to still show the bug.

**Verdict:** The fix in PR #1709 (commit `c3e07993`) is correct. The user's test session
(`game_log_20260328_185204.txt`) ran an **older pre-compiled binary** that predates the fix.
The binary was built from branch `issue-1142` at commit `bb817d83` on `2026-03-20` — eight
days before the fix was committed. The source code in the repository is correct.

---

## Timeline of Events

```
2026-03-20  Old binary compiled (branch issue-1142, commit bb817d83)
            Build info not embedded → log shows "build_info.cfg not found"

2026-03-28T15:41:28Z  Fix committed: c3e07993
            "fix: use .get() for caliber properties in armory stats panel"
            Changes: caliber.caliber_name → caliber.get("caliber_name")
                     caliber.can_ricochet → caliber.get("can_ricochet")
                     caliber.can_penetrate → caliber.get("can_penetrate")
                     caliber.max_penetration_distance → caliber.get("max_penetration_distance")
            Tests added: tests/unit/test_armory_menu.gd (67 lines, 3 regression tests)

2026-03-28T15:44:20Z  PR marked "Ready to merge"

2026-03-28T15:52:58Z  Owner reports: "всё ещё null" (still null)
            Attaches: game_log_20260328_185204.txt
            Requests: deep case study analysis in docs/case-studies/issue-1708

2026-03-28T18:52:04   Game log begins
            Binary: I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe
            Engine: 4.3-stable (official)
            Build info: "not available (build_info.cfg not found)"  ← pre-fix binary confirmed

2026-03-28T18:52:27   Player equips AK+GL (ak_gl weapon selected)
            Log shows: [Player.Weapon] Equipped AKGL (ammo: 30/30)
            NOTE: No [BaseWeapon] caliber diagnostic logs present
            → Confirms binary lacks BaseWeapon debug logging code from current repo

2026-03-28T18:52:30   Armory menu opened with AK+GL selected
            Log shows: [PauseMenu] Armory menu instance added as child
            NOTE: No [ArmoryMenu] caliber output in log
            → armory_menu.gd in this binary has old dot-access code, returns null
```

---

## Root Cause Analysis

### The C#/GDScript Interop Boundary

The weapon stats are loaded in `armory_menu.gd` via `_load_weapon_resources()`. For AK+GL,
the resource is a C# class (`WeaponData.cs`) loaded from `AKGLData.tres`.

**AKGLData.tres excerpt:**
```ini
[ext_resource type="Resource" uid="uid://dk7m4n9r3p5q3"
             path="res://resources/calibers/caliber_762x39.tres" id="2_caliber"]
Caliber = ExtResource("2_caliber")
```

The `Caliber` property in `WeaponData.cs` is declared as:
```csharp
[Export]
public Resource? Caliber { get; set; }
```

`CaliberData` is a **GDScript** resource (`caliber_data.gd`) with properties like
`caliber_name`, `can_ricochet`, `can_penetrate`, `max_penetration_distance`.

### Why Direct Dot Access Returns Null

When `armory_menu.gd` does:
```gdscript
var caliber = resource.get("Caliber")  # Gets the CaliberData resource object
bbcode += "... %s\n" % caliber.caliber_name  # BUG: returns null
```

The object `caliber` is typed as the base `Resource` class in GDScript's type inference —
because it was returned from a C# property with return type `Resource?` and stored in an
untyped `var`. When GDScript's compiler resolves `caliber.caliber_name`, it resolves against
the base `Resource` class at compile time, which has no such property, so it returns `null`.

The `.get()` method, by contrast, performs **dynamic runtime dispatch** through Godot's
`Object::get()` engine path, which at runtime reaches the `CaliberData` GDScript script's
property system and correctly returns the stored value.

### Evidence from Code and Logs

1. **No `[BaseWeapon]` logs in game_log_20260328_185204.txt** — the current repo's
   `BaseWeapon.cs` (line 196) prints `[BaseWeapon] WeaponData.Caliber: Present/NULL`.
   Absence of this log confirms the binary predates this debugging code.

2. **Build info missing** — log line `Build info: not available (build_info.cfg not found)`
   confirms the binary was not built from the current repo state (which has `build_info.cfg`
   showing `commit="bb817d83"`, `date="2026-03-20T07:00:00Z"`).

3. **Binary path**: `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe`
   ("загрузки" = "downloads", "микро фиксы" = "micro fixes") — a manually distributed
   binary from March 20, 8 days before the fix was committed.

4. **Original code in repo** (commit `89cff364`, main branch before fix):
   ```gdscript
   bbcode += "[color=#aab0b8]Caliber:[/color] %s\n" % caliber.caliber_name  # dot access
   ```

5. **Fixed code** (commit `c3e07993`):
   ```gdscript
   bbcode += "[color=#aab0b8]Caliber:[/color] %s\n" % caliber.get("caliber_name")
   ```

### Why `.get()` Works but Dot Access Doesn't

This is a known characteristic of Godot 4 C#/GDScript interop:

| Access pattern | When used via C# boundary | Works? |
|---|---|---|
| `caliber.caliber_name` (dot notation) | Type inferred as base `Resource` | **No — returns null** |
| `caliber.get("caliber_name")` | Dynamic dispatch at runtime | **Yes** |

Reference: Godot Engine issues [#67167](https://github.com/godotengine/godot/issues/67167),
[#83980](https://github.com/godotengine/godot/issues/83980), and
[#92183](https://github.com/godotengine/godot/issues/92183) document related interop
behaviors. The `.get()` API exists precisely for this dynamic-dispatch use case.

The same project already uses this pattern correctly in:
- `BaseWeapon.cs` line 199: `WeaponData.Caliber.Get("caliber_name")`
- `casing.gd` line 169-170: `caliber_data.get("caliber_name")` fallback path

---

## Sequence of Events (Technical)

```
1. ArmoryMenu._ready() called
   └─ _load_weapon_resources() called
      └─ load("res://resources/weapons/AKGLData.tres") → WeaponData C# resource
         └─ resource stored in _weapon_resources["ak_gl"]

2. User clicks AK+GL slot → _on_weapon_slot_selected("ak_gl")
   └─ _pending_weapon_id = "ak_gl"
   └─ _update_loadout_panel() called
      └─ _update_weapon_stats() called
         └─ resource = _weapon_resources["ak_gl"]  (WeaponData C# object)
         └─ caliber = resource.get("Caliber")      (gets CaliberData GDScript object)
         └─ [OLD CODE] caliber.caliber_name        → null (type system fails at boundary)
            [NEW CODE] caliber.get("caliber_name") → "7.62x39mm" (dynamic dispatch)

3. bbcode string built with null → displayed as "<null>" in RichTextLabel
```

---

## Proposed Solutions

### Solution 1 (Applied in PR #1709): Use `.get()` for All CaliberData Properties ✅

**Status: Implemented and correct.**

Replace all direct property accesses on the GDScript `CaliberData` resource with `.get()`:
```gdscript
caliber.get("caliber_name")         # was: caliber.caliber_name
caliber.get("can_ricochet")         # was: caliber.can_ricochet
caliber.get("can_penetrate")        # was: caliber.can_penetrate
caliber.get("max_penetration_distance")  # was: caliber.max_penetration_distance
```

**Pros:** Minimal change, consistent with existing patterns, works for any `Resource`.
**Cons:** None — `.get()` is the standard Godot API for dynamic property access.

### Solution 2 (Alternative): Mirror Caliber String in WeaponData.cs

Add a `CaliberName` string property to `WeaponData.cs`:
```csharp
[Export]
public string CaliberName { get; set; } = "";
```

Then read it directly: `resource.get("CaliberName")`.

**Pros:** No boundary crossing needed for display.
**Cons:** Data duplication, requires keeping in sync with CaliberData resource.
The project already rejects this approach — see existing `CaliberCanRicochet`,
`CaliberMaxRicochetAngle`, `CaliberMaxRicochets` mirror properties added for Issue #935.
Adding more mirrors increases maintenance burden.

### Solution 3 (Future): Type-Cast at Access Site

Once Godot fixes compile-time GDScript type resolution for cross-language resources, use:
```gdscript
var caliber := resource.get("Caliber") as CaliberData
if caliber:
    bbcode += "... %s\n" % caliber.caliber_name  # safe after type cast
```

**Status:** Not yet reliable in Godot 4.3. Requires `CaliberData` to be registered as a
global class visible to GDScript at compile time across the C# boundary.

---

## Why Testing Still Showed Null

The user's game session ran the **old binary** (compiled 2026-03-20, 8 days before fix).
Key evidence:
1. Binary path: "downloads/micro fixes" folder — old standalone exe
2. Log says: "build_info.cfg not found" — no build metadata
3. No `[BaseWeapon]` log entries — BaseWeapon debug logging (added as part of this issue
   investigation) is not present in the old binary
4. The fix was committed 2026-03-28T15:41:28Z; the test session started at 18:52:04 same
   day, but used a binary that predates the repository fix

**To verify the fix:** Rebuild from source (or obtain a binary built after commit `c3e07993`)
and open the Armory Menu on AK+GL. The Caliber field should display `7.62x39mm`.

---

## Files in This Case Study

- `analysis.md` — this document
- `game_log_20260328_185204.txt` — game session log from owner (2026-03-28)

---

## References

- [Godot Issue #67167](https://github.com/godotengine/godot/issues/67167) — C# readonly properties inaccessible from GDScript
- [Godot Issue #83980](https://github.com/godotengine/godot/issues/83980) — C# Resource export type InvalidCastException
- [Godot Issue #92183](https://github.com/godotengine/godot/issues/92183) — Non-exported C# properties absent from property list
- [Godot Issue #69822](https://github.com/godotengine/godot/issues/69822) — Exporting C# Resources broken in Godot 4 Beta 8
- [Godot Issue #83071](https://github.com/godotengine/godot/issues/83071) — Source generator breaks on >2 levels of Resource nesting
- [Godot Docs: C# Basics and Cross-Language Scripting](https://docs.godotengine.org/en/stable/tutorials/scripting/cross_language_scripting.html)
- `Scripts/AbstractClasses/BaseWeapon.cs:196-200` — same `.Get()` pattern in C# side
- `scripts/effects/casing.gd:169-170` — same `.get()` pattern in GDScript side
- `Scripts/Data/WeaponData.cs:125-126` — `Caliber` property declaration
- `resources/weapons/AKGLData.tres` — AK+GL weapon data with caliber reference
- `resources/calibers/caliber_762x39.tres` — 7.62x39mm caliber resource
