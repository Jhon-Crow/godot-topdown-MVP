# Case Study: Issue #1744 — Pacifist Enemy Bugs (Дocks/Sewer/Railway Station)

## Issue Summary

**Title:** fix громкоговоритель (fix loudspeaker)

**Reported symptoms (original Russian):**
1. На карте Доки снайпер всё ещё стреляет по игроку при 0 врагах на счётчике  
   *(On Docks map, sniper still shoots at the player when the counter shows 0 enemies)*
2. На карте Канализация уровень завершается с 0 врагов, но при этом есть враги, которые стреляют  
   *(On Sewer map, level completes at 0 enemies but there are enemies shooting at the player)*
3. Громкоговоритель перестаёт работать на карте ЖД Пути (возможно из-за особых врагов)  
   *(Loudspeaker stops working on Railway Station map, possibly due to special enemy types)*

**Logs provided:**
- `game_log_1.txt` — Docks sniper issue (90,313 lines)
- `game_log_2.txt` — Sewer level completion issue (27,112 lines)
- `game_log_3.txt` — Railway Station loudspeaker issue (19,488 lines)

---

## Issue 1: Docks Level — Sniper Still Shooting at 0 Enemy Count

### Timeline Reconstruction

| Time      | Event |
|-----------|-------|
| 12:13:56  | Player loads DocksLevel — 15 enemies registered |
| 12:14:35  | 3rd attempt after death — 15 enemies registered again |
| 12:14:37–12:15:52 | Player kills 13 enemies: ContainerYardB_Machete, ContainerYardB_Rifle, ContainerYardB_Shotgun, WarehouseA_Shotgun, CraneGuard2, WarehouseB_Rifle, CraneGuard1, WarehouseB_Grenadier, WarehouseA_UZI2, WarehouseA_UZI1, ContainerYardA_Rifle2, ContainerYardA_Rifle1, WarehouseB_UZI, LoadingDock_ArmoredSkin |
| 12:15:48  | **ContainerYardA_Sniper "Transitioned to PACIFIST"** → `_current_enemy_count` decrements to 0 |
| 12:15:49  | Player starts reloading. Sniper detects reload vulnerability and executes: `"Player vulnerable (reloading) - pursuing to attack"` → **State: PACIFIST → PURSUING** |
| 12:15:50  | Sniper transitions to COMBAT and fires at player |
| 12:16:44  | Level completes (player reaches exit zone) — sniper still alive and fighting |

### Root Cause

**File:** `scripts/objects/enemy.gd`, line 1302

```gdscript
# SECOND PRIORITY: pursue vulnerable player who is not close (Issue #1305: respect combat toggle)
if _combat_allowed and player_is_vulnerable and _can_see_player and _player and not player_close:
```

This condition checks for a **vulnerable player (reloading/ammo empty)** and transitions the enemy to PURSUING. However, it is **missing the pacifist guard** that exists on the analogous "close player" check at line 1284:

```gdscript
# Issue #318: block during confusion; Issue #959: pacifists skip; Issue #1305: respect combat toggle
if _combat_allowed and player_is_vulnerable and not is_confused and not (_pacifist and _pacifist.is_pacifist) and _can_see_player and _player and player_close:
```

When a pacifist enemy detects the player reloading and has line-of-sight, the `_update_common_state()` function forcefully transitions it to PURSUING — breaking out of the pacifist state without any notification to the level script. The level already counted this enemy as "eliminated" when it became pacifist, but the enemy is now free to attack.

**Sequence of failure:**
1. Loudspeaker pacifies ContainerYardA_Sniper → `became_pacifist` signal emitted → level count `-1`
2. Level count reaches 0 → `_level_cleared = true` → exit zone activates
3. Within 1 second, player reloads → sniper sees reload → `_transition_to_pursuing()` called
4. Sniper is now PURSUING but still alive, shooting at player — level effectively "completed" with a live enemy

---

## Issue 2: Sewer Level — Level Completes But Enemies Still Shoot

### Timeline Reconstruction (Final Sewer Run, starting 12:24:30)

| Time      | Event | Count |
|-----------|-------|-------|
| 12:24:30  | SewerLevel loaded — 13 enemies registered | 13 |
| 12:25:27  | Corridor2Guard killed by player | 12 |
| 12:25:28  | **Corridor1Guard "Transitioned to PACIFIST"** (loudspeaker) — count decremented, `died` signal DISCONNECTED | 11 |
| 12:25:29  | **Corridor3Guard "Transitioned to PACIFIST"** — count decremented, `died` signal DISCONNECTED | 10 |
| 12:25:32  | LastChance effect ends. All enemies get "Memory reset" → Corridor1Guard and Corridor3Guard transition: `PACIFIST → SEARCHING` |  |
| 12:25:32  | Corridor1Guard dies (signal disconnected, no count change) | 10 |
| 12:25:32  | Room1Guard killed | 9 |
| 12:25:33  | RoomBGuard killed | 8 |
| 12:25:34  | Room2Guard killed | 7 |
| 12:25:34  | Corridor3Guard dies (signal disconnected, no count change) | 7 |
| 12:25:34  | Room3Guard killed | 6 |
| 12:25:38  | ExitRoomMachineGunner killed | 5 |
| 12:25:39  | TopRoomGrenadier killed | 4 |
| 12:25:40  | **ForkGuardRight "Transitioned to PACIFIST"** — count `-1`, signal disconnected | 3 |
| 12:25:40  | **RoomAGuard "Transitioned to PACIFIST"** — count `-1`, signal disconnected | 2 |
| 12:25:42  | **TopRoomGuard "Transitioned to PACIFIST"** — count `-1`, signal disconnected | 1 |
| 12:25:43  | ForkGuardUp killed | **0** ← level triggers completion |
| 12:25:44  | ForkGuardRight killed (signal disconnected) | 0 |
| 12:25:52  | **Level completed** — Player controls disabled |
| 12:25:52  | RoomAGuard transitions: `SEARCHING → COMBAT` |
| 12:25:57  | RoomAGuard transitions: `PURSUING → COMBAT` — still fighting after level end |

### Root Cause (Same Bug, Different Trigger)

The same missing pacifist guard at `enemy.gd` line 1302 is the root cause. However, there is an additional contributing factor:

**Pacifist enemies lose their pacifist state when LastChance effect ends.**

When the LastChance time-freeze effect ends, enemy memory is reset (enemies lose track of player position due to the confusion timer). This "memory reset" causes enemies in PACIFIST state to transition to SEARCHING — because the pacifist state machine calls `Memory reset: confusion=2.0s, had_target=true` which then transitions `PACIFIST → SEARCHING`.

This exposes a secondary bug: **pacifist enemies should not leave pacifist state due to memory/confusion resets**. Once an enemy becomes pacifist via the loudspeaker, it should remain pacifist until the level ends (unless the player directly attacks it, which is the intended "hostility chance" mechanic).

The immediate fix for symptom 2 is the same as symptom 1 (adding the pacifist guard to line 1302), but the deeper fix would also prevent pacifists from being reverted by LastChance/memory reset.

---

## Issue 3: Railway Station — Loudspeaker "Stops Working"

### Timeline Reconstruction

The loudspeaker **does work** on the Railway Station map but with very low apparent effectiveness due to:

1. **Effect chance is only 11%** (Loudspeaker level 5)  
2. **50° cone constraint** — player often fires the loudspeaker upward (-0.15, -0.99) while enemies are spread across a wide map
3. **`was_attacked_by_player` check** — any enemy that previously attacked the player is excluded from pacification
4. **4 extra drone enemies** — drones are in the "enemies" group but don't have `apply_pacifism` method, so the log shows `Effect applied: 0/19` (including 4 drones that can never be pacified)

**Evidence of loudspeaker working:**
- 9 successful pacification events were logged: FarTracks_MachineGunnerRight, Exit_DroneOperator1, Platform_TeleporterRight3, Platform_TeleporterRight2, Platform_TeleporterLeft1 (×3), NearTracks_MachineGunnerLeft
- 8 out of 112 activation attempts (7.1%) resulted in at least 1 pacification — consistent with 11% base chance against 2–3 enemies in cone

**Possible contributing factor:**
The "0/19" count in logs is misleading — the denominator shows ALL enemies in the "enemies" group (including drones), while "Alerted 15 enemies" shows only enemies with `alert_from_loudspeaker` method. This cosmetic inconsistency in logging could contribute to the perception that the loudspeaker "stops working."

**Additionally**, the same pacifist-escape bug (issue 1/2) means that enemies who become pacifist quickly leave pacifist state if the player reloads, making the effect appear non-existent.

---

## Root Cause Summary

**Primary root cause (all 3 issues):** `scripts/objects/enemy.gd` line 1302 — missing pacifist guard in the "pursue vulnerable player" logic.

```gdscript
# BUGGY (line 1302):
if _combat_allowed and player_is_vulnerable and _can_see_player and _player and not player_close:

# CORRECT (should match line 1284 pattern):
if _combat_allowed and player_is_vulnerable and not is_confused and not (_pacifist and _pacifist.is_pacifist) and _can_see_player and _player and not player_close:
```

**Secondary contributing factor:** Pacifist enemies leave pacifist state when LastChance time-freeze effect ends (memory reset), but this is masked by the primary bug. Investigation of the memory reset interaction would require a separate fix.

---

## Proposed Fix

Add `not (_pacifist and _pacifist.is_pacifist)` to the guard condition at line 1302 in `scripts/objects/enemy.gd`.

This ensures that pacifist enemies:
- Do NOT transition to PURSUING when they see the player reloading
- Do NOT transition to PURSUING when player ammo is empty
- Continue to seek cover and remain pacifist until they are either killed or the level ends

The existing `_process_pacifist_state()` function already handles the case where a pacifist is directly attacked (`_pacifist.start_retaliation()`), which is the intended retaliation mechanic. The fix only blocks the "opportunistic pursuit" trigger.

---

## Files Changed

- `scripts/objects/enemy.gd` — Add pacifist guard to line 1302

---

## Verification

After the fix, the following behaviors should be observed:
1. **Docks:** Pacifist ContainerYardA_Sniper does not enter PURSUING when player reloads
2. **Sewer:** Pacifist enemies (Corridor1Guard, Corridor3Guard, etc.) do not enter SEARCHING/PURSUING when LastChance ends or player reloads
3. **Railway Station:** Pacifist enemies obtained via loudspeaker stay pacifist longer, making the loudspeaker feel more effective

---

## Log Files

- [`game_log_1.txt`](./game_log_1.txt) — Docks level (90,313 lines)
- [`game_log_2.txt`](./game_log_2.txt) — Sewer level (27,112 lines)  
- [`game_log_3.txt`](./game_log_3.txt) — Railway Station level (19,488 lines)
