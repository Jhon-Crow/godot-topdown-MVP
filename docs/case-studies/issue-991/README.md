# Case Study: Issue #991 — Fix AK Tutorial (fix обучение АК)

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/991  
**Reported by:** Jhon-Crow  
**Created:** 2026-03-11T17:19:39Z  
**Status:** OPEN  
**Related PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/946 (merged 2026-03-11)

---

## 1. Issue Description (original, Russian + translation)

**Original:**
> было добавлено обучение по строкам https://github.com/Jhon-Crow/godot-topdown-MVP/pull/946
> подсказки для АК появились но перекрываются подсказками гранаты
> [screenshot: overlapping hint labels]
> обе надписи пропадают после броска гранаты, но строка подствольного гранатомёта не исчезает после выстрела подствольного гранатомёта.

**Translation:**
> Tutorial lines-by-strings were added via PR #946. The AK hints now appear, but they are overlapped by the grenade hints. Both labels disappear after throwing a grenade, but the underbarrel grenade launcher line does NOT disappear after firing the underbarrel grenade launcher.

### Reported Bugs (2 distinct problems)

| # | Description | Severity |
|---|---|---|
| Bug 1 | AK tutorial hints are visually overlapped by the grenade tutorial hints | Visual / UX |
| Bug 2 | The underbarrel grenade launcher (GL) hint line does NOT disappear after the player fires the GL | Logic / UX |

---

## 2. Context and Background

### Timeline of Events

| Date | Event |
|---|---|
| 2026-03-02 | PR #946 opened by @konard — "Fix tutorial training lines per issue #945" |
| 2026-03-02 | Round 1 (AI): Initial fix implementing line-by-line tutorial system |
| 2026-03-02 | Round 2 feedback (Jhon-Crow): hint overlap + Lab level not updated |
| 2026-03-02 | Round 2 (AI): Fixed overlap with label.visible = false; updated labyrinth_level.gd |
| 2026-03-02 | Round 3 feedback (Jhon-Crow): 10 more bugs identified |
| 2026-03-05 | Round 3 (AI): Fixed 10 bugs including increased HINT_SPACING 50→60px, fixed grenade ordering, AK GL hint added after reload, etc. |
| 2026-03-07 | Round 4 feedback (Jhon-Crow): 5 bugs including AK GL hint not appearing on Lab map |
| 2026-03-07 | Round 4 (AI): Fixed 5 bugs including AK GL hint appearing after reload |
| 2026-03-07 | Round 5 feedback (Jhon-Crow): 4 more bugs including AK+Revolver training broken |
| 2026-03-07 | Round 5 (AI): Fixed 4 bugs including AK/Revolver tutorial on tutorial_level.gd |
| 2026-03-07 | Round 6 feedback (Jhon-Crow): AK + Revolver lines still missing on Labyrinth map, counter broken |
| 2026-03-11 | Round 6 (AI): Fixed duplicate weapon node issue in labyrinth_level.gd (missing weapon_names guard) |
| 2026-03-11T17:18:31Z | PR #946 merged by Jhon-Crow |
| 2026-03-11T17:19:39Z | Issue #991 opened by Jhon-Crow — reports 2 new bugs in the merged code |

### Key Finding: Issue #991 was opened 68 seconds after PR #946 was merged

The issue was filed immediately after the PR merge, based on final review of the merged result. The last comment on PR #946 from Jhon-Crow (at 17:16:29Z) already described these exact two bugs before the merge, meaning the PR was merged with known remaining issues.

---

## 3. File Inventory

| File | Path | Size | Role |
|---|---|---|---|
| tutorial_level.gd | scripts/levels/tutorial_level.gd | 1544 lines | Tutorial map hint logic |
| labyrinth_level.gd | scripts/levels/labyrinth_level.gd | 2284 lines | Labyrinth map hint logic |
| AKGL.cs | Scripts/Weapons/AKGL.cs | 692 lines | AK+GL C# weapon class |

Local copies of these files are included in this case study directory.

---

## 4. Root Cause Analysis

### Bug 1: AK Hints Overlapped by Grenade Hints

#### Sequence of Events

After PR #946's round 6 fix, when a player equips the AK+GL on the Labyrinth map:

1. Player fires 2+ shots → `_on_tutorial_weapon_fired()` triggers reload hint reveal
2. Player reloads → `_on_tutorial_reload_completed()` fires
3. In `_on_tutorial_reload_completed()` (labyrinth_level.gd ~line 1960):
   - `_dismiss_tutorial_hint(TUTORIAL_HINT_RELOAD)` is called ✓
   - `if _tutorial_has_ak_gl and ... _tutorial_ak_gl_has_round_loaded()` → `_add_tutorial_hint(TUTORIAL_HINT_GRENADE_LAUNCHER, ...)` — AK GL hint added ✓
   - `_tutorial_step = TutorialStep.THROW_GRENADE` is set ✓
   - Grenade hint is also added immediately: `_add_tutorial_hint(TUTORIAL_HINT_GRENADE, ...)` ✓

4. Both `TUTORIAL_HINT_GRENADE_LAUNCHER` (AK GL) and `TUTORIAL_HINT_GRENADE` (grenade throw) are now active simultaneously
5. The hint layout stacks hints in insertion order, with index 0 = closest to player
6. Because both hints are added in the same function call, they stack on top of each other visually at positions that overlap

#### Root Cause

The `_on_tutorial_reload_completed()` function adds the **AK GL grenade launcher hint** and then **immediately also adds the grenade throw hint** in the same code path. Both hints now appear at the same time, stacked only 60px apart. Since each hint can be 2 lines tall (with BBCode), 60px is insufficient to prevent visual overlap when two multi-line hints appear simultaneously.

The specific logic flaw (labyrinth_level.gd, around line 1976-1990):

```gdscript
# Bug fix #10: AK GL shows underbarrel grenade launcher hint after reload (if round loaded).
if _tutorial_has_ak_gl and canvas_layer and _tutorial_ak_gl_has_round_loaded():
    _add_tutorial_hint(TUTORIAL_HINT_GRENADE_LAUNCHER,
        "[color=#ff4444][ПКМ][/color] Выстрели подствольным гранатомётом", canvas_layer)
if _tutorial_has_thrown_grenade:
    _tutorial_step = TutorialStep.COMPLETED
    _dismiss_all_tutorial_hints()
else:
    _tutorial_step = TutorialStep.THROW_GRENADE
    # Bug fix #5: grenade hint shown AFTER reload disappears.
    if _tutorial_player_has_grenades():
        if canvas_layer and not _tutorial_hints.has(TUTORIAL_HINT_GRENADE):
            _tutorial_grenade_hint_step = 0
            _tutorial_grenade_g_was_held = false
            _add_tutorial_hint(TUTORIAL_HINT_GRENADE,
                _build_tutorial_grenade_hint_bbcode(0),
                canvas_layer)
```

The AK GL hint and grenade throw hint are added sequentially without any gate between them. For all other weapons (M16, pistol, etc.), the grenade hint is the only hint at the THROW_GRENADE step. But for AK+GL, there are now **two simultaneous hints** and the spacing system was not designed for this case.

The same issue exists in `tutorial_level.gd` around line 1158-1165.

#### Contributing Factor: HINT_SPACING insufficient for 2 simultaneous multi-line hints

`TUTORIAL_HINT_SPACING = 60.0` was set in round 3 to prevent overlap for one hint of 2 lines. When two separate hints of 2 lines each are stacked, they require at least 80-100px apart at 20px font size.

---

### Bug 2: GL Hint Line Does Not Disappear After Firing the Underbarrel GL

#### Sequence of Events

1. Player reloads → `TUTORIAL_HINT_GRENADE_LAUNCHER` hint appears: "[ПКМ] Выстрели подствольным гранатомётом"
2. Player presses RMB → `AKGL.FireGrenadeLauncher()` runs in C#
3. In `AKGL.cs` (line 383-391):
   ```csharp
   GrenadeAvailable = false;
   // ...
   EmitSignal(SignalName.GrenadeFired);
   EmitSignal(SignalName.GrenadeAvailabilityChanged, false);
   ```
4. The `GrenadeFired` and `GrenadeAvailabilityChanged` signals are emitted
5. Neither `tutorial_level.gd` nor `labyrinth_level.gd` has connected to `GrenadeFired` or `GrenadeAvailabilityChanged`
6. The `TUTORIAL_HINT_GRENADE_LAUNCHER` hint is **never dismissed**

#### Root Cause

The `HINT_GRENADE_LAUNCHER` / `TUTORIAL_HINT_GRENADE_LAUNCHER` hint is added by `_on_*_reload_completed()` when the AK GL has a round loaded, but **no signal handler exists** to dismiss it when the grenade launcher actually fires.

`AKGL.cs` exposes two relevant signals:
- `GrenadeFired` — emitted exactly when the GL fires (line 390)
- `GrenadeAvailabilityChanged` — emitted with `false` when the round is consumed (line 391)

Neither signal is connected in `tutorial_level.gd` or `labyrinth_level.gd` at any point. A grep for `GrenadeFired` and `GrenadeAvailabilityChanged` in both files returns no results.

The only GL-related signal connection made is to `FireModeChanged` (which AKGL does not even have, per the code comment at line 649 of labyrinth_level.gd).

#### Why "Both Hints Disappear After Throwing a Grenade" (Observed Behavior)

The owner noted that "both inscriptions disappear after throwing a grenade." This is because `_on_tutorial_grenade_thrown()` calls `_dismiss_all_tutorial_hints()` (or iterates over all hint keys), which removes **all** active hints including `TUTORIAL_HINT_GRENADE_LAUNCHER`. The GL hint disappearing on grenade throw is a side effect of the blanket "dismiss all" call, not a proper dismissal triggered by actually firing the GL.

---

## 5. Affected Code Sections

### tutorial_level.gd

| Lines | Function | Issue |
|---|---|---|
| 1155-1165 | `_on_player_reload_completed()` | Adds GL hint and grenade hint simultaneously without sequencing |
| 568-583 | `_connect_player_signals()` (AKGL block) | Does not connect to `GrenadeFired` or `GrenadeAvailabilityChanged` |
| (missing) | (no handler) | No `_on_grenade_launcher_fired()` handler exists |

### labyrinth_level.gd

| Lines | Function | Issue |
|---|---|---|
| 1973-1990 | `_on_tutorial_reload_completed()` | Adds GL hint and grenade hint simultaneously without sequencing |
| 646-649 | `_setup_player_tracking()` (AKGL block) | Does not connect to `GrenadeFired` or `GrenadeAvailabilityChanged` |
| (missing) | (no handler) | No `_on_tutorial_grenade_launcher_fired()` handler exists |

### AKGL.cs

| Lines | Element | Notes |
|---|---|---|
| 138-145 | `GrenadeFiredEventHandler` signal | Emitted when GL fires — not connected in GDScript levels |
| 143-145 | `GrenadeAvailabilityChangedEventHandler` signal | Emitted with `false` on GL fire — not connected in GDScript levels |
| 383 | `GrenadeAvailable = false` | State correctly set to false after firing |
| 390-391 | `EmitSignal(GrenadeFired)` / `EmitSignal(GrenadeAvailabilityChanged, false)` | Signals emitted but unhandled |

---

## 6. Proposed Solutions

### Solution A: Fix Bug 2 First (GL Hint Dismissal) — Highest Priority

**Connect to `GrenadeFired` signal in both level scripts.**

In `tutorial_level.gd`, inside the AKGL connection block (~line 568):
```gdscript
elif akgl != null:
    _assault_rifle = akgl
    _has_ak_gl = true
    _connect_weapon_fired_signal(akgl)
    # ... existing reload signal connections ...
    
    # NEW: connect to GL fired signal to dismiss the GL tutorial hint
    if akgl.has_signal("GrenadeFired"):
        akgl.GrenadeFired.connect(_on_grenade_launcher_fired)
        print("Tutorial: Connected to GrenadeFired signal (AKGL)")
```

Add a new handler:
```gdscript
func _on_grenade_launcher_fired() -> void:
    _dismiss_hint(HINT_GRENADE_LAUNCHER)
    print("Tutorial: GL fired — dismissed grenade launcher hint")
```

Apply identical changes to `labyrinth_level.gd` using `TUTORIAL_HINT_GRENADE_LAUNCHER` and `_dismiss_tutorial_hint()`.

---

### Solution B: Fix Bug 1 (AK GL + Grenade Hint Overlap) — 2 sub-options

#### Option B1: Sequence the hints (GL hint first, then grenade hint after GL fires)

After the GL hint is dismissed (via `_on_grenade_launcher_fired()`), then show the grenade throw hint. This gives the player a clear two-step flow:
1. Reload → GL hint appears → "Fire the underbarrel GL [RMB]"
2. GL fires → GL hint dismissed → Grenade throw hint appears → "Throw a grenade [G+RMB]"

This is the cleanest UX approach and requires:
- Removing the immediate grenade hint add from `_on_*_reload_completed()`
- Adding the grenade hint in `_on_grenade_launcher_fired()` after dismissing the GL hint

```gdscript
func _on_grenade_launcher_fired() -> void:
    _dismiss_hint(HINT_GRENADE_LAUNCHER)
    print("Tutorial: GL fired — showing grenade hint")
    # Now show grenade hint as the next step
    var canvas_layer := get_node_or_null("CanvasLayer")
    if canvas_layer and _player_has_grenades() and not _has_thrown_grenade:
        _grenade_hint_step = 0
        _grenade_g_was_held = false
        _add_hint(HINT_GRENADE, _build_grenade_hint_bbcode(0), canvas_layer)
```

And in `_on_player_reload_completed()`, for the AK GL path, do NOT immediately add the grenade hint — wait for the GL to fire first:
```gdscript
if _has_ak_gl and canvas_layer and _ak_gl_has_round_loaded():
    _add_hint(HINT_GRENADE_LAUNCHER,
        "[color=#ff4444][ПКМ][/color] Выстрели подствольным гранатомётом", canvas_layer)
    # Do NOT add grenade hint here — it will appear after GL fires
    if not _has_thrown_grenade:
        _advance_to_step(TutorialStep.THROW_GRENADE)
    else:
        _advance_to_step(TutorialStep.COMPLETED)
    return
```

#### Option B2: Increase HINT_SPACING for AK GL weapon specifically

If sequencing is not desired and both hints must appear simultaneously, increase `HINT_SPACING` from 60 to 90px. This is a minimal fix but may cause hints to go off-screen on small viewports.

**Recommendation: Option B1** — Sequencing (GL fires → grenade hint appears) is the correct UX design and eliminates the overlap entirely without requiring larger spacing.

---

### Solution C: Handle the case where GL was NOT reloaded (GrenadeAvailable = false)

After the PR #946 fix, `_ak_gl_has_round_loaded()` checks `GrenadeAvailable` at the time of reload completion. If the player fires the GL before reloading (e.g., fires GL → reloads → completes reload), then `GrenadeAvailable` would be `false` at reload time and the GL hint would NOT appear. This case is handled correctly by the existing `_ak_gl_has_round_loaded()` check.

However, if the player reloads FIRST and THEN fires the GL (normal flow), the GL hint appears and must be dismissed. Solution A covers this.

---

## 7. Summary of Root Causes

| Bug | Root Cause | Fix |
|---|---|---|
| Bug 1: Hints overlap | GL hint and grenade throw hint both added simultaneously in `_on_*_reload_completed()` without sequencing | Add GL hint → wait for GL fire → add grenade hint sequentially |
| Bug 2: GL hint never dismissed | No connection to `GrenadeFired` or `GrenadeAvailabilityChanged` signal from `AKGL.cs`; `_dismiss_hint(HINT_GRENADE_LAUNCHER)` is never called except as a side-effect of global dismiss-all on grenade throw | Connect `GrenadeFired` signal → call `_dismiss_hint(HINT_GRENADE_LAUNCHER)` |

---

## 8. Data Sources

- GitHub Issue #991: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/991
- GitHub PR #946 (6 review rounds, 37 comments): https://github.com/Jhon-Crow/godot-topdown-MVP/pull/946
- Source file `scripts/levels/tutorial_level.gd` (main branch, 1544 lines) — local copy included
- Source file `scripts/levels/labyrinth_level.gd` (main branch, 2284 lines) — local copy included
- Source file `Scripts/Weapons/AKGL.cs` (main branch, 692 lines) — local copy included
- PR #946 merge commit: `8b583292600b32b81efafbcd55cd6659d700ae59`
- PR #946 head commit: `7eb7e027bafbad8a156d62a8b33530008cdddbcd`
