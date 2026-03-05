# Case Study: Issue #910 — Enemies Don't React to Invisible Player's Sound or Muzzle Flash

## Issue Summary

**Issue Number:** #910 (tracking issue #911)
**Title:** Enemies should shoot toward invisible player's sound source and muzzle flash
**Status:** Implemented (iteration 4 — addressing root causes from 2026-02-28 feedback)
**Author:** Jhon-Crow
**Original Language:** Russian

### Original Description (Russian)
> когда игрок в Невидимости (активен предмет Невидимость) враги должны стрелять примерно в источник звука (веером) или по вспышке от ствола.

### Translation
> When the player is Invisible (Invisibility item is active), enemies should shoot approximately at the sound source (in a fan pattern) or at the muzzle flash.

---

## Owner Feedback History

### Comment 1 — 2026-02-24 (game_log_20260225_021948.txt)
**Russian:** враги не стреляют по вспышкам игрока (невидимого) даже когда он в их поле зрения и очень близко.
**Translation:** Enemies do not shoot at the player's muzzle flashes (invisible) even when the player is in their field of view and very close.

### Comment 2 — 2026-02-28 (game_log_20260301_014039.txt) — LATEST
**Russian:**
1. не работает
2. когда на врага попадает вспышка — он должен переходить в боевое состояние
3. когда игрок невидим враги должны стрелять на каждый звук, изданный игроком

**Translation:**
1. Does not work
2. When a muzzle flash hits an enemy — they should transition to COMBAT state
3. When the player is invisible, enemies should shoot at every sound made by the player

---

## Game Log Evidence (game_log_20260301_014039.txt)

### Key Finding: Zero Issue #910 Log Entries
A grep search for `#910`, `suppressive`, `invisible`, `MuzzleFlash`, and `flash_detect` across the entire 6,664-line log returned **0 matches**. This confirms that:
- The suppressive fire system (`SuppressiveFireComponent`) was never triggered
- The muzzle flash detection system (`MuzzleFlashDetectionComponent`) was never triggered
- No enemy shot at the invisible player during the entire session

### Incident Reconstruction: First Encounter (01:40:48)

```
[01:40:48] SoundProp: GUNSHOT at (488.53, 728.07), source=PLAYER (AKGL), range=1600
[01:40:48] Sound result: notified=4, out_of_range=1, self=0, below_threshold=5
```
- 4 enemies notified of player gunshot
- All 4 transitioned: IDLE → COMBAT
- No #910 suppressive fire log entries
- Enemies immediately retreated: COMBAT → RETREATING → IN_COVER / PURSUING

### Incident Reconstruction: Main Encounter (01:40:58)

```
[01:40:58] SoundProp: GUNSHOT at (450, 951.67), source=PLAYER (AKGL), range=1600
[01:40:58] Sound result: notified=3, out_of_range=1, self=0, below_threshold=6

[01:40:58] Enemy2: IDLE → COMBAT
[01:40:58] Enemy3: IDLE → COMBAT
[01:40:58] Enemy4: IDLE → COMBAT
[01:40:58] Enemy4: COMBAT → RETREATING → IN_COVER → SUPPRESSED
[01:40:58] Enemy3: COMBAT → RETREATING
[01:40:58] Enemy1: IDLE → COMBAT (after hearing Enemy2's gunshot sound)
```
**Critical observation:** All enemies entered COMBAT, then immediately retreated to cover — **no suppressive shots fired** at the invisible player's known position.

### Incident Reconstruction: Second Wave (01:41:02)

```
[01:41:02] SoundProp: GUNSHOT at (514.48, 723.15), source=PLAYER (AKGL), range=1600
[01:41:02] Sound result: notified=4, out_of_range=1, self=0, below_threshold=5
[01:41:02] Enemy1: IDLE → COMBAT
[01:41:02] Enemy2: IDLE → COMBAT
[01:41:02] Enemy3: IDLE → COMBAT → RETREATING
[01:41:02] Enemy4: IDLE → COMBAT
[01:41:03] Enemy1: COMBAT → PURSUING
[01:41:03] Enemy2: COMBAT → PURSUING
[01:41:03] Enemy4: COMBAT → PURSUING
```
**Pattern repeated:** COMBAT → PURSUING transition without any suppressive fire.

---

## Root Cause Analysis

### Root Cause 1: Suppressive Fire NOT Called in COMBAT State (Bug — "Does not work")

The owner says the feature "does not work." Examination of `scripts/objects/enemy.gd` reveals:

**Location:** `_process_combat_state()` — line 1350

```gdscript
# Current code (PARTIAL fix — wrong placement):
if not _can_see_player:
    if _combat_state_timer >= COMBAT_MIN_DURATION_BEFORE_PURSUE:  # 0.5s
        _transition_to_pursuing()
        return
    if _suppressive_fire:
        _suppressive_fire.try_suppress_pursuing(...)  # ← Called ONLY during 0.5s wait
```

**The problem:** `try_suppress_pursuing` has this guard:
```gdscript
func try_suppress_pursuing(can_see: bool, ...) -> bool:
    if can_see or is_melee: return false
    if not player or not player.has_method("is_invisible") or not player.is_invisible(): return false
```

So it checks `player.is_invisible()`. If the player activated invisibility and enemies were already in some non-IDLE state, or if the timing doesn't line up, the check fails silently.

**But the deeper problem from the log:** Enemies go IDLE → COMBAT immediately when they hear gunshots. The COMBAT state calls `try_suppress_pursuing` for only `COMBAT_MIN_DURATION_BEFORE_PURSUE = 0.5s`, then transitions to PURSUING. But PURSUING also calls suppressive fire, which should work... except:

**The actual culprit:** Looking at the log again — enemies go IDLE → COMBAT but the player was NOT invisible at the start (no `InvisibilitySuit` activation log entry found in the session). The player was shooting while **visible**, then perhaps activated invisibility mid-combat. When the player is visible, `try_suppress_pursuing` returns false immediately because `is_invisible()` is false. Then if the player activates invisibility, the enemies are already in non-IDLE states (PURSUING, RETREATING, IN_COVER) and the code paths do call suppressive fire — but it still doesn't fire because:

**Root finding from `try_suppress_pursuing`:**
```gdscript
var target_pos := _muzzle_flash_detection.estimated_player_position if
    (_muzzle_flash_detection and _muzzle_flash_detection.detected) else last_pos
if target_pos == Vector2.ZERO or ...: return false
```

If `_last_known_player_position` is `Vector2.ZERO` (never updated from sound when invisible), no shot is fired. But the log shows `_last_known_player_position` IS updated by GUNSHOT sound handler:
```gdscript
# on_sound_heard_with_intensity line 690
_last_known_player_position = position
```

**Definitive Root Cause 1:** `try_suppress_pursuing` requires `player.is_invisible() == true`. The player must be invisible at the exact moment the check runs. The 0.5s COMBAT window and subsequent PURSUING re-check may miss the invisibility window if:
- The player only briefly activates invisibility and it expires before the enemy reaches PURSUING state
- Enemies in COMBAT with `_can_see_player == true` never get to the suppressive fire path

### Root Cause 2: Muzzle Flash Does NOT Trigger COMBAT State Transition (Missing Feature)

Owner request #2: "When a muzzle flash hits an enemy — they should transition to COMBAT state."

**Current behavior in `SuppressiveFireComponent._physics_process()`:**
```gdscript
if _muzzle_flash_detection.check_muzzle_flash(...):
    _enemy._last_known_player_position = ...
    if _enemy._current_state == 0:  # AIState.IDLE = 0
        _enemy._transition_to_pursuing()  # ← Transitions to PURSUING, NOT COMBAT
```

**The bug:** When a muzzle flash is detected, the code transitions from IDLE → PURSUING. The owner wants IDLE → **COMBAT** (so the enemy immediately starts shooting back).

Additionally, the `_physics_process` guard:
```gdscript
if _enemy._can_see_player or _enemy._is_blinded or _enemy._memory_reset_confusion_timer > 0.0:
    _muzzle_flash_detection.reset(); return
```

This resets the detection when `_memory_reset_confusion_timer > 0.0`. Since activating invisibility triggers `memory_reset_confusion_timer = 2.0s` for all enemies (confirmed from first log), the detection is suppressed for 2 seconds after the player goes invisible. This is a critical timing issue.

**Also:** `_track_muzzle_flash` in `ImpactEffectsManager` tracks ALL muzzle flashes (player AND enemy). The `MuzzleFlashDetectionComponent` does not filter by source — it will detect enemy muzzle flashes as "player flashes." This is a correctness bug (though enemies are unlikely to be near each other's flash positions).

### Root Cause 3: Enemies Don't Shoot at EVERY Sound When Player Is Invisible (Missing Feature)

Owner request #3: "When the player is invisible, enemies should shoot at every sound made by the player."

**Current behavior:** Only `GUNSHOT` (type 0) and `EXPLOSION` (type 1) trigger `_transition_to_combat()`. The reaction guards:
```gdscript
var should_react := false
if _current_state == AIState.IDLE:
    should_react = intensity >= 0.01
elif _current_state in [AIState.FLANKING, AIState.RETREATING]:
    should_react = intensity >= 0.3
if not should_react: return
```

Enemies in COMBAT, PURSUING, IN_COVER, SEARCHING, SUPPRESSED do NOT call suppressive fire when they hear a gunshot (only the existing path in their `_process_*` methods does). The `on_sound_heard_with_intensity` handler calls `_transition_to_combat()` unconditionally at line 695 — but if the enemy is already in COMBAT/PURSUING/IN_COVER, this just re-enters the same state.

**What the owner wants:** When the player is invisible AND makes any sound (gunshot, footstep, reload, casing kick), the nearby enemies should fire suppressive shots immediately at that sound position — regardless of their current state.

---

## Sequence of Events (Reconstructed)

```
01:40:48  Player fires (not yet invisible or brief invisibility expired)
          ↓ SoundProp: GUNSHOT → 4 enemies notified
          ↓ Enemies: IDLE → COMBAT
          ↓ _process_combat_state: _can_see_player check fails (player invisible?)
          ↓ try_suppress_pursuing called but: player.is_invisible() = false (timing) OR
            _memory_reset_confusion_timer > 0 blocks the detection
          ↓ 0.5s elapses → COMBAT → PURSUING
          ↓ try_suppress_pursuing called in PURSUING: same conditions, no shot

01:40:58  Player fires again at (450, 951)
          ↓ Same pattern repeats
          ↓ Enemy4: COMBAT → RETREATING → IN_COVER → SUPPRESSED
          ↓ try_suppress_cover called: player.is_invisible() check at wrong moment
          ↓ NO suppressive shots fired at any point
          
01:41:02  Player fires at (514, 723) — 4 enemies notified
          ↓ All IDLE → COMBAT → PURSUING
          ↓ Zero #910 log entries = zero suppressive shots in entire session
```

---

## Proposed Solutions

### Fix 1: Call Suppressive Fire in COMBAT State and on Every Sound

**In `_process_combat_state()` — always try suppressive fire when player not visible:**
```gdscript
if not _can_see_player:
    # Always attempt suppressive fire toward last known position
    if _suppressive_fire:
        _suppressive_fire.try_suppress_pursuing(
            _can_see_player, _last_known_player_position,
            _is_melee_weapon, _player, _is_reloading, _shoot_timer, shoot_cooldown
        )
    if _combat_state_timer >= COMBAT_MIN_DURATION_BEFORE_PURSUE:
        _transition_to_pursuing()
        return
```

**In `on_sound_heard_with_intensity()` — add suppressive fire response for invisible player:**
```gdscript
# After updating _last_known_player_position from gunshot:
if sound_type == 0 and source_type == 0:  # GUNSHOT from PLAYER
    _last_known_player_position = position
    # If player is invisible, immediately fire suppressive shots
    if _player and _player.has_method("is_invisible") and _player.is_invisible():
        if _suppressive_fire:
            _suppressive_fire.shoot(position)
```

### Fix 2: Muzzle Flash Detection Transitions to COMBAT (Not PURSUING)

**In `SuppressiveFireComponent._physics_process()`:**
```gdscript
if _muzzle_flash_detection.check_muzzle_flash(...):
    _enemy._last_known_player_position = _muzzle_flash_detection.estimated_player_position
    _enemy._log_to_file("[#910] Muzzle flash detected: est_pos=%s" % ...)
    # CHANGE: transition to COMBAT (shoot back), not PURSUING (move toward)
    if _enemy._current_state == AIState.IDLE:
        _enemy._log_to_file("[#910] Muzzle flash triggered COMBAT from IDLE")
        _enemy._transition_to_combat()  # ← Was: _transition_to_pursuing()
    # Also shoot immediately in non-idle states
    elif _enemy._current_state in [AIState.PURSUING, AIState.IN_COVER, AIState.RETREATING]:
        _suppressive_fire.shoot(_muzzle_flash_detection.estimated_player_position)
```

### Fix 3: Remove `_memory_reset_confusion_timer` Guard for Muzzle Flash

The confusion timer guard prevents muzzle flash detection for 2 seconds after invisibility activates. This is counterproductive — a muzzle flash is VISIBLE and should override confusion:

```gdscript
func _physics_process(delta: float) -> void:
    if _enemy == null or _muzzle_flash_detection == null or _enemy._player == null:
        return
    # CHANGE: Remove _memory_reset_confusion_timer guard for muzzle flash
    # Flash is a visual event - confusion doesn't prevent seeing a bright light
    if _enemy._can_see_player or _enemy._is_blinded:  # Keep only blind guard
        _muzzle_flash_detection.reset(); return
```

### Fix 4: Filter Enemy Muzzle Flashes in ImpactEffectsManager

The flash tracking system records all flashes (player AND enemy). Enemies checking for "player muzzle flash" may detect their own allies' flashes:

**In `ImpactEffectsManager._track_muzzle_flash()`:**
```gdscript
func _track_muzzle_flash(position: Vector2, direction: Vector2, source: Node2D = null) -> void:
    var flash_data := {
        "position": position,
        "direction": direction.normalized(),
        "timestamp": Time.get_ticks_msec() / 1000.0,
        "source": source  # Add source tracking
    }
    _active_muzzle_flashes.append(flash_data)
```

And filter in `get_active_muzzle_flashes()` to return only player-sourced flashes.

### Fix 5: Shoot at Every Sound When Player Is Invisible

Add to `on_sound_heard_with_intensity()` to handle all sound types:
```gdscript
# After all specific sound type handlers, before the GUNSHOT/EXPLOSION handler:
# If player is invisible, fire suppressive shot at ANY sound from player
if source_type == 0 and _player and _player.has_method("is_invisible") and _player.is_invisible():
    if _suppressive_fire and not _is_reloading:
        _suppressive_fire.shoot(position)
    _last_known_player_position = position
    if _memory: _memory.update_position(position, SOUND_GUNSHOT_CONFIDENCE)
```

---

## Implementation (Iteration 3 — 2026-02-28)

All three owner requirements have been implemented:

| Fix | Requirement | File | Change |
|-----|-------------|------|--------|
| Muzzle flash → COMBAT (not PURSUING) | Req #2 | `suppressive_fire_component.gd` | `_transition_to_pursuing()` → `_transition_to_combat()` + immediate shoot |
| Remove confusion timer guard for flash | Req #1/#2 | `suppressive_fire_component.gd` | Removed `_memory_reset_confusion_timer > 0.0` from detection block |
| Fire on RELOAD sound (invisible) | Req #3 | `enemy.gd` | `_suppressive_fire.shoot(position)` after RELOAD handler |
| Fire on EMPTY_CLICK sound (invisible) | Req #3 | `enemy.gd` | `_suppressive_fire.shoot(position)` after EMPTY_CLICK handler |
| Fire on CASING_KICK sound (invisible) | Req #3 | `enemy.gd` | `_suppressive_fire.shoot(position)` after CASING_KICK handler |
| Fire on GUNSHOT sound (invisible) | Req #3 | `enemy.gd` | `_suppressive_fire.shoot(position)` after GUNSHOT handler |
| Shoot cooldown in `shoot()` | Correctness | `suppressive_fire_component.gd` | Added `_shoot_timer < shoot_cooldown` guard + reset |

## Implementation Priority (Historical)

| Priority | Fix | Owner Requirement | Effort |
|----------|-----|-------------------|--------|
| P1 | Fix 2: Muzzle flash → COMBAT transition | Req #2 | Low (1 line change) |
| P1 | Fix 3: Remove confusion timer guard for flash | Req #1 (#2 depends on it) | Low (1 line change) |
| P2 | Fix 5: Shoot at every player sound | Req #3 | Medium |
| P2 | Fix 1: Suppressive fire in COMBAT state | Req #1 (not working) | Low |
| P3 | Fix 4: Filter enemy flashes from tracking | Correctness | Medium |

---

## Files to Modify

1. `scripts/components/suppressive_fire_component.gd`
   - `_physics_process()`: Remove confusion timer guard, change IDLE→PURSUING to IDLE→COMBAT
   - `_physics_process()`: Add immediate shoot in non-idle states on flash detection

2. `scripts/objects/enemy.gd`
   - `on_sound_heard_with_intensity()`: Add suppressive fire call when player is invisible for ANY sound type
   - `_process_combat_state()`: Ensure suppressive fire is attempted every frame (not just in 0.5s window)

3. `scripts/autoload/impact_effects_manager.gd`
   - `spawn_muzzle_flash()`: Accept `source` parameter
   - `_track_muzzle_flash()`: Store source
   - `get_active_muzzle_flashes()`: Filter by player source (optional — low priority)

---

## Related Issues and Components

- **Issue #673**: Invisibility suit implementation — defines `is_invisible()` method and memory reset
- **Issue #574**: `FlashlightDetectionComponent` — same pattern as MuzzleFlashDetectionComponent
- **Issue #297**: `EnemyMemory` — confidence system used for position updates
- **Issue #322**: SEARCHING state — what enemies should do after losing invisible player
- **Issue #805**: GUNSHOT/EXPLOSION sound handling in `on_sound_heard_with_intensity`
- **Issue #693**: CASING_KICK sound — should also trigger suppressive fire when player invisible

## Game Log Files

- `game_log_20260225_021948.txt` — Initial report, shows muzzle flash not working (pre-PR#911)
- `game_log_20260301_014039.txt` — Second report (2026-03-01), shows 3 bugs post-iteration 2
- `game_log_20260301_023611.txt` — Third report (2026-03-01), shows sounds blocked by confusion timer
- `game_log_20260301_023900.txt` — Fourth report (2026-03-01), shows enemy not reacting to hits

---

## Iteration 4 Analysis (2026-03-05)

### Owner Feedback (2026-02-28 23:42:19)

**Russian:**
1. после попадания в противника противник остаётся в том же состоянии - это не правильно (сейчас игрок из невидимости стреляет в idle или searching врага безнаказанно)
2. стрельба по игроку в невидимости либо срабатывает редко, либо не работает

**Translation:**
1. After hitting an enemy, the enemy stays in the same state - this is wrong (currently the player shoots from invisibility at idle or searching enemies without punishment)
2. Shooting at the invisible player either works rarely or doesn't work

### Root Cause Analysis from Logs (game_log_20260301_023900.txt)

#### Root Cause A: Enemy Doesn't React to Being Hit by Invisible Player

**Evidence from log:**
```
[02:39:20] [INFO] [Player] Reset memory for 10 enemies (invisibility activation - Issue #723)
[02:39:20] [ENEMY] [Enemy3] Hit: dmg=1, hp=4/4->3/4
[02:39:20] [ENEMY] [Enemy3] Hit: dmg=1, hp=3/4->2/4
[02:39:20] [ENEMY] [Enemy3] Hit: dmg=1, hp=2/4->1/4
[02:39:20] [ENEMY] [Enemy3] Hit: dmg=1, hp=1/4->0/4
```

Enemy3 is hit 4 times and killed while staying in IDLE state — NO state transition to COMBAT!

**Code analysis (`enemy.gd` line 4169-4177):**
```gdscript
else:
    # Play non-lethal hit sound
    if audio_manager and audio_manager.has_method("play_hit_non_lethal"):
        audio_manager.play_hit_non_lethal(global_position)
    # Spawn blood effect for non-lethal hit (smaller, no decal)
    if impact_manager and impact_manager.has_method("spawn_blood_effect"):
        impact_manager.spawn_blood_effect(global_position, hit_direction, caliber_data, false)
    _update_health_visual()
    if _aggression: _aggression.check_retaliation(hit_direction)  # [Issue #675] retaliate
```

**The bug:** `on_hit_with_bullet_info()` has NO state transition code. The only response is:
1. Face toward attacker direction
2. Visual/audio feedback
3. `check_retaliation()` — which only handles **aggression gas (enemy vs enemy)**, NOT player attacks

**Fix:** Added state transition to COMBAT when hit in non-combat states + fire suppressive shot back.

#### Root Cause B: Confusion Timer Blocks ALL Player Sounds

**Evidence from log (game_log_20260301_023611.txt):**
```
[02:36:19] [INFO] [Player] Reset memory for 10 enemies (invisibility activation - Issue #723)
[02:36:20] [INFO] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(553.80, 714.39), source=PLAYER (AssaultRifle), range=1469, listeners=20
[02:36:20] [INFO] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(578.46, 709.92), source=PLAYER (AssaultRifle), range=1469, listeners=10
```

20 potential listeners, but NO "Heard gunshot" log entries and NO "[#910] Suppressive" entries!

**Code analysis (`enemy.gd` line 551):**
```gdscript
if not _is_alive or _memory_reset_confusion_timer > 0.0:
    return  # BLOCKS ALL SOUNDS!
```

The `_memory_reset_confusion_timer` is set to 2.0 seconds when invisibility activates (line 3737). This blocks the ENTIRE `on_sound_heard_with_intensity()` function for 2 seconds — exactly when the player is shooting.

**Fix:** Modified to allow player gunshot sounds during confusion (for suppressive fire).

#### Root Cause C: Enemies in SEARCHING State Don't React to Gunshots

**Code analysis (`enemy.gd` lines 676-683):**
```gdscript
var should_react := false
if _current_state == AIState.IDLE:
    should_react = intensity >= 0.01
elif _current_state in [AIState.FLANKING, AIState.RETREATING]:
    should_react = intensity >= 0.3
if not should_react:
    return
```

Enemies in SEARCHING state (where they go after invisibility resets their memory) have `should_react = false` and return early, never reaching the suppressive fire call.

**Fix:** Added SEARCHING/PURSUING/IN_COVER/COMBAT states to the reaction conditions for player gunshots.

### Implementation (Iteration 4)

| Fix | Requirement | File | Change |
|-----|-------------|------|--------|
| Hit triggers COMBAT + suppressive fire | Req #1 | `enemy.gd:4177` | Added state transition and suppressive fire when hit |
| Allow gunshots during confusion | Req #2 | `enemy.gd:551` | Modified guard to allow player gunshots |
| Searching/etc states react to gunshots | Req #2 | `enemy.gd:678` | Added more states to `should_react` check |
| Clear confusion timer when hit | Correctness | `enemy.gd:4185` | Reset timer on hit ("wake-up call") |
