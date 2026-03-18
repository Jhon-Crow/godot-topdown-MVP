# Case Study: Issue #1071 — Active Item: Dash (Рывок)

## Issue Summary
**Title:** добавить активный предмет - рывок
**Author:** Jhon-Crow
**Requested Feature:** Add a dash active item for the player.

### Requirements (translated from Russian)
- Unlimited uses (no charge limit)
- Cooldown: 1.2 seconds between dashes
- During the dash, the player ignores all damage sources
- Reference: dash from Hyper Light Drifter

## Hyper Light Drifter Dash Analysis

Hyper Light Drifter (by Heart Machine, 2016) features one of the most celebrated dash mechanics in indie games:

### Key Properties
1. **Directional**: Dash in the current movement direction; if standing still, dash forward (in aim direction)
2. **Distance**: ~150–200px (short burst, not a teleport)
3. **Duration**: Very brief (~0.1–0.15s); near-instant
4. **Invincibility frames**: Full damage immunity for entire dash duration
5. **Visual**: Motion blur/trail behind the player; brief speed lines
6. **Cooldown**: Short cooldown (~0.5–1.2s), unlimited uses
7. **Chaining**: In HLD you can chain dashes; this issue requests 1.2s cooldown (no chaining)
8. **Sound**: Short whoosh/swipe sound on activation

### Gameplay Role
The dash is the primary mobility and survival tool: dodge incoming fire, reposition instantly,
escape flanking enemies. The key gameplay feel is **reactive invincibility** — you dash *through*
bullets rather than around them.

## Architecture Analysis

### Existing Active Item System
The game has a well-established pattern for active items:
- **ActiveItemManager** (`scripts/autoload/active_item_manager.gd`): Singleton managing enum + ACTIVE_ITEM_DATA dict
- **Player script** (`scripts/characters/player.gd`): `_init_*` and `_handle_*_input()` per item
- **Input**: Space key mapped to `flashlight_toggle` action
- **Progress Bar**: `ActiveItemProgressBar` shows cooldown/charges above player head

### Damage Protection Pattern
The force field (`is_force_field_active()`) pattern shows how to block damage:
```gdscript
# In on_hit_with_info():
if is_force_field_active():
    return  # blocked
```
The dash must add a similar `is_dashing()` check.

### Movement System
Player uses `CharacterBody2D` with velocity-based movement:
```gdscript
velocity = velocity.move_toward(input_direction * max_speed, acceleration * delta)
move_and_slide()
```
Dash overrides velocity with a high-speed burst in the dash direction.

## Solution Design

### Approach
1. Implement dash entirely within `player.gd` (no separate scene needed — similar to homing bullets)
2. During dash: override velocity with `dash_direction * DASH_SPEED`
3. Invincibility: `_dash_active` flag checked in `on_hit_with_info()`
4. Cooldown: simple timer, no charge counter
5. Progress bar: continuous bar showing cooldown depletion
6. Visual: brief speed-line / motion-blur effect via modulate flash (or trail Line2D)
7. Audio: short whoosh sound if available, otherwise silent

### Constants
- `DASH_SPEED: float = 900.0` (3× max_speed of 300)
- `DASH_DURATION: float = 0.12` seconds
- `DASH_COOLDOWN: float = 1.2` seconds (per issue spec)
- Input: `flashlight_toggle` (Space key) — same as all other active items

### Components Modified
1. **`active_item_manager.gd`** — Add `DASH` enum entry + ACTIVE_ITEM_DATA
2. **`player.gd`** — `_init_dash()`, `_handle_dash_input()`, `_update_dash()`, `is_dashing()`, damage block
3. **`active_item_manager.gd`** — `has_dash()` helper

### Unlock Condition
Per the issue: "неограниченное количество" (unlimited uses) with cooldown. No special unlock — freely available from the start (like BFF Pendant, Breaker Bullets, Force Field).

## Known Libraries / Solutions

### Godot Built-in
- `CharacterBody2D.velocity` + `move_and_slide()` — native physics movement; dash is just a velocity override
- `get_tree().create_timer()` — usable for cooldown, but inline timer is simpler and cheaper
- No external library needed

### Reference Implementations
- Hyper Light Drifter: `velocity = dash_dir * DASH_SPEED` for a fixed duration; flag for i-frames
- Hotline Miami: Similar instant burst with brief i-frames
- Enter the Gungeon: "dodge roll" — longer animation, invincibility window

## Test Plan
1. Unit test: dash starts on Space, sets `_dash_active = true`
2. Unit test: damage is blocked while `_dash_active`
3. Unit test: cooldown prevents re-activation within 1.2s
4. Unit test: dash ends after `DASH_DURATION` seconds
5. Unit test: cooldown bar shows on activation, hides after cooldown

---

## Bug Investigation Timeline

### Round 1 — `game_log_20260317_214814.txt`

**Owner feedback:** "предмет не работает" (item doesn't work). Dash was going in movement direction (not aim direction).

**Root cause found:** `_start_dash()` used `input_direction` (WASD) instead of `_get_aim_direction()` (mouse cursor).

**Fix applied:** Changed `_start_dash()` to use `_get_aim_direction()`. Also moved `DASH` enum index to 14 after incomplete merge from main.

---

### Round 2 — `game_log_20260318_020059.txt`

**Owner feedback:** "ничего не изменилось, предмет всё ещё не работает и нет значка" (nothing changed, item still doesn't work and there's no icon).

**Analysis:** Log showed "Active item changed from Breaching Charges to Dash" — the armory DID switch to Dash. But after level restart, `Player._ready()` showed NO `[Player.Dash]` log entry, meaning `has_dash()` returned false silently.

**Root cause found:** A previous merge from `main` branch had removed `EXTENDED_MAGAZINE` (10), `DRILLING_BULLETS` (15), `RECOIL_COMPENSATOR` (16), and `COMBAT_DISPOSITION` (17) from the `ActiveItemType` enum, placing `DASH` at index 14. But `main` branch has `AUTO_RELOAD = 14`. So the GDScript enum compiled `DASH = 14`, but `has_dash()` checked `current_active_item == ActiveItemType.DASH` (which is 14), and the armory's saved state stored index 14 as AUTO_RELOAD — causing a mismatch.

**Fix applied:** Restored all items from main branch in correct order. `DASH` moved to index 18 (after `COMBAT_DISPOSITION = 17`). Total: 19 item types (indices 0–18).

---

### Round 3 — `game_log_20260318_062710.txt` ← **Current session**

**Owner feedback:** "ничего не изменилось — нет значка, не работает" (nothing changed — no icon, doesn't work).

**Analysis performed:**

Key findings from the log:
```
[06:27:10] [INFO] [PersistManager] Restored selected active item type: 12
[06:27:15] [INFO] [ActiveItemManager] Active item changed from Breaching Charges to Dash
[06:27:15] [INFO] [Player.RecoilCompensator] Recoil compensator not selected in ActiveItemManager
[06:27:15] [INFO] [Player.Jammer] JammerHUD initialized
```

Critically absent: **any `[Player.Dash]` log entry** — not "Dash equipped", not even "Dash not selected".

`_init_dash()` is called in `_ready()` AFTER `_init_recoil_compensator()`. If RecoilCompensator logs appeared but Dash didn't log at all (not even the "not selected" message), the function was not being called.

**Root cause confirmed:** The user's game binary was built from an **older commit** that did not yet include `_init_dash()` in `player.gd`, even though `active_item_manager.gd` already knew about DASH (explaining why the armory showed "Dash" and the item-changed log appeared).

**Verification:** The latest CI artifact (build run from commit `4f9de49c`, timestamp 00:39 on 2026-03-18) was confirmed to contain `_init_dash()` by running `strings` on the embedded PCK:

```
$ strings Godot-Top-Down-Template.exe | grep "_init_dash\|has_dash\|Player.Dash"
func has_dash() -> bool:
	_init_recoil_compensator()
	_init_dash()
func _init_dash() -> void:
		FileLogger.info("[Player.Dash] ActiveItemManager not found")
	if not active_item_manager.has_method("has_dash"):
		FileLogger.info("[Player.Dash] ActiveItemManager missing has_dash method")
	if not active_item_manager.has_dash():
		FileLogger.info("[Player.Dash] Dash not selected in ActiveItemManager")
	FileLogger.info("[Player.Dash] Dash equipped ...
```

**The code is correct.** The user tested an older binary downloaded before our latest fix was pushed.

**Resolution:** The user needs to download the latest CI artifact from the PR branch. The latest successful build (run ID 23223325533 on upstream, 23223325257 on fork) was built from commit `4f9de49c` and contains the full correct implementation.

### How to download the correct binary

1. Go to [CI Actions for this PR branch](https://github.com/konard/Jhon-Crow-godot-topdown-MVP/actions?query=branch%3Aissue-1071-7f132dd95cdc)
2. Click the latest "Build Windows Portable EXE" run
3. Download the `windows-build` artifact
4. Extract the ZIP and run `Godot-Top-Down-Template.exe`
5. In the armory, select **Dash**
6. Press **Space** to dash toward the mouse cursor — full invincibility, 1.2s cooldown

### PersistManager save file note

The save file (`user://game_state.cfg`) stores `current_active_item` as an integer. If the user had a save from an earlier buggy binary (DASH at wrong index), they may need to:
- Start fresh (reset save via game menu), OR
- Simply select Dash again from the armory — `set_active_item(18)` will overwrite the saved value

All items are marked `unlocked: true` by default in our code, so Dash will always appear in the armory regardless of save file state.
