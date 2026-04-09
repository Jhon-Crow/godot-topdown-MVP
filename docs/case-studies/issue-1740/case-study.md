# Case Study: Issue #1740 — Fix Gunslinger Difficulty (Time Does Not Slow on Every Kill)

**Issue title (RU):** fix сложность Стрелок — не при каждом убийстве замедляется время
**Translation:** "Fix Gunslinger difficulty — time does not slow down on every kill"
**Status:** OPEN
**Date of session logs:** 2026-03-29, 2026-03-30 (follow-up)

---

## 1. Logs Downloaded

| File | Local path | Lines | Session |
|------|-----------|-------|---------|
| game_log_20260329_184026.txt | `docs/case-studies/issue-1740/game_log_1.txt` | 6,702 | 18:40:26 – 18:43:50 |
| game_log_20260329_184429.txt | `docs/case-studies/issue-1740/game_log_2.txt` | 8,770 | 18:44:29 – 18:47:33 |
| game_log_20260330_103828.txt | `docs/case-studies/issue-1740/game_log_20260330_103828.txt` | 2,229 | 10:38:28 – 10:39:17 (follow-up, 2026-03-30) |

---

## 2. Source Files Analyzed

| File | Role |
|------|------|
| `scripts/autoload/power_fantasy_effects_manager.gd` | Manages the 600ms kill-triggered time-slowdown |
| `scripts/autoload/penultimate_hit_effects_manager.gd` | Manages the 3-second time-slowdown when player reaches 1 HP |
| `scripts/autoload/hit_effects_manager.gd` | Manages the 3-second 0.8x slowdown on hitting an enemy |
| `scripts/autoload/difficulty_manager.gd` | Provides `is_gunslinger_mode()` and `is_kill_last_chance_enabled()` |
| `scripts/autoload/game_manager.gd` | Emits `enemy_killed` signal; calls `register_kill()` |
| `scripts/autoload/last_chance_effects_manager.gd` | Hard-mode "last chance" freeze; Gunslinger mode checks here too |

---

## 3. System Design (How the Slowdown Works)

### Signal / Call Chain

```
Enemy._on_death()
  └─ died_with_info.emit(...)                 → level script register_kill
       └─ GameManager.register_kill()
            └─ GameManager.enemy_killed.emit()
  └─ PowerFantasyEffectsManager.on_enemy_killed()   ← direct call from enemy.gd
```

`on_enemy_killed()` (power_fantasy_effects_manager.gd, line 109):
1. Queries `DifficultyManager` — returns early if NOT Power Fantasy or Gunslinger.
2. Queries `LastChanceEffectsManager.is_effect_active()` — skips kill effect if hard-mode time-freeze is already running.
3. Calls `_start_effect(KILL_EFFECT_DURATION_MS)` → sets `Engine.time_scale = 0.1` for **600 ms real time**.

### Duration Constants (power_fantasy_effects_manager.gd)

```gdscript
const KILL_EFFECT_DURATION_MS: float = 600.0  # actual value used
const EFFECT_TIME_SCALE: float = 0.1           # 10x slowdown
```

---

## 4. Log Analysis

### Log 3 (game_log_20260330_103828.txt) — Follow-up session (2026-03-30)

**Session:** 10:38:28 – 10:39:17 (Gunslinger mode, PR #1741 fix applied)
**Owner comment:** "даже при первом убийстве не всегда срабатывает замедление, при том что визуальный эффект срабатывает всегда" (even the first kill doesn't always trigger slowdown, although the visual effect always triggers)

| Metric | Count |
|--------|-------|
| Player kills | 17 |
| "Enemy killed - triggering" messages | 17 |
| "Starting power fantasy effect" | 14 |
| "Effect timer reset" (kill during active effect) | 3 |
| "Effect duration expired" (natural end) | 17 |
| Scenes / deaths | 5 |
| Issue #1740 fix message seen | 1 (line 1555: "PowerFantasy kill effect still active — keeping time_scale slowed") |

All PowerFantasy effects in this log completed their full 600ms duration. No premature reset via PenultimateHit was observed. However, this log led to discovery of a **second root cause** (see section 5.2 below).

### Log 1 (game_log_1.txt)

**Session:** 18:40:26 – 18:43:50
**Difficulty at startup:** Normal → switched to Gunslinger at line 530 (18:40:41)

| Metric | Count |
|--------|-------|
| Player kills | 20 |
| "Enemy killed - triggering" messages | 20 |
| "Starting power fantasy effect" | 20 |
| "Effect duration expired" (natural end) | 19 |
| Effects interrupted by scene change | 1 |
| FPS drops during active effect | 3 |

### Log 2 (game_log_2.txt)

**Session:** 18:44:29 – 18:47:33
**Difficulty at startup:** Gunslinger (persisted)

| Metric | Count |
|--------|-------|
| Player kills | 49 |
| "Enemy killed - triggering" messages | 49 |
| "Starting power fantasy effect" | 45 |
| "Effect timer reset" (kill during active effect) | 4 |
| "Effect duration expired" (natural end) | 46 |
| Effects interrupted by scene change | 0 |
| FPS drops during active effect | 5 |

---

## 5. Root Cause Analysis

### Root Cause 2 (Follow-up — discovered 2026-03-30): HitEffectsManager resets time_scale during PowerFantasy/PenultimateHit effects

**File:** `scripts/autoload/hit_effects_manager.gd`, `_end_slow_effect()` (line 111)

When the player hits an enemy, `HitEffectsManager.on_player_hit_enemy()` starts a 3-second, 0.8x time slowdown. When this timer expires (or on scene reset), `_end_slow_effect()` unconditionally sets `Engine.time_scale = 1.0`.

**Scenario that causes visual effect without time slowdown:**

1. Player shoots enemy (hit, not kill) → `HitEffectsManager` sets `Engine.time_scale = 0.8`, starts 3s timer
2. Player kills the enemy → `PowerFantasyEffectsManager` sets `Engine.time_scale = 0.1`, starts 600ms timer
3. Within this 600ms window, the HitEffects 3-second timer may still be counting down — if it expires during the PowerFantasy window, `_end_slow_effect()` fires and **sets `Engine.time_scale = 1.0`**
4. The PowerFantasy visual (saturation overlay) remains active, but time is now at 1.0
5. ~600ms later, PowerFantasy's timer calls `_end_effect()` which sets `Engine.time_scale = 1.0` (already 1.0)

This also applies when the HitEffects timer fires during a PenultimateHit 3-second window.

**Why "even the first kill":** The HitEffects 3s timer may expire just after the kill — the kill is the last shot, so the HitEffects timer started shortly before the kill and can expire mid-way through the 600ms PowerFantasy window.

**Fix:** In `_end_slow_effect()`, skip the `Engine.time_scale = 1.0` reset if `PowerFantasyEffectsManager` or `PenultimateHitEffectsManager` report an active effect. Same pattern already used in `penultimate_hit_effects_manager.gd` (Fix 1).

### Primary Root Cause: PenultimateHit and PowerFantasy time_scale conflict

**File:** `scripts/autoload/penultimate_hit_effects_manager.gd`, `_end_penultimate_effect()` (line 288)

When the player reaches 1 HP, `PenultimateHitEffectsManager` starts a 3-second slowdown via `Engine.time_scale = 0.1`. If the player kills an enemy during this window:

1. `PowerFantasyEffectsManager.on_enemy_killed()` fires
2. It checks `LastChanceEffectsManager.is_effect_active()` → `false` (Gunslinger disables LastChance)
3. PowerFantasy starts its own 600ms effect (also at `Engine.time_scale = 0.1`)
4. Shortly after, `PenultimateHitEffectsManager` expires (at 3 seconds) and calls `Engine.time_scale = 1.0`
5. **Time is restored to normal even though PowerFantasy's 600ms kill effect is still active**
6. ~600ms later, PowerFantasy's timer expires and calls `Engine.time_scale = 1.0` again (already at 1.0)

**Log 2 evidence** (lines 4562–4617):
```
[18:45:56] [PowerFantasy] Starting power fantasy effect: (Duration: 600ms)
[18:45:57] [PenultimateHit] Effect duration expired after 3.03 real seconds
[18:45:57] [PenultimateHit] Ending penultimate hit effect                   ← sets time_scale=1.0
[18:45:57] [PowerFantasy] Effect duration expired after 642.00 ms           ← time_scale was already 1.0
```

The saturation overlay from PowerFantasy remains visible (correct), but time is running at normal speed (wrong) from the PenultimateHit expiry until the PowerFantasy timer expires naturally.

### Secondary: Scene-change reset during kill effect

When the player kills an enemy and immediately presses Q (or kills the last enemy auto-advancing the level), `reset_effects()` fires and restores `Engine.time_scale = 1.0` within the 600ms window.

**Log 1 evidence** (lines 1965–1991): Kill at 18:41:53, `reset_effects()` at 18:41:54 (~1 second later, but the effect had only been running for a brief moment).

### Minor: Stale log message

`"Enemy killed - triggering 300ms last chance effect"` hardcoded despite `KILL_EFFECT_DURATION_MS = 600.0`.

---

## 6. Fixes Applied (Full)

### Fix 1 (Primary — `penultimate_hit_effects_manager.gd`)

In `_end_penultimate_effect()`, before restoring `Engine.time_scale = 1.0`, check if `PowerFantasyEffectsManager` has an active kill effect. If so, skip the reset and let PowerFantasy restore time_scale when its own effect expires.

```gdscript
if not replay_mode:
    var pfm: Node = get_node_or_null("/root/PowerFantasyEffectsManager")
    if pfm and pfm.has_method("is_effect_active") and pfm.is_effect_active():
        _log("PowerFantasy kill effect still active — keeping time_scale slowed (Issue #1740)")
    else:
        Engine.time_scale = 1.0
```

### Fix 2 (Minor — `power_fantasy_effects_manager.gd`)

Replace hardcoded `"300ms"` log strings with dynamic `KILL_EFFECT_DURATION_MS`.

### Fix 3 (Follow-up — `hit_effects_manager.gd`, 2026-04-09)

In `_end_slow_effect()`, before restoring `Engine.time_scale = 1.0`, check if PowerFantasy or PenultimateHit effects are active:

```gdscript
func _end_slow_effect() -> void:
    _is_slow_active = false
    if not replay_mode:
        var pfm: Node = get_node_or_null("/root/PowerFantasyEffectsManager")
        if pfm and pfm.has_method("is_effect_active") and pfm.is_effect_active():
            return
        var phm: Node = get_node_or_null("/root/PenultimateHitEffectsManager")
        if phm and phm.has_method("is_effect_active") and phm.is_effect_active():
            return
        Engine.time_scale = 1.0
```

Also added `is_effect_active() -> bool` public method to `PenultimateHitEffectsManager` (required by Fix 3).

## 7. Files Modified

- `scripts/autoload/penultimate_hit_effects_manager.gd` — Fix 1 (time_scale conflict) + added `is_effect_active()` public method (Fix 3 support)
- `scripts/autoload/power_fantasy_effects_manager.gd` — Fix 2 (stale log strings)
- `scripts/autoload/hit_effects_manager.gd` — Fix 3 (HitEffects resetting time_scale during active slowdown)
