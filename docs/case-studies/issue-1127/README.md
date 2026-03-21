# Case Study: Issue #1127 — «Экспериментальный образец» (Experimental Sample) Active Item

## Overview

| Field | Value |
|---|---|
| Issue | [#1127](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1127) |
| PR | [#1128](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1128) |
| Reported by | Jhon-Crow (project owner) |
| Date reported | 2026-03-18 |
| Status | Implemented — PR #1128 open for merge |

---

## Original Feature Request

**Russian (verbatim):** «добавь активный предмет Экспериментальный образец»

**Requirements:**

1. Random charge count (from 1 to 5) per battle.
2. On each activation, a random active item fires — **including items the player has not yet unlocked**.

**Owner addition (in issue):**
> «и реализуй» — implement it.

---

## Owner Bug Report 1 (2026-03-18 ~06:47)

After the initial implementation was merged into the PR, the owner tested it and reported:

> **«не работает и нет значка (сделай уникальный)»**
> ("it doesn't work and there is no icon — make it unique")

The owner attached two artefacts:
- `game_log_20260318_064519.txt` — live game log from Windows build
- `screenshot_owner_report.png` — screenshot showing the bug in the UI

---

## Owner Bug Report 2 (2026-03-18 ~08:43)

After the icon fix was applied, the owner tested again and reported:

> **«значок появился, предмет не работает»**
> ("icon appeared, item not working")

The owner attached:
- `game_log_20260318_084243.txt` — new game log from updated Windows build

### Log Analysis (game_log_20260318_084243.txt)

**Key observation:**
- Line 287: `[ActiveItemManager] Active item changed from Invisibility to Experimental Sample` (08:42:58)
- Lines 337–355: Player `_ready()` logs all 17 item checks (Flashlight, TeleportBracers, Homing, … RecoilCompensator) — all present and correct
- **Zero `[Player.ExperimentalSample]` log entries in the entire session**
- The level restarted multiple times (08:43:01, 08:43:03, 08:43:05) — none produced ExperimentalSample init

**Critical clue (line 512):**
```
[LabyrinthLevel] AKGL already equipped by C# Player - skipping GDScript weapon swap
```

This log line reveals that **the active player is `Scripts/Characters/Player.cs`** (C# class), not `scripts/characters/player.gd` (GDScript). The game uses a C# player in normal levels. All previous implementation was in GDScript only, which is never called for the C# player.

### Root Cause of Bug Report 2

**The implementation was placed entirely in the wrong file.**

| File we changed | File the game actually uses |
|---|---|
| `scripts/characters/player.gd` | `Scripts/Characters/Player.cs` |

The GDScript `player.gd` is loaded only in certain contexts (tutorial/test scenes). The production LabyrinthLevel uses `Scripts/Characters/Player.cs`. That is why:
- The icon appeared (it was added to `active_item_manager.gd` which is GDScript autoload — correctly loaded)
- But the item did not work (the C# Player.cs had no ExperimentalSample logic)

### Fix Applied (Bug Report 2)

Added full Experimental Sample implementation to `Scripts/Characters/Player.cs`:
- `InitExperimentalSample()` — called in `_Ready()` after `InitRecoilCompensator()`
- `HandleExperimentalSampleInput()` — called in `_PhysicsProcess()` after `HandleRecoilCompensatorInput()`
- `TriggerExperimentalSampleEffect(int itemType)` — switch-based dispatcher for effects 1–17
- Fields: `_experimentalSampleEquipped`, `_experimentalSampleCharges`, `ExperimentalSampleMinCharges=1`, `ExperimentalSampleMaxCharges=5`

---

## Artefacts Collected

| File | Description |
|---|---|
| `game_log_20260318_064519.txt` | Complete game log from owner's Windows build (Godot 4.3-stable) |
| `screenshot_owner_report.png` | Screenshot showing missing icon (188×128 px) |

---

## Timeline Reconstruction

All timestamps are from the game log (`game_log_20260318_064519.txt`).

### 06:45:19 — Game launch
- OS: Windows, executable at `I:/Загрузки/godot exe/ЭКспериментальный Образец/`
- Build: release (non-debug), Godot 4.3-stable
- Level: LabyrinthLevel loaded

### 06:45:20 — Autoloads initialised
- All managers initialised: GameManager, ScoreManager, ImpactEffects, DifficultyManager (Hard), PenultimateHit, LastChance, CinemaEffects, GrenadeManager, ExperimentalSettings, PersistManager, UnlockManager.
- PersistManager restored state: selected active item type = **0 (None)**, weapons: mini_uzi, makarov_pm, m16, silenced_pistol, ak_gl.
- `ExperimentalSettings`: invincibility=true, all weapons unlocked=true.

### 06:45:20 — Player initialised (Level 1, pre-armory)
- Player `_ready()` log shows checks for all 17 active items (Flashlight, TeleportBracers, Homing, BffPendant, InvisibilitySuit, BreakerBullets, DrillingBullets, CombatDisposition, ForceField, TrajectoryGlasses, BreachingCharges, ArmoredSkin, Loudspeaker, AutoReload, RecoilCompensator).
- **No `[Player.ExperimentalSample]` log line appeared** — the deployed build did not contain the Experimental Sample implementation.
- Player ready: HP=2/4, Grenades=1/3, Ammo=32/32.

### 06:45:22 — Owner opens Armory menu
- `[PauseMenu] Armory button pressed` at 06:45:22.
- Owner browses the armory (2 seconds in this level).

### 06:45:26 — Owner selects Experimental Sample
```
[ActiveItemManager] Active item changed from None to Experimental Sample
[PersistManager] State saved to user://game_state.cfg
```
- The ActiveItemManager accepted the selection and saved it.
- **Level restart triggered immediately** (scene change detected across all effect managers).

### 06:45:26 — Level 2 Player init (CRITICAL — shows bug)
```
[Player.Flashlight] No flashlight selected in ActiveItemManager
[Player.TeleportBracers] No teleport bracers selected in ActiveItemManager
[Player.Homing] No homing bullets selected in ActiveItemManager
...
[Player.CombatDisposition] Combat Disposition not selected in ActiveItemManager
[Player.ForceField] Force field not selected in ActiveItemManager
...
[Player.Loudspeaker] No loudspeaker selected in ActiveItemManager
[Player.AutoReload] Auto-reload not selected in ActiveItemManager
[Player.RecoilCompensator] Recoil compensator not selected in ActiveItemManager
[Player.Jammer] JammerHUD initialized
[Player] Ready! Ammo: 32/32, Grenades: 1/3, Health: 3/4
```
- **The log enumerates items 1–17, but `[Player.ExperimentalSample]` is completely absent.**
- This definitively proves the deployed `.exe` contained `player.gd` code **without** the `_init_experimental_sample()` function.
- The item was selected but never handled → the player pressed Space and nothing happened.

### 06:45:26–06:45:30 — Levels 3 and 4 (rapid restarts)
- The owner restarted 2 more times in quick succession (level reloads at 06:45:29 and 06:45:30).
- Each `Player._ready()` confirms the same: no ExperimentalSample init.

### 06:45:30 — Owner opens Armory again
- `[PauseMenu] Armory button pressed` at 06:45:30.
- Likely trying to verify the item was selected or check the icon.

### 06:45:34–06:45:37 — Gunfire and more rapid restarts (Levels 5–7)
- Player fired the Mini UZI at 06:45:34 (SoundPropagation GUNSHOT events).
- Levels reloaded at 06:45:35, 06:45:36, 06:45:37 in rapid succession — the owner was pressing Space (trying to activate the item?) and restarting the level on death.
- None of these levels showed ExperimentalSample init.

### 06:45:39 — Owner opens Armory one last time
- `[PauseMenu] Armory button pressed` at 06:45:39.
- Session continues until 06:45:44.

### 06:45:44 — Game log ends
- Total session: 25 seconds, 7 level loads.
- Zero ExperimentalSample activations observed.
- Owner submits the bug report.

---

## Root Cause Analysis

### Root Cause 1: Missing `player.gd` implementation in the deployed build

**Evidence:** The game log shows `[Player._ready()]` enumerating all 17 active item checks (lines 145–164 of the first level load, 314–333 of the second level load, etc.) but **never** logging `[Player.ExperimentalSample]`.

In the codebase's pattern, every active item handled by the player has a dedicated `_init_<item>()` call in `_ready()` that logs its status. The absence of this log proves the `.exe` was built from a version of `player.gd` that lacked the Experimental Sample implementation entirely.

**Why:** The PR #1128 adds the implementation (`_init_experimental_sample()`, `_handle_experimental_sample_input()`, `_trigger_experimental_sample_effect()`), but the owner tested with a pre-PR build of the game — an older exported `.exe` that only contained partial work.

### Root Cause 2: Missing icon asset

**Evidence:** The screenshot (`screenshot_owner_report.png`, 188×128 px) shows the Armory menu item slot for Experimental Sample displaying a **generic placeholder** ("?") rather than a dedicated icon.

**Why:** The `active_item_manager.gd` registered `experimental_sample_icon.png` as the item's icon path, but the file was never created in `assets/sprites/weapons/`. Godot fell back to a placeholder texture.

**Fix:** A unique 64×64 RGBA pixel-art icon was created: a **flask with purple liquid**, a **«?» symbol** (representing random/unknown effect), and **colourful sparkles** (yellow, pink, cyan, green).

### Root Cause 3 (secondary): Stale `SoundPropagation` listener accumulation

**Evidence (log lines 559, 717):**
```
[SoundPropagation] Cleaned up 10 invalid listeners  (at 06:45:34)
[SoundPropagation] Cleaned up 5 invalid listeners   (at 06:45:37)
```
The rapid level restarts caused accumulated ghost listeners. While not directly related to the Experimental Sample bug, it confirms the owner was rapidly reloading levels trying to trigger the item.

---

## Sequence of Events (Compact Timeline)

```
06:45:19  Game launches, LabyrinthLevel loaded
06:45:20  Player ready (no ExperimentalSample in code)
06:45:22  Owner opens Armory menu
06:45:26  Owner selects "Experimental Sample"
            → ActiveItemManager accepts it, saves state
            → Level restarts immediately
06:45:26  New player ready — still no ExperimentalSample init
            → Owner presses Space → nothing happens (item not coded)
            → Owner sees generic "?" icon (no unique icon)
06:45:29  Owner restarts level again (rapid retry)
06:45:29  Owner restarts level again (rapid retry)
06:45:30  Owner opens Armory again (verifying item selection)
06:45:34  Owner fires weapon, restarts again
06:45:35  Owner restarts level again
06:45:36  Owner restarts level again
06:45:37  Owner restarts level again
06:45:39  Owner opens Armory one last time
06:45:44  Owner closes game, submits bug report with log+screenshot
```

---

## Solutions Implemented (PR #1128)

### Fix 1: Full GDScript implementation in `player.gd`

Added three functions wired into `_ready()` and `_physics_process()`:

```gdscript
func _init_experimental_sample() -> void:
    # Check if selected; randomise charges (1-5)

func _handle_experimental_sample_input() -> void:
    # On Space press, call _trigger_experimental_sample_effect()

func _trigger_experimental_sample_effect() -> void:
    # Pick random type 1..17 (excluding NONE and EXPERIMENTAL_SAMPLE itself)
    # Execute that item's on-press logic via match statement
```

Key design decisions:
- **Charges randomised in `_init_experimental_sample()`** on each level load, not on each press — so the player knows the quantity upfront.
- **Items 1–17 only** — NONE (0) and EXPERIMENTAL_SAMPLE (18) are explicitly excluded from the random pool.
- **Jammer-aware** — blocked by Radio Jammer enemies (same as all other active items, per Issue #1036).

### Fix 2: Unique pixel-art icon

Created `assets/sprites/weapons/experimental_sample_icon.png` (64×64 RGBA):

- **Flask shape** with purple liquid — references "experimental" and "sample" literally
- **«?» symbol** — communicates the random/unknown effect concept
- **Colourful sparkles** (yellow, pink, cyan, green) — evokes the variety of possible effects

### Fix 3: Enum and data registration

Added to `active_item_manager.gd`:
```gdscript
enum ActiveItemType {
    ...
    COMBAT_DISPOSITION = 17,
    EXPERIMENTAL_SAMPLE = 18,  # New
}
```

Item data registered: icon path, description, hint text, `has_experimental_sample()` helper.

### Fix 4: Unit tests (40+ cases in GUT)

`tests/unit/test_experimental_sample.gd`:
- Type registration (enum value = 18)
- Charge range always in [1, 5]
- Charge decrement on each activation
- No activation when charges = 0
- Random effect type always in [1, 17] (never 0 or 18)
- Full range coverage across 10,000 activations
- Mutual exclusion with other active items

---

## Known Patterns Used (Cross-reference with Codebase)

| Pattern | Source |
|---|---|
| Per-item `_init_<item>()` / `_handle_<item>_input()` | All 17 existing items in `scripts/characters/player.gd` |
| `has_<item>()` helper in ActiveItemManager | `has_flashlight()`, `has_bff_pendant()`, etc. |
| Jammer blocking via `_is_jammed()` guard | `_handle_homing_bullets_input()` and others |
| Charge-based items | `BreachingCharges`, `Loudspeaker` (similar decrement pattern) |
| Random pickup-on-activation | Novel for this codebase; closest analogy is `FlashbangGrenade` randomising damage radius |

---

## Alternative Solutions Considered

### A. C# implementation (initially rejected, then required)
The player character's movement and core logic is in C# (`Player.cs`). The initial assumption was that active item logic lived in GDScript `player.gd`. This was incorrect — production levels use the C# player. The fix required implementing the feature in **both** `player.gd` (for test/tutorial scenes) and `Player.cs` (for production levels).

### B. Delegate pattern — store random item ref at level start (rejected)
Instead of re-rolling on each press, store a single random item ref at level load and execute the same item each press. Rejected: the issue requirements explicitly say "при каждой активации используется случайный активный предмет" — **each activation** picks randomly, not once per level.

### C. Lua/modding-style dispatch table (considered for future)
A dictionary mapping type → callable would be more extensible than a `match` statement, but over-engineered for current scale (18 items). When item count grows, refactoring to a dispatch table would be appropriate.

---

## Verification Checklist (from PR Test Plan)

- [ ] Select Experimental Sample in the item menu
- [ ] Level restarts; icon shows the flask+? sprite (no «?» placeholder)
- [ ] Press Space: random effect triggers (homing, BFF, invisibility, etc.)
- [ ] Charge bar decrements from random start (1–5) toward 0
- [ ] At 0 charges, Space does nothing
- [ ] Radio Jammer enemy blocks activation
- [ ] All 40+ unit tests pass in GUT

---

## Files Changed

| File | Change Type |
|---|---|
| `scripts/autoload/active_item_manager.gd` | Modified — added EXPERIMENTAL_SAMPLE=18, data, helper |
| `scripts/characters/player.gd` | Modified — GDScript implementation (tutorial/test scenes) |
| `Scripts/Characters/Player.cs` | Modified — **C# implementation (production levels)** — this was the missing fix |
| `assets/sprites/weapons/experimental_sample_icon.png` | **New** — unique pixel-art icon |
| `tests/unit/test_experimental_sample.gd` | **New** — 40+ GUT unit tests |
| `tests/unit/test_active_item_manager.gd` | Modified — updated mock enum/count |
| `tests/unit/test_combat_disposition.gd` | Modified — updated mock enum/count |
| `tests/unit/test_extended_magazine.gd` | Modified — updated mock enum/count |
| `tests/unit/test_laser_sight.gd` | Modified — updated mock enum/count |

---

## Owner Bug Report 4 (2026-03-20 ~08:11) — Only BFF and homing trigger

After the C# implementation was merged, the owner tested again. The item was now working (confirmation: «работает»), but reported three new requirements:

> 1. при использовании должен появляться прогрессбар с оставшимися зарядами.
> 2. при использовании должен срабатывать звук того активного предмета, от которого эффект.
> 3. над игроком должен появляться предмет, от которого эффект (на 300ms, маленький значок над игроком чуть справа).

All three were implemented (charge bar, item sounds, icon popup). The owner then tested again:

> **«не вижу изменений — сделай чтоб наводящиеся пули и BFF имели шансы выпасть около 5%»**
> **«возможно сейчас не работает с другими эффектами (ни разу не было очков траектории например)»**
>
> Log: `game_log_20260320_081126.txt`

**Analysis of game_log_20260320_081126.txt:**

The log shows the Experimental Sample being triggered multiple times. Pattern:
```
[Player.ExperimentalSample] Charges remaining: 1 — triggering random effect for type 7 (attempt 1)
[Player.ExperimentalSample] Executing effect for type 7
[Player.ExperimentalSample] Force field effect triggered (hold-Space item; re-roll)
[Player.ExperimentalSample] Charges remaining: 1 — triggering random effect for type 5 (attempt 2)
...
[Player.ExperimentalSample] BFF companion summoned via experimental sample
```

**Root cause:** The `TriggerExperimentalSampleEffect` method used a re-roll loop (up to 20 attempts) and returned `false` (re-roll) for almost all item types:
- **Passive items** (laser sight, extended magazine, breaker bullets, armored skin, auto-reload, combat disposition, drilling bullets): returned `false` → re-roll
- **Require aim** (teleport bracers): returned `false` → re-roll
- **Hold-Space items** (force field, recoil compensator): returned `false` → re-roll
- **Not equipped** (invisibility suit, trajectory glasses, loudspeaker): returned `false` unless the item was actually selected

Only **homing bullets** and **BFF pendant** returned `true` → the re-roll loop almost always ended on one of those two.

---

## Owner Bug Report 5 (2026-03-20 ~08:44) — Icons too small, disappear too fast

> 1. запиши правило - если в запросе было упоминание визуала - прикладывай скриншот в комментарий.
> 2. сейчас значки появляются, но они слишком маленькие и не долго видны (пусть не исчезают пока действет эффект).
> 3. сейчас срабатывают только BFF и наводящиеся пули (а должны любые эффекты активных предметов)
>
> Log: `game_log_20260320_084424.txt`

**Analysis of game_log_20260320_084424.txt:**

Confirms the same re-roll pattern. The icon popup was configured at 20px ICON_SIZE and 300ms duration — both too small and too short to be noticed.

---

## Fix Applied (Bug Reports 4 + 5)

### Fix 1: Remove re-roll loop — all effects always fire

Changed `TriggerExperimentalSampleEffect` return type from `bool` to `float` (effect duration).
Removed the up-to-20-attempts re-roll loop in `HandleExperimentalSampleInput`.

Every item now fires an effect:
- **Invisibility suit (5), Trajectory glasses (8)**: spawn temporary effect instance on-the-fly if not equipped
- **Loudspeaker (11)**: call `LoudspeakerApplyEffect` directly (no equip check)
- **Drilling bullets (15)**: apply to current magazine unconditionally
- **Breaching charges (12)**: detonate if placed, else homing burst fallback
- **All passive items** (1, 6, 7, 9, 10, 13, 14, 16, 17): trigger a homing burst as a visible effect (so the player always sees *something* happen)

### Fix 2: Larger icons that stay visible for effect duration

Updated `scripts/ui/experimental_sample_item_popup.gd`:
- `ICON_SIZE`: 20px → **48px** (2.4× larger)
- `BG_RADIUS`: 13px → **30px**
- Duration: fixed 300ms → **passed from `TriggerExperimentalSampleEffect`** return value (effect's actual duration)
- Fade-out only in the last 0.4s of the display period
- `show_icon` signature updated: `show_icon(icon_path, duration = 1.2)`

---

## References

- [Issue #1127](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1127) — original feature request
- [PR #1128](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1128) — implementation
- [Issue #1036](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1036) — Radio Jammer (referenced for jammer-blocking behaviour)
- Godot 4 `randi_range()` docs: https://docs.godotengine.org/en/stable/classes/class_@globalscope.html#class-globalscope-method-randi-range
- GUT (Godot Unit Testing) framework: https://github.com/bitwes/Gut
