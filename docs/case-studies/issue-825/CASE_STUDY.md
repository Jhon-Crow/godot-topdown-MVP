# Case Study: Issue #825 — Enemy Reaction Delay in Night Mode

## Overview

**Issue**: Enemies in night mode (realistic visibility) should turn on their flashlight and orient toward the player, then after a 30% longer delay than in non-night mode, begin shooting.

**Reported Problems** (from PR #889 comment by owner @Jhon-Crow, 2026-02-24):
1. There is currently no or too short a pause between the enemy flashlight turning on and the start of shooting.
2. Enemies sometimes start shooting without turning on their flashlight.

**Evidence**: Game log file `game_log_20260224_200839.txt` (collected 2026-02-24, during Windows gameplay session).

---

## Timeline / Sequence of Events

### Session Context
- **Build**: Non-debug (`Debug build: false`), Engine v4.3-stable
- **OS**: Windows
- **Log file**: `game_log_20260224_200839.txt`

### Night Mode Activation
```
[20:08:39] [ExperimentalSettings] initialized - Realistic visibility: false
[20:08:47] [ExperimentalSettings] Realistic visibility enabled
[20:08:50] [CinemaEffects] Scene changed to: BuildingLevel
```

Night mode (realistic visibility) was enabled at `20:08:47`, **3 seconds** after the game started. Enemies then spawned in `BuildingLevel` with night mode already active.

### First Combat Engagement (Night Mode)
```
[20:08:58] [Enemy3] State: IDLE -> COMBAT
[20:08:58] [Enemy3] ROT_CHANGE: P1:visible -> P2:combat_state
[20:08:59] (Enemy3 fires: "Sound emitted: type=GUNSHOT, source=ENEMY (Enemy3)")
```

Enemy3 enters COMBAT and fires within approximately **1 second** of detecting the player.

### Key Observation from Log Analysis
- **No `[EnemyFlashlight]` log entries** anywhere in the 14,568-line game log.
- This is because `debug_logging = false` is the default for the flashlight component.
- The 50-100ms pre-attack flash duration is imperceptible — shorter than a single animation frame at 60fps.
- The flashlight visually turns on and off too fast for the player to notice.

---

## Root Cause Analysis

### Bug 1: Too-Short Pause Between Flashlight and Shooting

**Root Cause**: `PRE_ATTACK_FLASH_DURATION_MIN = 0.05` and `PRE_ATTACK_FLASH_DURATION_MAX = 0.1` in `EnemyFlashlightComponent`.

The pre-attack flash duration of 50-100ms was designed to be the delay between the flashlight turning on and the enemy shooting. However:
- At 60fps, one frame = ~16.7ms
- 50ms = ~3 frames — visually imperceptible
- 100ms = ~6 frames — barely perceptible

**Evidence from code** (`scripts/components/enemy_flashlight_component.gd:17-18`):
```gdscript
const PRE_ATTACK_FLASH_DURATION_MIN: float = 0.05
const PRE_ATTACK_FLASH_DURATION_MAX: float = 0.1
```

This duration is far too short to serve as a "noticeable pause" that warns the player. The issue description says enemies should "first turn on the flashlight and orient toward the player" before shooting — this orientation behavior requires visible time (at minimum 300-500ms).

**What was intended**: The flashlight should be on long enough for the player to visually notice it and potentially react (dodge, take cover).

**Design context from Issue #824/825**: The flashlight pre-attack behavior is meant to:
1. Give the enemy a more realistic "spotting" behavior in the dark
2. Give the player a fair warning before being shot (flashlight = visual "incoming attack" signal)
3. Simulate the time for an enemy to aim their weapon in the dark after activating a flashlight

### Bug 2: Enemies Sometimes Shoot Without Flashlight

**Root Cause**: Two code paths bypass the flashlight pre-attack sequence:

**Path A — Already Flashing Check** (`enemy_flashlight_component.gd:169-172`):
```gdscript
if _is_flashing_for_attack:
    # Already flashing, don't interrupt
    _log_debug("Already flashing, skipping new flash request")
    return
```
When `_is_flashing_for_attack` is true and `_shoot()` is called again (e.g., fast enemy, short cooldown), the new shot doesn't wait for a flashlight flash — it gets dropped silently. The callback is never queued.

**Path B — Flashlight Scene Load Failure** (`enemy_flashlight_component.gd:160-167`):
```gdscript
if _flashlight_node == null or _point_light == null:
    _setup_flashlight()
    if _flashlight_node == null or _point_light == null:
        # Still not available, execute callback immediately
        if callback.is_valid():
            callback.call()
        return
```
If the flashlight scene file is missing or fails to load, enemies shoot immediately without any flashlight. This silent fallback is invisible in non-debug logs.

**Path C — High-Priority Attacks in `enemy.gd`** (`enemy.gd:1161-1178`, `enemy.gd:1207-1235`):
The "player distracted" priority attack and "player vulnerable" priority attack call `_shoot()` directly without checking if the enemy is in the middle of a pre-attack flash sequence. These priority attacks can fire while `_is_pre_attack_flashing = true` on the main enemy state machine — but since these are different code paths and `_shoot()` checks `_is_pre_attack_flashing` at the START, the flashlight flash state could be inconsistent.

**Path D — No Logging of Failures**: Since `debug_logging = false` by default, all flashlight failures are completely silent. The game log confirms zero `[EnemyFlashlight]` entries, making it impossible to diagnose issues in production builds.

---

## Proposed Solutions

### Fix 1: Increase Pre-Attack Flash Duration

The pre-attack flash duration should be long enough for players to perceive the flashlight and react. Based on game design principles for fair warning systems:

- **Minimum**: 0.3s (300ms) — minimum noticeable duration for a visual cue
- **Maximum**: 0.5s (500ms) — maximum that doesn't feel punishing

This matches the "flashlight orientation" time described in the issue: the enemy needs time to turn on the flashlight AND orient toward the player before shooting.

**Recommended fix** in `enemy_flashlight_component.gd`:
```gdscript
const PRE_ATTACK_FLASH_DURATION_MIN: float = 0.3   # was 0.05
const PRE_ATTACK_FLASH_DURATION_MAX: float = 0.5   # was 0.1
```

### Fix 2: Prevent Shooting Without Flashlight

When night mode is active and the flashlight is available, the enemy should NEVER shoot without the flashlight pre-attack sequence. Fix options:

**Option A**: Block shooting when flashlight is initialized but not flashing yet (make `_is_pre_attack_flashing` a gate).

**Option B**: Queue pending shoot callbacks instead of dropping them.

The simplest and most reliable fix: when `_is_flashing_for_attack` is already true and `_shoot()` is called again, the current approach drops the shot silently. This can be improved by tracking the pending state more carefully.

Additionally, the `_setup_flashlight()` call in `start_pre_attack_flash()` should be more robust — if it fails at night mode start, log it clearly.

---

## Impact Assessment

- **Player experience**: Enemies feel unfair because they shoot before the player can react to the flashlight warning.
- **Design intent**: The flashlight is meant to be a visible "tell" (warning signal) that an enemy is about to shoot.
- **Severity**: Medium — the 30% detection delay (0.78s at Normal difficulty) does add time, but the flashlight visual warning is the key gameplay feedback mechanism.

---

## Related Issues and PRs

- **Issue #824**: Enemy flashlight behavior (parent issue for flashlight component)
- **Issue #825**: This issue — 30% longer reaction delay in night mode
- **PR #889**: Implementation of fix for Issue #825

## References

- Game log: `game_log_20260224_200839.txt` (attached to PR #889 by @Jhon-Crow)
- `scripts/components/enemy_flashlight_component.gd` — Flashlight component implementation
- `scripts/objects/enemy.gd` — Enemy AI with `_shoot()` and `_setup_enemy_flashlight()`
- `scripts/autoload/difficulty_manager.gd` — Detection delay with 30% night mode multiplier
- [Enemy design patterns — The Level Design Book](https://book.leveldesignbook.com/process/combat/enemy)
- [AI + Night + Flashlight — Gray Zone Warfare](https://steamcommunity.com/app/2479810/discussions/0/603025512082760440/)
