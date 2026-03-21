# Case Study: Issue #1259 — BuildingLevel: Player Death & Ammo Counter Broken

**Date:** 2026-03-21
**Reporter:** Jhon-Crow
**Branch/PR:** `issue-1259-9a7159f5f5ed` / PR #1260
**Severity:** High — core gameplay loop (death, ammo UI) non-functional on one map

---

## 1. Problem Description

Two bugs specific to the **Building** map (`BuildingLevel`):

1. **Player cannot die** — the "YOU DIED" text never appears; the scene restarts without any death screen.
2. **Ammo counter is broken** — the ammo label does not update when the player switches weapons or when `_apply_building_ammo_config` reinitialises magazine count.

Both bugs were absent from all other levels (TestTier, CityLevel, DocksLevel, FactoryLevel, RevolverLevel).

---

## 2. Evidence from Game Log (`game_log_20260321_081722.txt`)

**Key log observations:**

| Time | Event | Significance |
|------|-------|--------------|
| 08:17:23 | `[SceneLoader] ERROR: Invalid resource: res://scenes/levels/BuildingLevel.tscn` | First attempt to load BuildingLevel failed entirely |
| 08:22:00 | BuildingLevel finally loads | No lines from `building_level.gd` (e.g. signal connection messages) |
| 08:22:26 | `[CinemaEffects] Player died` | Player death confirmed at engine level |
| 08:22:26 | `[PenultimateHit] Player died`, `[LastChance] Player died` | C# effects received `Died` signal |
| 08:22:28 | `[CinemaEffects] Scene changed to: BuildingLevel` | Scene restarted ~2s after death |
| *(never)* | No "YOU DIED" label, no `building_level.gd` death handler log | GDScript handler never fired |

**Pattern across all BuildingLevel deaths in the log:**
- CinemaEffects, PenultimateHit, LastChance all fire their `Died` handlers (C# components connected to `Died`)
- `building_level.gd`'s `_on_player_died()` never fires (no corresponding log output)
- Scene restarts via `GameManager.on_player_death()` called from C# effects — no "YOU DIED" screen

---

## 3. Root Cause Analysis

### Root Cause 1: Missing `LevelInitFallback` in `BuildingLevel.tscn`

All other levels include a `LevelInitFallback` C# node that:
- Acts as a safety net if GDScript tokenization fails (Godot 4.3 binary tokenization bug — [godotengine/godot#94150](https://github.com/godotengine/godot/issues/94150))
- Connects to the player `Died` signal in C# to show "YOU DIED" and restart
- Connects weapon `AmmoChanged` signal to update ammo UI

`BuildingLevel.tscn` was missing this node entirely. When `building_level.gd` failed to load (as seen at 08:17:23 in the log), there was no fallback — the death signal was never connected at the GDScript level, and there was no C# fallback either.

Evidence: `[SceneLoader] ERROR: Invalid resource: res://scenes/levels/BuildingLevel.tscn` (line 254 of log). Even when the scene loaded successfully later, the GDScript produced no log output indicating it was running.

### Root Cause 2: Ordering Bug in `_setup_player_tracking()` in `building_level.gd`

In the GDScript level script, `_ammo_label` was initialised **after** `_setup_selected_weapon()` was called:

```gdscript
# BUGGY ORDER (before fix):
func _setup_player_tracking() -> void:
    _player = get_node_or_null("Entities/Player")
    if _player == null:
        return
    _setup_realistic_visibility()
    _setup_selected_weapon()           # ← calls _apply_building_ammo_config()
    if GameManager:
        GameManager.set_player(_player)
    _ammo_label = get_node_or_null(...)  # ← too late! already called above
    if _player.has_signal("died"):
        _player.died.connect(_on_player_died)
```

`_apply_building_ammo_config()` calls `_update_ammo_label_magazine()` which has a null-guard:
```gdscript
func _update_ammo_label_magazine(current_mag: int, reserve: int) -> void:
    if _ammo_label == null:
        return   # ← silently returns, initial ammo display is lost
    _ammo_label.text = "AMMO: %d/%d" % [current_mag, reserve]
```

Because `_ammo_label` is `null` at the time `_apply_building_ammo_config` runs, the initial ammo display is silently skipped. The label stays at its scene-default `"AMMO: 30/30"` even after the weapon is swapped or magazine count is reinitialised.

---

## 4. Fix Applied

### Fix 1: Add `LevelInitFallback` to `BuildingLevel.tscn`

Added the node to `scenes/levels/BuildingLevel.tscn`, matching all other levels:

```gdscript
# Added to header:
[ext_resource type="Script" path="res://Scripts/Components/LevelInitFallback.cs" id="5_fallback"]

# Added as last node:
[node name="LevelInitFallback" type="Node" parent="."]
script = ExtResource("5_fallback")
```

Also updated `load_steps` from `28` to `29`.

### Fix 2: Move `_ammo_label` Initialisation Before `_setup_selected_weapon()`

```gdscript
# FIXED ORDER:
func _setup_player_tracking() -> void:
    _player = get_node_or_null("Entities/Player")
    if _player == null:
        return
    # Find the ammo label early so _apply_building_ammo_config can update it (Issue #1259)
    _ammo_label = get_node_or_null("CanvasLayer/UI/AmmoLabel")
    _setup_realistic_visibility()
    _setup_selected_weapon()           # now _ammo_label is valid when called
    ...
```

---

## 5. Tests Added

New unit tests added to `tests/unit/test_level_scripts.gd`:

**Player death tests:**
- `test_building_player_death_shows_death_message` — death triggers "YOU DIED"
- `test_building_player_death_sets_game_over` — `_game_over_shown` is set to prevent duplicate messages
- `test_building_player_death_does_not_show_game_over_message` — only `show_death_message` fires, not `show_game_over_message`
- `test_building_player_second_death_ignored` — second death is a no-op after first

**Ammo counter tests:**
- `test_building_ammo_label_initialized_before_weapon_setup` — label is ready before weapon setup (fixed order)
- `test_building_ammo_label_buggy_order_misses_initial_update` — proves old order caused label to be skipped
- `test_building_ammo_label_update_reflects_magazine_ammo` — label shows correct `AMMO: current/reserve` text
- `test_building_ammo_label_update_empty_magazine` — label shows `AMMO: 0/reserve` when empty
- `test_building_ammo_label_update_fails_when_not_initialized` — null guard works correctly

---

## 6. Timeline of Events (Reconstructed)

```
[Initial] BuildingLevel.tscn created/modified → LevelInitFallback never added (present in all other levels)
[Code]    _setup_player_tracking() written → _ammo_label initialised after _setup_selected_weapon (subtle ordering bug)
[Runtime] Godot 4.3 tokenization bug may prevent GDScript from running → no fallback exists for BuildingLevel
[User]    Player enters BuildingLevel → ammo label shows wrong value → no "YOU DIED" screen on death
[Report]  Issue #1259 filed: "player cannot die, ammo counter broken" on Building map
[Fix]     PR #1260: (1) added LevelInitFallback, (2) fixed ordering bug
```

---

## 7. Related Issues

- [godotengine/godot#94150](https://github.com/godotengine/godot/issues/94150) — GDScript binary tokenization bug in Godot 4.3
- Issue #540 — realistic visibility component setup (same `_setup_player_tracking` function)
- Issue #636 — Makarov PM 2.5x ammo multiplier
- Issue #886 — GrenadeTimer GDScript/C# duplicate handling
- Issue #949 — M16/AK+GL should have 2 magazines on Building level
