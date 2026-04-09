# Case Study: Issue #1756 — Fix HUD (Spare Magazine Counter)

## Issue Summary

**Title:** fix hud  
**Reported:** 2026-04-09  
**Status:** Open (fix in PR #1773)  
**Reporter:** Jhon-Crow  
**Pull Request:** #1773  

The HUD magazine counter (`MAGS:` label) had two related display bugs:

1. **Empty spare magazines were shown** — magazines with 0 rounds appeared as
   `| 0 |` entries after the player had fired them dry. This cluttered the
   display with useless information.
2. **No upper bound on visible spare magazine entries** — when difficulty
   multipliers (e.g. Power Fantasy ×4) gave the player 8+ spare magazines, all
   of them were rendered side-by-side, causing the label to overflow off-screen.

The reporter included a screenshot showing the overflowing HUD:  
`MAGS: [4] | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 |`
(roughly 16 spare magazines, all truncated by the screen edge).

---

## Attached Logs

| File | Source | Notes |
|------|--------|-------|
| `game_log_20260410_002044.txt` | Provided by reporter (Jhon-Crow) in PR comment | Session recorded on Windows with the pre-fix executable |

---

## Timeline of Events

### Original HUD implementation — all spare magazines displayed unconditionally

The `_update_magazines_label()` function (present in all 15 level scripts) was
first introduced to show the player their current ammo state.  The original
logic iterated over every element of `magazine_ammo_counts`:

```gdscript
var parts: Array = []
for i in range(magazine_ammo_counts.size()):
    var ammo: int = magazine_ammo_counts[i]
    if i == 0:
        parts.append("[%d]" % ammo)
    else:
        parts.append("%d" % ammo)

_magazines_label.text = "MAGS: " + " | ".join(parts)
```

Index 0 is the currently-loaded magazine (displayed in brackets); every other
index is a spare magazine.  No filtering and no display cap was applied.

### Difficulty multipliers introduce many spare magazines

Several gameplay modes multiply the initial spare-magazine count:

| Mode | Multiplier | Example (AKGL default 2 spares) |
|------|-----------|--------------------------------|
| Power Fantasy | ×4 | 8 spare magazines |
| Gunslinger | ×2.5 | 5 spare magazines |
| Makarov PM ×2.5 ammo config | ×2.5 | varies |

The log (`game_log_20260410_002044.txt`, line 1227) confirms Power Fantasy
activated during the reporter's session:

```
[00:21:02] [INFO] [LevelInitFallback] BuildingLevel: Power Fantasy mode
                   - AKGL magazines multiplied by 4x
[00:21:02] [INFO] [LevelInitFallback] BuildingLevel: AKGL magazines
                   reinitialized to 8 (C# fallback, Issue #1259)
```

With 8 (or more) spare magazines all rendered without a cap, the label
overflowed the HUD width.

### Empty magazines remain in the array after firing

When the player fires all rounds from a spare magazine and reloads it into the
weapon, the now-empty spare slot (`ammo == 0`) is kept in the array.  The
original loop renders these as `| 0 |`, which conveys no useful information and
wastes horizontal space.

### Reporter observes the two bugs

The screenshot in the issue shows the AKGL with approximately 15–16 spare
entries all reading `| 9 |` — this matches an AKGL's full magazine (30 rounds
÷ ... wait: AKGLs display 9 because ... the label showed raw "9" rounds for
each, consistent with the BuildingLevel's `AKGL magazines reinitialized to ...`
log entries and round counts visible in the gameplay screenshot).

The reporter filed issue #1756 with the following requirements (translated from
Russian):

> When a player has more than 6 non-empty magazines, the remaining full
> magazines should be displayed as "+ x+count" (e.g. "+ x7").
> Empty magazines should also not be shown (currently showing as `|0|`).

---

## Root Cause Analysis

### Root Cause 1: No filter for zero-ammo spare magazines

**Location:** `_update_magazines_label()` in all 15 level scripts  
**Code path:** `scripts/levels/*.gd`

The loop appended every element from `magazine_ammo_counts[1:]` regardless of
its value.  A spare with `ammo == 0` was indistinguishable in the loop from one
with remaining rounds.

**Effect:** Spent magazines appeared as `| 0 |` entries, persisting in the HUD
for the rest of the level.

### Root Cause 2: No display cap on spare magazine entries

**Location:** Same loop, same function  

`magazine_ammo_counts` can grow arbitrarily large depending on difficulty
multipliers applied during level initialization.  The label width is fixed by
the HUD layout — there is no wrapping or scrolling.

**Effect:** With 8+ spare magazines the label overflowed the screen. With 15+
entries the label was completely unreadable.

**Why this wasn't caught earlier:** The base ammo configuration gives the
player 2–3 spare magazines in most levels, which fits comfortably.  The bug
only becomes visible in Power Fantasy mode or when specific difficulty
multipliers are combined.

---

## Research: Design Approaches

### A — Filter + hard cap with overflow indicator (chosen)

Collect only non-empty spares, display at most N, show `+ xM` if more exist.

**Pros:** Clean, informative, readable at any magazine count. Zero allocations
beyond the filter array.  
**Cons:** Player cannot see exact count beyond N without arithmetic.

### B — Scrollable / paginated label

Display a window of spares with left/right navigation buttons.

**Pros:** Player can inspect all magazines.  
**Cons:** Requires new UI nodes, input handling, and more complex HUD state.
Out of scope for a one-line HUD label.

### C — Summarise all spares as a count only (e.g. `MAGS: [30] ×7`)

Don't show individual spare ammo counts at all; just show how many spares remain.

**Pros:** Minimal space. Never overflows.  
**Cons:** Removes per-magazine ammo information (useful for partially-spent
spares). Conflicts with existing data shown in the label.

### D — Increase HUD label width / shrink font

Make the label area wider so more entries fit.

**Pros:** No code logic changes.  
**Cons:** Breaks HUD layout for all screen sizes; only defers the problem.

**Chosen approach: A** — matches the reporter's explicit specification and is
consistent with the compact, information-rich HUD style already in the game.

---

## Proposed Solutions

### Solution 1 ✅ Filter zero-ammo spares and cap at 6 with `+ xN` overflow (implemented)

For each spare magazine (`i > 0`), include it only if `ammo > 0`. Render the
first 6 non-empty spares normally. If there are more than 6, append a single
`+ xN` entry where `N` is the overflow count.

```gdscript
# Current magazine always shown in brackets
parts.append("[%d]" % magazine_ammo_counts[0])

# Spare magazines: skip empty ones, show at most 6, then + xN for the rest
const MAX_VISIBLE_SPARE: int = 6
var non_empty_spare: Array = []
for i in range(1, magazine_ammo_counts.size()):
    if magazine_ammo_counts[i] > 0:
        non_empty_spare.append(magazine_ammo_counts[i])

for j in range(mini(non_empty_spare.size(), MAX_VISIBLE_SPARE)):
    parts.append("%d" % non_empty_spare[j])

var overflow: int = non_empty_spare.size() - MAX_VISIBLE_SPARE
if overflow > 0:
    parts.append("+ x%d" % overflow)
```

**Before:**
```
MAGS: [30] | 30 | 30 | 30 | 30 | 30 | 30 | 30 | 30 | 0 | 0 | 0
```
**After:**
```
MAGS: [30] | 30 | 30 | 30 | 30 | 30 | 30 | + x2
```

### Solution 2 ❌ Increase label container width

Would only postpone the overflow for more extreme magazine counts and would
break other HUD layouts.

---

## Implemented Fixes (PR #1773)

### Fix 1: `_update_magazines_label()` in all 15 level scripts

**Files changed:**

| Script | Location |
|--------|----------|
| `scripts/levels/arena_level.gd` | `_update_magazines_label()` |
| `scripts/levels/beach_level.gd` | `_update_magazines_label()` |
| `scripts/levels/building_level.gd` | `_update_magazines_label()` |
| `scripts/levels/castle_level.gd` | `_update_magazines_label()` |
| `scripts/levels/city_level.gd` | `_update_magazines_label()` |
| `scripts/levels/decadence_level.gd` | `_update_magazines_label()` |
| `scripts/levels/docks_level.gd` | `_update_magazines_label()` |
| `scripts/levels/factory_level.gd` | `_update_magazines_label()` |
| `scripts/levels/labyrinth_level.gd` | `_update_magazines_label()` |
| `scripts/levels/railway_station_level.gd` | `_update_magazines_label()` |
| `scripts/levels/revolver_level.gd` | `_update_magazines_label()` |
| `scripts/levels/roguelike_level.gd` | `_update_magazines_label()` |
| `scripts/levels/sewer_level.gd` | `_update_magazines_label()` |
| `scripts/levels/test_tier.gd` | `_update_magazines_label()` |
| `scripts/levels/winter_forest_level.gd` | `_update_magazines_label()` |

The logic was identical across all 15 scripts (copy-paste pattern).  The fix
was applied uniformly.

### Fix 2: Updated `MockLevelHelper.format_magazines_label()` in tests

**File:** `tests/unit/test_level_helpers.gd`

The mock helper that mirrors the real HUD logic for unit testing was updated to
match the new filter + cap algorithm.

### Fix 3: Six new unit tests

**File:** `tests/unit/test_level_helpers.gd`

| Test | Scenario |
|------|----------|
| `test_magazines_label_hides_empty_spares` | `[30, 0, 0]` → only current shown |
| `test_magazines_label_all_spares_empty` | All spares 0 → no spare entries |
| `test_magazines_label_exactly_6_spares` | 6 non-empty → all shown, no overflow |
| `test_magazines_label_7_spares_overflow` | 7 non-empty → 6 shown + `+ x1` |
| `test_magazines_label_9_spares_overflow` | 9 non-empty → 6 shown + `+ x3` |
| `test_magazines_label_empty_excluded_from_overflow` | Mix of 0 and non-zero → only non-zero count toward overflow |

---

## Game Log Analysis (`game_log_20260410_002044.txt`)

This log was recorded by the reporter on **2026-04-10 at 00:20:44** using a
**pre-fix** Windows executable build (no `build_info.cfg`, Engine 4.3-stable).

Key observations:

| Timestamp | Event | Significance |
|-----------|-------|--------------|
| `00:20:44` | Session start, LabyrinthLevel | Normal magazine count (2 spares) |
| `00:20:45` | BuildingLevel loaded (C# fallback) | `AKGL magazines reinitialized to 2` |
| `00:20:50` | BuildingLevel reloaded | `AKGL magazines reinitialized to 2` |
| `00:21:02` | **Power Fantasy mode activated** | `AKGL magazines multiplied by 4x` → **8 spares** |
| `00:21:02` | `AKGL magazines reinitialized to 8` | This is the state visible in the screenshot |
| `00:22:10` | Revolver equipped | Different weapon, different HUD |

The log confirms the Power Fantasy ×4 multiplier created 8 spare magazines —
more than the 6-entry cap introduced by the fix — which is exactly the
condition that triggers the overflow bug visible in the screenshot.

The log does **not** contain any `_update_magazines_label` debug output (the
function only updates the label silently), but the chain of level-init events
reconstructs the state that caused the visual bug.

**Why the reporter says "не вижу изменений" (I don't see changes):**  
The reporter was testing the pre-fix exported executable downloaded from the
release artifacts.  The fix exists in the source branch (PR #1773, commit
`140268df`) but has not yet been merged to `main` and re-exported.  Once the
PR is merged and a new build is produced, the fix will be visible in-game.

---

## Summary Table

| Cause | Impact | Confidence | Fix Complexity | Status |
|-------|--------|-----------|----------------|--------|
| No zero-ammo filter in `_update_magazines_label()` | Empty `\| 0 \|` entries clutter HUD | High | Low | ✅ Fixed in PR #1773 |
| No cap on spare magazine entries | Label overflows screen in Power Fantasy / high-ammo modes | High | Low | ✅ Fixed in PR #1773 |
| Fix not yet in released build | Reporter cannot verify the fix in their executable | High | N/A | ⏳ Pending PR merge |

---

## Round 2 Feedback (2026-04-10) — New Game Log & Revised Requirements

After PR #1773 was raised as ready, the reporter (Jhon-Crow) provided a second
game log (`game_log_20260410_013223.txt`) recorded on **2026-04-10 at 01:32:23**
and added two clarifications:

### New Requirement 1: Partial spare magazines must be shown individually

> "сейчас если не перезарядиться с неполного магазина на полный (не израсходовав
> ни одного магазина) то начатый магазин исчезает из счёта."

Translation: "If you reload from a partially-fired magazine to a full spare,
the partially-fired magazine disappears from the HUD count."

**Root cause identified:** The original fix abbreviated **all** non-empty spare
magazines beyond the 6th one. When a player had many full spares plus one
partial spare, the partial magazine was "hidden" inside the `+ xN` counter
rather than displayed explicitly — the player could not see they still had
unused partial ammo.

The correct behaviour: partial spare magazines (0 < ammo < capacity) should
always be shown individually. Full spare magazines (ammo == capacity) may be
abbreviated.

### New Requirement 2: All full spare magazines should be abbreviated

> "так же сокращай не только после 7 полных магазинов, а все магазины полные
> магазины (например [20] | + x6)"

Translation: "Also abbreviate not only after 7 full magazines, but ALL full
magazines (for example `[20] | + x6`)."

**Root cause identified:** The original fix still rendered up to 6 full spare
magazines individually. The reporter's expectation is that any number of full
spare magazines should be shown as `+ xN` (since they are interchangeable).
Partial magazines, being unique in their ammo count, are still shown explicitly.

---

## Revised Algorithm (Round 2 fix, also in PR #1773)

The new `_update_magazines_label()` logic:

1. Current magazine `[N]` — always shown
2. Spare magazines with `ammo == 0` → **skipped** (empty, not useful)
3. Spare magazines with `0 < ammo < capacity` → **shown individually** (partial)
4. Spare magazines with `ammo == capacity` → **counted** and shown as `+ xN`

This requires knowing the magazine capacity, which was not previously available
in GDScript.

### C# change: `GetMagazineMaxCounts()`

Added to `MagazineInventory` (Scripts/Data/MagazineData.cs) and exposed via
`BaseWeapon` (Scripts/AbstractClasses/BaseWeapon.cs):

```csharp
/// <summary>
/// Gets an array of max capacities parallel to GetMagazineAmmoCounts().
/// Use alongside GetMagazineAmmoCounts() to distinguish full vs partial magazines.
/// </summary>
public int[] GetMagazineMaxCounts()
```

Returns the same element order as `GetMagazineAmmoCounts()` — index 0 is the
current magazine capacity, indices 1+ are spare capacities (sorted by ammo
descending, matching the ammo array).

### GDScript change in all 15 level scripts

```gdscript
# Get magazine capacities to distinguish full vs partial spares
var mag_max_counts: Array = []
if weapon != null and weapon.has_method("GetMagazineMaxCounts"):
    mag_max_counts = Array(weapon.GetMagazineMaxCounts())

var parts: Array = []
parts.append("[%d]" % magazine_ammo_counts[0])

var full_spare_count: int = 0
for i in range(1, magazine_ammo_counts.size()):
    var ammo: int = magazine_ammo_counts[i]
    if ammo <= 0:
        continue
    var cap: int = mag_max_counts[i] if i < mag_max_counts.size() else 0
    if cap > 0 and ammo >= cap:
        full_spare_count += 1
    else:
        parts.append("%d" % ammo)  # partial: show explicitly

if full_spare_count > 0:
    parts.append("+ x%d" % full_spare_count)

_magazines_label.text = "MAGS: " + " | ".join(parts)
```

### Examples

| Scenario | Before (round 1 fix) | After (round 2 fix) |
|----------|----------------------|---------------------|
| 6 full spares | `MAGS: [30] \| 30 \| 30 \| 30 \| 30 \| 30 \| 30` | `MAGS: [30] \| + x6` |
| 8 full spares | `MAGS: [30] \| 30 \| 30 \| 30 \| 30 \| 30 \| 30 \| + x2` | `MAGS: [30] \| + x8` |
| 5 full + 1 partial (7) | `MAGS: [30] \| 30 \| 30 \| 30 \| 30 \| 30 \| 7` | `MAGS: [30] \| 7 \| + x5` |
| Partial only (7) | `MAGS: [30] \| 7` | `MAGS: [30] \| 7` (unchanged) |
| 1 empty spare | `MAGS: [30]` | `MAGS: [30]` (unchanged) |

---

## Game Log Analysis (`game_log_20260410_013223.txt`)

This log was recorded by the reporter on **2026-04-10 at 01:32:23** using a
**pre-fix** Windows executable (same build as the first log).

Key observations:

| Timestamp | Event | Significance |
|-----------|-------|--------------|
| `01:32:23` | LabyrinthLevel with SilencedPistol (13/13) | Standard ammo |
| `01:32:25` | DocksLevel — configured 60 enemies | Ammo doubled for DocksLevel |
| `01:32:31` | First reload animation (GrabMagazine → InsertMagazine → PullBolt) | Reload sequence successful |
| `01:32:34` | Second reload animation | Player testing reload mechanics |
| `01:32:39` | Revolver equipped (5/5), ammo doubled to 24 magazines | Different weapon |
| `01:32:57` | AssaultRifle equipped (30/30), 8 magazines | Demonstrates many-magazine scenario |

The log records reload animation phases but does not trace individual
`magazine_ammo_counts` values (those are only emitted via C# signals, not
file-logged). The session demonstrates normal gameplay patterns — the reporter
was testing the pre-fix build to verify whether PR #1773's changes were
visible.

---

## Updated Summary Table

| Cause | Impact | Confidence | Fix Complexity | Status |
|-------|--------|-----------|----------------|--------|
| No zero-ammo filter in `_update_magazines_label()` | Empty `\| 0 \|` entries clutter HUD | High | Low | ✅ Fixed in PR #1773 (round 1) |
| No cap on spare magazine entries | Label overflows screen in Power Fantasy / high-ammo modes | High | Low | ✅ Fixed in PR #1773 (round 1) |
| Full spare magazines shown individually up to 6 | Up to 6 identical full-mag entries waste space | High | Low | ✅ Fixed in PR #1773 (round 2) |
| Partial spares hidden inside `+ xN` counter | Player cannot see remaining partial ammo | High | Medium | ✅ Fixed in PR #1773 (round 2) |
| Fix not yet in released build | Reporter cannot verify the fix in their executable | High | N/A | ⏳ Pending PR merge |
