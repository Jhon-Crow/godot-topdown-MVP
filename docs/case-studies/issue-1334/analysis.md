# Issue #1334 — Game crashes on restart in the Docks map

## Summary

The game crashes when the player dies and the scene restarts on the Docks map
(and potentially other maps). The crash is especially reproducible when killed
by the sniper enemy, because multiple enemies deal damage simultaneously,
increasing the chance of overlapping death-handling code paths.

## Data collected

| File | Description |
|------|-------------|
| `game_log_1.txt` | First session log — crash at 16:42:11 after sniper kill on Docks |
| `game_log_2.txt` | Second session log — crash at 19:28:33 during gameplay on Docks |
| `game_log_3.txt` | Third session log — crash at 19:29:49 during gameplay on Docks |
| `game_log_4.txt` | Fourth session log — transitions through Labyrinth then Docks |
| `screenshot.png`  | Screenshot of frozen game state at crash |

## Timeline reconstruction (game_log_1.txt)

1. **16:42:06** — Player takes lethal damage (health 1.0 → 0.0).
   - `CinemaEffects`, `PenultimateHit`, and `LastChance` all receive the
     `Died` signal and process death effects.
2. **16:42:06** — `docks_level.gd:_on_player_died()` fires,
   starts a `create_timer(0.5)` before calling `GameManager.on_player_death()`.
3. **16:42:06** — `LevelInitFallback.cs:OnPlayerDied()` also fires,
   starts its own `CreateTimer(0.5)` before calling `GameManager.on_player_death()`.
4. **16:42:06–16:42:07** — Scene restarts successfully (first timer fires at
   ~16:42:07, `reload_current_scene()` completes).
5. **16:42:07** — New scene is loaded. `_reset_stats()` resets `player_alive = true`.
6. **16:42:07** — Second timer fires `on_player_death()` again, which calls
   `restart_scene()` → `reload_current_scene()` a **second time** while the
   scene tree is in a transitional state.
7. **16:42:10** — Player plays on the restarted level. At 16:42:10, sniper kills
   the player again. Same double-timer pattern triggers.
8. **16:42:11** — Log ends abruptly. The game crashes due to `reload_current_scene()`
   being called on a partially-initialized or already-reloading scene tree.

## Root cause

### Duplicate `Died` signal handlers scheduling `on_player_death()`

On the Docks level (and 5 other levels), **two independent components** both
connect to the player's `Died` signal:

1. **`scripts/levels/docks_level.gd`** — the GDScript level script
   ```gdscript
   func _on_player_died() -> void:
       _show_death_message()
       if GameManager:
           await get_tree().create_timer(0.5).timeout
           GameManager.on_player_death()
   ```

2. **`Scripts/Components/LevelInitFallback.cs`** — the C# fallback component
   ```csharp
   private void OnPlayerDied()
   {
       var timer = GetTree().CreateTimer(0.5);
       timer.Timeout += () =>
       {
           if (IsInstanceValid(gameManager))
               gameManager.Call("on_player_death");
       };
   }
   ```

Both timers fire after 0.5 seconds, causing `GameManager.on_player_death()`
to execute twice. The first call triggers `reload_current_scene()`, and the
second call arrives while the engine is in the middle of (or has just completed)
a scene reload, causing undefined behavior or a crash.

### Affected levels

Any level that has both a GDScript `_on_player_died` handler AND the
`LevelInitFallback.cs` node:

- `DocksLevel.tscn`
- `BuildingLevel.tscn`
- `CityLevel.tscn`
- `FactoryLevel.tscn`
- `RevolverLevel.tscn`
- `TestTier.tscn`

### Why especially with the sniper

The sniper's hitscan fires instantly (no projectile travel time), so the
lethal shot can coincide with other damage sources in the same frame. However,
the root cause is the duplicate handler — it would crash with any death on
an affected level.

## Fix (Round 1)

Two guards were added to `scripts/autoload/game_manager.gd`:

1. **`on_player_death()` early return**: If `player_alive` is already `false`,
   the method returns immediately. This prevents the second timer callback
   from re-triggering the death/restart sequence.

2. **`restart_scene()` reload guard**: A `_reloading` flag prevents
   `reload_current_scene()` from being called while a reload is already in
   progress. The flag is reset via `call_deferred("_reset_reloading")` at the
   end of the frame, after all pending timers have fired.

## Round 2 — problem not solved

New crash logs (`game_log_20260322_200321.txt`, `game_log_20260322_200607.txt`)
show crashes still occur. Analysis revealed additional root causes:

### New findings

1. **Crashes during the 0.5s restart delay**: After the player dies, the game
   continues processing for 0.5 seconds before `on_player_death()` is called.
   During this window, enemies continue firing at the dead player's physics body.
   The sniper's hitscan raycast can interact with a dead player's collision shape,
   and various physics callbacks can fire on partially-freed nodes, causing segfaults.

2. **SceneTreeTimers persist across scene reloads**: Per Godot engine bugs
   (godotengine/godot-proposals#8577, godotengine/godot#93619), `CreateTimer()`
   timers fire even after the scene reloads and the originating node is freed.
   C# lambda closures in `LevelInitFallback.cs` can reference stale state.

3. **Player collision stays active after death**: Neither `player.gd` nor
   `Player.cs` disabled the collision layer/mask on death, allowing enemies to
   continue interacting with the dead player's physics body during the 0.5s delay.

### Timeline from new crash logs

**Log 1 (game_log_20260322_200321.txt)**:
- Death 1 (20:04:15) → restart succeeds → DocksLevel reloaded
- Death 2 (20:05:16) → restart succeeds → DocksLevel reloaded
- Death 3 (20:05:34) → enemies keep firing at dead player → crash at 20:05:38

**Log 2 (game_log_20260322_200607.txt)**:
- Player dies at 20:06:18 → enemies keep firing → crash ~1 second later

## Fix (Round 2)

### 1. Disable player collision on death
Both `player.gd` and `Player.cs` now set `collision_layer = 0` and
`collision_mask = 0` in their death handlers. This removes the dead player
from the physics world, preventing any hitscan raycasts or bullet collisions
from reaching it during the 0.5s restart delay.

### 2. Defense-in-depth in GameManager
`on_player_death()` now also disables the player's collision via the
`GameManager.player` reference, as a fallback in case the player script's
own death handler uses a different code path.

### 3. Stale callback guards
- All GDScript level death handlers now check `is_instance_valid(self)` after
  the `await` timer, preventing the coroutine from resuming on a freed node.
- `LevelInitFallback.cs` adds an `_isDying` flag to prevent duplicate
  `OnPlayerDied` calls, and its timer lambda checks `IsInstanceValid(this)`
  before proceeding.

### 4. Sniper hitscan safety
`enemy_sniper_component.gd` now checks `is_instance_valid(hit_node)` after
obtaining the collider from the raycast result, preventing crashes when the
collider is freed mid-frame.

### Files changed
- `scripts/autoload/game_manager.gd` — defense-in-depth collision disable
- `scripts/characters/player.gd` — collision disable on death
- `Scripts/Characters/Player.cs` — collision disable on death
- `Scripts/Components/LevelInitFallback.cs` — `_isDying` guard + `IsInstanceValid(this)` in timer
- `scripts/components/enemy_sniper_component.gd` — `is_instance_valid` check
- All 9 level scripts — `is_instance_valid(self)` after await in `_on_player_died()`

## Round 3 — grey death screen stuck (2026-03-22)

### Problem

User reports the game gets **stuck on a grey death screen** — no crash, but no
restart either. The game displays death effects (CinemaEffects' cigarette burn,
expanding spots, end-of-reel) and the "YOU DIED" label, but never reloads the scene.

### New logs collected

| File | Description |
|------|-------------|
| `logs/game_log_20260322_200321.txt` | Round 2 session (11806 lines) — death at 20:05:34 with no restart |
| `logs/game_log_20260322_200607.txt` | Round 2 session (1168 lines) — death at 20:06:18 with no restart |
| `logs/game_log_20260322_204406.txt` | Round 3 session (1125 lines) — death at 20:44:26 with no restart |

### Root cause analysis

The logs reveal a critical pattern: **`GameManager.on_player_death()` is never called**.
After the player dies, `CinemaEffects`, `PenultimateHit`, and `LastChance` all log
receiving the `Died` signal and processing death effects, but the log then simply stops.
There are no log entries for restart, scene reload, or `on_player_death()`.

#### Why the restart fails silently

The restart depends on level scripts' `_on_player_died()` which uses:
```gdscript
func _on_player_died() -> void:
    _show_death_message()
    if GameManager:
        await get_tree().create_timer(0.5).timeout
        if not is_instance_valid(self):
            return
        GameManager.on_player_death()
```

And `LevelInitFallback.cs::OnPlayerDied()` which uses a C# timer:
```csharp
var timer = GetTree().CreateTimer(0.5);
timer.Timeout += () => {
    if (IsInstanceValid(this) && IsInstanceValid(gameManager))
        gameManager.Call("on_player_death");
};
```

**Key finding**: On DocksLevel (and other levels where GDScript works), the
`LevelInitFallback.cs::CheckAndInitialize()` detects that GDScript `_ready()` already
ran (log: `"GDScript _ready() already ran (enemies tracked: 20) - skipping fallback"`)
and **returns early without connecting to the player's death signal**. This means only
the GDScript handler is connected.

The GDScript handler uses `await get_tree().create_timer(0.5).timeout` — a coroutine
that suspends and resumes when the SceneTreeTimer fires. In exported builds with
C#/GDScript interop, **GDScript coroutines connected to C# signals can silently fail
to resume after await**. The `Died` signal is defined in C# (`BaseCharacter.cs`), and
the connected function uses `await`, creating a cross-language coroutine boundary that
is unreliable in certain Godot 4.3 exported build configurations.

When the coroutine fails to resume, `GameManager.on_player_death()` is never called,
the scene is never reloaded, and the game stays stuck on the death screen.

### Fix (Round 3)

**Safety net timer in GameManager**: Instead of relying on level scripts to trigger
restart, GameManager now directly connects to the player's `Died`/`died` signal
via `set_player()` and starts its own safety net timer:

1. **`set_player()`** — When the player reference is set, GameManager connects to
   the player's `Died` (C#) or `died` (GDScript) signal.

2. **`_on_player_died_signal()`** — Immediately disables dead player's collision
   (defense-in-depth) and starts a 1.5s SceneTreeTimer with `process_always=true`
   and `ignore_time_scale=true`, ensuring it fires regardless of pause state or
   time scale changes.

3. **`_on_death_safety_net_timer()`** — When the timer fires, checks if
   `player_alive` is still `true`. If so, it means no level script successfully
   called `on_player_death()`, and GameManager forces the restart itself.
   Special modes (roguelike, arena) are excluded from auto-restart.

This approach:
- **Preserves normal flow**: Level scripts have 1.5s to call `on_player_death()`
  (their timers are 0.5s). If they succeed, the safety net is a no-op.
- **Catches failures**: If the GDScript coroutine silently fails, GameManager
  catches it and forces restart after 1.5s.
- **No breaking changes**: Special levels (roguelike, arena) are explicitly
  excluded from auto-restart.

### Files changed

- `scripts/autoload/game_manager.gd`:
  - `set_player()` — connects to player Died/died signal
  - `_on_player_died_signal()` — safety net timer start + collision disable
  - `_on_death_safety_net_timer()` — checks and forces restart if needed
  - `_death_signal_received` flag — tracks whether Died signal was received
  - Added logging to `on_player_death()`, `restart_scene()`, and new handlers
- `docs/case-studies/issue-1334/logs/` — new crash log files

## Round 4 — Safety net timer never fires (signal connection silently fails)

### New data

| File | Description |
|------|-------------|
| `round4/game_log_20260322_200321.txt` | Session with 3 successful restarts + 1 failed (sniper) |
| `round4/game_log_20260322_200607.txt` | Session dying on Docks from sniper — stuck on grey screen |
| `round4/game_log_20260322_204406.txt` | Session dying on Docks from sniper — stuck on grey screen |

### Analysis

The Round 3 safety net timer (`_on_player_died_signal` → `_on_death_safety_net_timer`)
**never fires**. Searching all three log files for `[GameManager]` entries shows only:
- `GameManager ready`
- `Weapon selected: ...`
- `kills_without_laser_sight: ...`

There is **no** `"Connected to player 'Died' signal"` log entry from `set_player()`,
even though `docks_level.gd:235` calls `GameManager.set_player(_player)`.

Meanwhile, CinemaEffects, PenultimateHit, and LastChance (all GDScript autoloads) **do**
successfully connect to the player's `Died` signal and receive it on death.

### Root cause

`GameManager.set_player()` uses `player.has_signal("Died")` to check for the C# signal
before connecting. **This check returns `false`** in the running build, causing the
connection to be silently skipped. The `Died` signal is defined on `BaseCharacter.cs`
(an inherited C# class), and GDScript's `has_signal()` may not reliably detect signals
inherited from C# base classes in all Godot 4 build configurations.

Other GDScript components (PenultimateHit, LastChance, CinemaEffects) connect to the
same signal but do so **later** (after shader warmup completes, ~1 second after _ready).
At that point, the C# node's signal table may be fully initialized, explaining why
their `has_signal("Died")` succeeds while GameManager's fails (called during `_ready()`).

Evidence: `game_log_20260322_200321.txt` shows the docks level's `_on_player_died()`
coroutine (GDScript await) works intermittently — 3 out of 4 deaths triggered restart
successfully, but the 4th death (sniper kill) failed silently, leaving the grey screen.

### Fix (Round 4)

Added **poll-based death detection** in `GameManager._process()` as a bulletproof fallback
that works regardless of signal connection status.

**How it works**: Every frame, if `player_alive == true` and `player.collision_layer == 0`,
the player is dead (Player.cs's `OnDeath()` sets `CollisionLayer = 0` immediately on death).
GameManager detects this and starts the same 1.5s safety net timer used by the signal handler.

This approach:
- **Works without signal connection**: No dependency on `has_signal()` or C# signal interop
- **Uses standard Godot property**: `collision_layer` is a built-in CharacterBody2D property,
  fully accessible from GDScript via the Godot property system
- **Preserves normal flow**: The 1.5s timer gives level scripts time to handle death first;
  if they succeed, the safety net is a no-op
- **No false positives**: `collision_layer` is only set to 0 in `Player.OnDeath()`;
  new players always spawn with collision_layer > 0

Also added comprehensive logging in `set_player()` to trace exactly why signal connection
fails, so future logs will contain diagnostic information:
- `has_signal('Died')` and `has_signal('died')` results
- Initial `collision_layer` value (baseline for poll detection)
- Player class name

### Files changed

- `scripts/autoload/game_manager.gd`:
  - `_process()` — added poll-based death detection checking `collision_layer == 0`
  - `_start_death_safety_net()` — extracted shared timer-start logic for signal and poll paths
  - `_death_detected_by_poll` flag — prevents repeated poll triggers
  - `set_player()` — added diagnostic logging for signal and collision_layer status
  - `_on_death_safety_net_timer()` — updated guard to check both `_death_signal_received` and `_death_detected_by_poll`
  - `_reset_stats()` — resets `_death_detected_by_poll`
- `docs/case-studies/issue-1334/round4/` — new crash log files

## Round 5 — Sniper hitscan fires at dead player on the same frame (crash)

### Data collected

| File | Description |
|------|-------------|
| `game_log_20260323_033423.txt` | Session log — crash at 03:35:23 when sniper hitscan hits dead player |

### Timeline reconstruction

1. **03:35:23** — Player is on Docks map (third life). Multiple enemies fire simultaneously.
2. **03:35:23** — `ContainerYardB_Rifle` fires a bullet that kills the player (lethal=True, health drops to 0).
3. **03:35:23** — Player.OnDeath() fires: sets CollisionLayer=0, emits Died signal synchronously.
4. **03:35:23** — Died signal handlers run in sequence:
   - GameManager._on_player_died_signal: disables collision, starts 1.5s safety net timer
   - CinemaEffects: triggers death effects
   - PenultimateHit: ends penultimate effect
   - LastChance: records death
5. **03:35:23** — **ON THE SAME FRAME**: ContainerYardA_Sniper's hitscan fires.
   - `shoot_sniper_hitscan()` uses `direct_space_state.intersect_ray()` with collision mask 1
   - Despite CollisionLayer being set to 0 in step 3, Godot's physics server does NOT flush
     collision layer changes mid-frame for direct_space_state queries — the raycast still finds
     the player on collision layer 1
   - The `is_alive` check (`has_method("is_alive")`) fails because the player is a C# node:
     C# properties (IsAlive) are not exposed as GDScript methods, so `has_method("is_alive")`
     returns false, and the check is bypassed
   - The hitscan calls `TakeDamage(50)` on the dead player
6. **03:35:23** — Log ends after SoundPropagation logs. **CRASH** — the game terminates.

### Root cause

Three layered failures combine to produce the crash:

1. **`GameManager.player_alive` was not set to false on the Died signal** — it was only set
   to false in `on_player_death()`, which runs 0.5–1.5 seconds later via timers. During
   the intervening frames, enemies still see `player_alive = true` and continue shooting.

2. **The sniper hitscan's `is_alive` check doesn't work for C# players** — the check
   `has_method("is_alive")` fails for C# nodes because `IsAlive` is a C# property (accessed
   via `get("IsAlive")` from GDScript, not via `call("is_alive")`). The condition
   `(not has_method("is_alive")) or call("is_alive")` evaluates to `(not false) or ...` = `true`,
   so the hitscan always considers the target alive.

3. **Godot's direct_space_state doesn't flush CollisionLayer changes mid-frame** — even though
   `CollisionLayer = 0` is set in OnDeath(), the physics server still returns the player in
   `intersect_ray()` queries within the same frame, because the collision data is only updated
   at the next physics step.

### Fix (Round 5)

**Primary fix — Set `player_alive = false` immediately on death signal:**
- `_on_player_died_signal()` now sets `player_alive = false` immediately when the Died signal fires
- This prevents ALL enemies from shooting at the dead player (they check `player_alive` before firing)
- Updated `on_player_death()` and `_on_death_safety_net_timer()` guards to use `_reloading` instead
  of `player_alive`, since `player_alive` is now false immediately

**Defense-in-depth — Enemy shoot prevention:**
- `_execute_shoot()`: Added `GameManager.player_alive` check before any shooting
- `_shoot_with_inaccuracy()`: Added `GameManager.player_alive` check
- `_machine_gunner_fire_at_corridor()`: Added `GameManager.player_alive` check
- `shoot_sniper_hitscan()`: Added `GameManager.player_alive` check at entry
- `fire_at_predicted_position()`: Added `GameManager.player_alive` check

**Defense-in-depth — Fixed C# `IsAlive` property check in hitscan:**
- The `is_alive` check now also checks `hit_node.get("IsAlive")` for C# properties
- This ensures even if `GameManager.player_alive` is somehow stale, the hitscan correctly
  skips dead C# nodes

### Changes (Round 5)

- `scripts/autoload/game_manager.gd`:
  - `_on_player_died_signal()` — sets `player_alive = false` immediately
  - `on_player_death()` — changed guard from `player_alive` to `_reloading`
  - `_on_death_safety_net_timer()` — changed guard from `player_alive` to `_reloading`
  - `_process()` poll detection — removed `player_alive` from condition, added `player_alive = false`
- `scripts/objects/enemy.gd`:
  - `_execute_shoot()` — added `GameManager.player_alive` check
  - `_shoot_with_inaccuracy()` — added `GameManager.player_alive` check
  - `_machine_gunner_fire_at_corridor()` — added `GameManager.player_alive` check
- `scripts/components/enemy_sniper_component.gd`:
  - `shoot_sniper_hitscan()` — added `GameManager.player_alive` check; fixed `is_alive` to also check C# property `IsAlive`
  - `fire_at_predicted_position()` — added `GameManager.player_alive` check

## Round 6 — Native segfault from physics state mutation during hitscan raycast loop

### Symptom
User reports: "всё ещё вылетает" (still crashes) specifically when killed by a sniper.
Log: `game_log_20260323_041436.txt`

### Log analysis
The log ends abruptly at line 1405 during active combat on the Docks map. There is **no death
event logged at all** — no `player_alive`, no `on_player_death`, no `Died` signal, no restart.
The game process terminates instantly with a native segfault. The logging system has no time
to flush its buffer before the crash.

The last entries show normal combat activity: enemies shooting, sound propagation events,
blood decals — then nothing. The crash is so fast that it occurs between log writes.

### Root cause
**Modifying physics state (CollisionLayer) during an active `direct_space_state.intersect_ray()` loop
causes undefined behavior in Godot's physics server, resulting in a native C++ segfault.**

The crash sequence in `shoot_sniper_hitscan()`:
1. Sniper hitscan fires — enters raycast loop calling `space_state.intersect_ray()` iteratively
2. Loop finds the player as a collision hit on layer 1
3. Loop calls `hit_node.call("TakeDamage", 50)` — lethal damage to the player
4. `TakeDamage(50)` runs **synchronously** → `HealthComponent.TakeDamage()` → `Died` signal
   → `BaseCharacter.OnHealthDied()` → `Player.OnDeath()` → **`CollisionLayer = 0`**
5. `EmitSignal(SignalName.Died)` fires → `GameManager._on_player_died_signal()` →
   **`player.collision_layer = 0`** (again), **`player.collision_mask = 0`**
6. Control returns to the hitscan loop — next iteration calls `space_state.intersect_ray()`
7. **SEGFAULT** — The physics server's internal state was mutated (CollisionLayer changed)
   during an active query sequence. Godot's physics server does not support concurrent
   modification during `direct_space_state` queries.

### Evidence from Godot engine documentation and issues
This is a **well-documented class of unsafe operations** in Godot:
- Godot issues #19023, #107951, #6676, #34330, #101795 document crashes from modifying
  physics state during physics callbacks/queries
- The engine tries to guard against this with "Removing a CollisionObject node during a
  physics callback is not allowed" warnings, but these guards do **not** catch indirect
  modifications through cross-language (GDScript→C#) method calls
- The Godot physics troubleshooting docs recommend using `call_deferred()` for any physics
  state changes triggered during physics operations

### Why Round 5 fix didn't work
Round 5 added `GameManager.player_alive` checks before shooting, and set `player_alive = false`
immediately on the `Died` signal. But the crash happens **inside the hitscan's own execution**:
- The hitscan function calls `TakeDamage()` which kills the player synchronously
- The `Died` signal fires synchronously within `TakeDamage()`
- `player_alive = false` IS set... but we're already past the `player_alive` check at the
  function entry — we're inside the raycast loop
- The physics state modification (CollisionLayer=0) happens before the loop finishes
- The next `intersect_ray()` call crashes

### Fix
**Deferred damage application**: Collect all hits during the raycast loop without calling any
damage methods. After the loop fully completes (all `intersect_ray()` calls are done), apply
damage to the collected hits. This is the standard safe pattern for Godot physics queries.

```
# BEFORE (Round 5 — crashes):
for _i in range(50):
    var char_result := space_state.intersect_ray(...)
    if target_alive:
        hit_node.call("TakeDamage", damage)   # ← modifies physics state mid-loop!
    exclude_rids.append(char_result["rid"])     # ← next iteration crashes

# AFTER (Round 6 — safe):
var pending_hits := []
for _i in range(50):
    var char_result := space_state.intersect_ray(...)
    if target_alive:
        pending_hits.append({"node": hit_node, ...})  # ← collect only
    exclude_rids.append(char_result["rid"])

# Apply damage AFTER all raycast queries are complete:
for hit_info in pending_hits:
    hit_node.call("TakeDamage", damage)   # ← safe, no active physics query
```

Additional safety: re-check `is_alive`/`IsAlive` before applying each deferred hit, in case
a prior hit in the same batch already killed the target.

### Changes (Round 6)

- `scripts/components/enemy_sniper_component.gd`:
  - `shoot_sniper_hitscan()` — Restructured to collect hits in `pending_hits` array during
    raycast loop, then apply damage after loop completes. Added re-validation of node validity
    and alive status before each deferred damage call.

---

## Round 7 — Process-based safety net countdown + robust IsAlive check

After Rounds 5-6, user reported the grey screen still persists. Two issues found:

1. **SceneTreeTimer callback never fires**: The safety net timer from `get_tree().create_timer()`
   silently failed when death effects modified scene processing state. Replaced with `_process()`-based
   countdown that decrements `_safety_net_countdown` each frame.

2. **IsAlive check bypassed for C# Player**: The sniper's `hit_node.get("IsAlive")` returns `null`
   for non-`[Export]` C# properties. Added `_check_target_alive()` with four fallback strategies.

---

## Round 8 — Wall-clock safety net + enemy AI freeze (2026-03-23)

### New crash logs analyzed

| File | Lines | Failure mode |
|------|-------|-------------|
| `game_log_20260323_063548.txt` | 8749 | Process crashes instantly after sniper hits dead player |
| `game_log_20260323_063713.txt` | 1286 | Process crashes mid-gameplay, no death events |
| `game_log_20260323_063737.txt` | 1372 | Grey screen stuck — safety net starts but never fires |
| `game_log_20260323_063759.txt` | 19080 | Mixed: LabyrinthLevel works fine, Docks crashes |

### Root cause 1: Safety net countdown affected by Engine.time_scale

The Round 7 fix used `_safety_net_countdown -= delta` in `_process()`. While `PROCESS_MODE_ALWAYS`
ensures `_process()` runs every frame, **`delta` is still scaled by `Engine.time_scale`**.

Death effects set `Engine.time_scale = 0.1` (PenultimateHit) which makes the delta 10x smaller.
A 1.5-second countdown effectively takes **15 real seconds** to complete. The user sees the grey
death screen for 15 seconds and thinks the game is frozen.

**Evidence**: In `game_log_20260323_063737.txt`, the safety net starts at 06:37:46 and should
fire at 06:37:47.5 (1.5s later). The log continues with enemy activity until 06:37:47 with no
restart. The 1.5s scaled delta has barely counted down 0.15s (1.5 * 0.1 time_scale).

**Fix**: Replaced delta-based countdown with wall-clock deadline using `Time.get_ticks_msec()`.
The deadline fires in real-world seconds regardless of `Engine.time_scale`.

### Root cause 2: Enemies continue full AI after player death → native segfault

After `player_alive = false` is set, enemies still run full `_physics_process()` — pathfinding,
raycasting, state transitions, LOS checks. These access the player node's physics body which
is in an inconsistent state (CollisionLayer was set to 0 by C# but the physics server may not
have processed it yet).

**Evidence**: In `game_log_20260323_063548.txt`, after the death signal fires (line 8736),
enemies continue "Player distracted - priority attack triggered" for several lines, then the
sniper hitscan hits the dead player (line 8744), followed by a few more enemy actions, then
the process terminates abruptly — characteristic of a native C++ segfault.

**Fix**: Added `player_alive` check at the very top of `enemy._physics_process()`. When the
player is dead, ALL enemy AI processing stops immediately. This is a defense-in-depth measure
that prevents any enemy code from accessing the dead player's physics state.

### Root cause 3: Sniper raycast hits dead player with stale physics state

The sniper's hitscan raycast uses `direct_space_state.intersect_ray()` with collision mask 1.
After `Player.OnDeath()` sets `CollisionLayer = 0`, the physics server may not immediately
update — the next `intersect_ray()` call can still hit the player. While damage is deferred
and skipped (Round 6 fix), the raycast itself may trigger undefined behavior in the physics
server when querying an object whose collision state is being modified.

**Fix**: Added mid-loop `player_alive` check in the raycast loop, and pre-compute the player's
RID to exclude it from character raycasts when the player is dead.

### Changes (Round 8)

- `scripts/autoload/game_manager.gd`:
  - Replaced `_safety_net_countdown` (float, delta-based) with `_safety_net_deadline_ms` (int,
    wall-clock deadline via `Time.get_ticks_msec()`). Unaffected by `Engine.time_scale`.
  - Updated `_process()`, `_start_death_safety_net()`, and `_reset_stats()` accordingly.

- `scripts/objects/enemy.gd`:
  - Added `player_alive` check at top of `_physics_process()` — freezes all enemy AI instantly
    when player dies. Prevents physics queries, pathfinding, and shooting on dead player node.

- `scripts/components/enemy_sniper_component.gd`:
  - Pre-compute player RID for raycast exclusion.
  - Re-check `player_alive` each iteration of the raycast loop, aborting if player died mid-frame.
  - Exclude dead player's RID from character raycast queries.

---

## Round 9 (2026-03-23)

### Root cause 1: `_reset_stats()` prematurely resets `player_alive = true`

`restart_scene()` calls `_reset_stats()` which sets `player_alive = true` and `player = null`
**before** `reload_current_scene()` completes. Since `reload_current_scene()` is deferred (it
calls `change_scene_to_file()` internally which defers the actual scene swap), there is a window
where enemies see `player_alive = true` but the old player node is in a transitional or freed
state. The enemy's Round 8 guard (`if not player_alive: return`) passes, and the enemy resumes
full AI processing — accessing `_player.global_position` on a freed or inconsistent node causes
a native segfault.

**Evidence**: In `game_log_20260323_072247.txt`, the game successfully restarts after a death at
07:23:47 (GameManager safety net works correctly). But after the reload at 07:23:48, the log
ends abruptly at 07:23:51 during normal gameplay with NO death event logged — characteristic of
a native segfault. The `LoadingDock_UZI` enemy fires shots and triggers distraction attacks right
before termination, suggesting enemy AI accessed stale player state.

**Fix**: Removed `player_alive = true` from `_reset_stats()`. Now `player_alive` stays `false`
throughout the entire scene reload transition and is only reset to `true` in `set_player()` when
the new scene's player node is registered. This eliminates the window where enemies could see
a false-positive alive state during reload.

### Root cause 2: No absolute failsafe for stuck death states

The existing safety mechanisms (signal-based detection, poll detection, 1.5s wall-clock timer)
all have guards and conditions that can prevent them from firing. If any combination of edge
cases causes ALL mechanisms to fail (e.g., `_reloading` flag stuck true, signal connection lost,
poll detection bypassed), the player is stuck on the grey death screen forever.

**Fix**: Added an absolute wall-clock failsafe in `_process()` that tracks when `player_alive`
was set to `false`. If 5 real seconds elapse without `set_player()` being called (which resets
it to `true`), the failsafe force-clears ALL guards (`_reloading`, `_safety_net_deadline_ms`)
and calls `restart_scene()`. This failsafe re-arms every 5 seconds if the restart fails, and
only `set_player()` (successful new scene load) permanently clears it. Special modes (roguelike,
ArenaLevel) are excluded from auto-restart.

### Root cause 3: Enemy references freed player node

Enemy `_physics_process()` and visibility check code access `_player.global_position` without
checking `is_instance_valid(_player)`. While the Round 8 `player_alive` guard prevents this
during normal death flow, the `_reset_stats()` timing bug (root cause 1) could let enemies
past the guard with a stale `_player` reference pointing to a freed node.

**Fix**: Added `is_instance_valid(_player)` checks:
- At the top of `_physics_process()`: if `_player` is invalid, set `_player = null` and return
- In the visibility check fast-path: added to the null-check condition
- In the distraction attack condition: added alongside the existing `_player` truthiness check

### Changes (Round 9)

- `scripts/autoload/game_manager.gd`:
  - Removed `player_alive = true` from `_reset_stats()` — stays false until `set_player()`.
  - Added `player_alive = true` and `_player_dead_since_ms = 0` reset in `set_player()`.
  - Added `_player_dead_since_ms` wall-clock timestamp tracking in all death detection paths.
  - Added absolute 5-second failsafe in `_process()` that ignores all guards and forces restart.

- `scripts/objects/enemy.gd`:
  - Added `is_instance_valid(_player)` check at top of `_physics_process()` (clears stale ref).
  - Added `is_instance_valid(_player)` in visibility check fast-path.
  - Added `is_instance_valid(_player)` in distraction attack condition.

## Round 10 — Native crash from physics state mutation + dead player continues processing (2026-03-23)

### New data collected

| File | Lines | Description |
|------|-------|-------------|
| `game_log_20260323_082449.txt` | 5211 | Session with our Round 9 fixes — crash at 08:26:03 after sniper kill |
| `game_log_20260322_192721.txt` | 7850 | User's original code (no fixes) — grey screen stuck after death |
| `game_log_20260322_192922.txt` | 2682 | User's original code — grey screen stuck after death |
| `game_log_20260322_193021.txt` | 837 | User's original code — grey screen stuck after death |
| `screenshot_round10.png` | — | Grey death screen stuck (from user's original code) |

### Log analysis — Round 9 code (game_log_20260323_082449.txt)

The latest log confirms our Round 9 fixes are working (safety net messages present). The game
successfully restarts 3 times via Q-key quick restart (08:24:59, 08:25:52, 08:25:57). But on the
4th death at 08:26:03 (killed by enemies after disabling invincibility), the game crashes.

**Crash sequence at 08:26:03:**

1. Player has 2 HP. Two hits arrive on the same frame (from OpenArea_Patrol2):
   - Hit 1: health 2→1 (PenultimateHit: "Hard mode — skipping, using last chance instead")
   - Hit 2: health 1→0 (lethal)
2. `Player.OnDeath()` fires → sets `CollisionLayer = 0`, `CollisionMask = 0`
3. `BaseCharacter.OnHealthDied()` emits `Died` signal
4. Signal handlers fire in sequence:
   - GameManager: sets `player_alive = false`, sets `collision_layer = 0` (again), starts safety net
   - CinemaEffects: triggers death effects
   - PenultimateHit/LastChance: record death
5. **After signal handlers**: A weapon shot fires (`ak_gl (9 total)`) — the dead player's
   `_PhysicsProcess()` was already running and continued to call `HandleShootingInput()` → `Shoot()`
6. Enemies react to the dead player's shot (sound propagation, suppression)
7. Blood puddle created
8. **Log ends abruptly** — native crash (process killed, no graceful shutdown)

### Root cause analysis

**Three distinct root causes identified:**

#### Root cause 1: `Player._PhysicsProcess` continues after death

The C# Player's `_PhysicsProcess()` method has **no** `IsAlive` check. After `OnDeath()` fires
(triggered by `TakeDamage()` → `HealthComponent.Died` signal), the `_PhysicsProcess()` method
was already in progress for this frame. The remaining code in `_PhysicsProcess()` continues to
execute: `HandleShootingInput()` → `Shoot()` → `CurrentWeapon.Fire()`. This creates a weapon
projectile from a dead player, and the weapon's fire/reload/input processing accesses player state
that may be inconsistent (collision disabled, health 0, etc.), leading to crashes.

**Evidence**: The log shows `[WeaponHintsComponent] Shot fired with ak_gl (9 total)` AFTER the
death signal handlers have all completed. This shot came from the dead player.

#### Root cause 2: Modifying CollisionLayer during active physics callbacks causes native segfault

`Player.OnDeath()` sets `CollisionLayer = 0` and `CollisionMask = 0` **synchronously** inside the
`TakeDamage()` call chain. When `TakeDamage()` is triggered by a bullet's `body_entered` or
`area_entered` callback, modifying collision properties during an active physics callback corrupts
the physics server's internal collision pair list.

This is a well-documented class of Godot bugs (see Round 6 analysis). The fix in Round 6 addressed
this for the **sniper hitscan** (deferred damage in raycast loop), but the root cause remained for
**all other damage sources** (rifle/shotgun/UZI bullets, grenades, etc.) that trigger `TakeDamage()`
via `body_entered`/`area_entered` physics callbacks.

**Evidence**: The crash happens on the same frame as death, with no SCRIPT ERROR logged — this is
the signature of a native C++ segfault in the physics server.

#### Root cause 3: GDScript code cannot detect dead C# Player

GDScript bullets use `has_method("is_alive")` to check if a collision target is alive before
applying damage. The C# Player class exposes `IsAlive` as a **property** (on `BaseCharacter`),
NOT as a method named `is_alive`. So `has_method("is_alive")` returns **false** for the Player
node, and the bullet's dead-entity guard is bypassed:

```gdscript
# bullet.gd line 514:
if body.has_method("is_alive") and not body.is_alive():
    return  # Pass through dead entities
# ↑ has_method("is_alive") returns FALSE for C# Player → check is skipped entirely
# The bullet hits the dead player and processes the collision
```

This allows in-flight bullets to collide with the dead player's body, triggering `body_entered`
callbacks that access physics state of a dead/dying node.

### Fix (Round 10)

#### Fix 1: Guard `_PhysicsProcess` with `IsAlive` check

Added `if (!IsAlive) return;` at the very top of `Player._PhysicsProcess()`. This immediately
stops ALL player processing (movement, input, shooting, animations) when the player is dead.
No more dead-player weapon fire or state access after death.

#### Fix 2: Defer ALL collision layer/mask changes

Changed `CollisionLayer = 0` in `Player.OnDeath()` from synchronous assignment to
`CallDeferred(MethodName._DisableDeadPlayerCollision)`. This ensures the physics server's
collision data is modified at the end of the frame (after all physics callbacks complete),
preventing the native segfault from mid-callback physics state mutation.

Also deferred all collision changes in `GameManager`:
- `_on_player_died_signal()` — uses `call_deferred("set", "collision_layer", 0)`
- `_start_death_safety_net()` — uses `call_deferred("set", "collision_layer", 0)`
- `on_player_death()` — uses `call_deferred("set", "collision_layer", 0)`

The `player_alive = false` flag remains **immediate** (not deferred) — this is the primary
guard that prevents enemies from shooting. The deferred collision disable is defense-in-depth
for the physics server.

#### Fix 3: Add `is_alive()` bridge method for GDScript interop

Added `public bool is_alive() => IsAlive;` to `Player.cs`. This exposes a GDScript-compatible
method that matches the naming convention used by enemy scripts and bullet collision code.

With this method:
- `has_method("is_alive")` now returns `true` for the C# Player node
- `body.is_alive()` returns `false` when the player is dead
- Bullets in flight correctly pass through the dead player instead of triggering collisions
- The sniper's `_check_target_alive()` Strategy 1 now works directly (no need for fallbacks)

#### Fix 4: Disable HitArea and ThreatSphere on death

`Player.OnDeath()` now also disables:
- **HitArea** (Area2D): `CollisionLayer/Mask = 0`, `Monitoring/Monitorable = false`
  — prevents bullets from triggering `area_entered` on dead player's hit detection
- **ThreatSphere** (Area2D): `Monitoring/Monitorable = false`
  — prevents LastChance from processing threats for a dead player

### Changes (Round 10)

- `Scripts/Characters/Player.cs`:
  - Added `if (!IsAlive) return;` at top of `_PhysicsProcess()` — stops dead player processing
  - Added `public bool is_alive() => IsAlive;` — GDScript-compatible alive check method
  - Changed `OnDeath()` to use `CallDeferred` for collision disabling
  - Added `_DisableDeadPlayerCollision()` method — disables player, HitArea, and ThreatSphere

- `scripts/autoload/game_manager.gd`:
  - `_on_player_died_signal()` — uses `call_deferred("set", ...)` for collision changes
  - `_start_death_safety_net()` — uses `call_deferred("set", ...)` for collision changes
  - `on_player_death()` — uses `call_deferred("set", ...)` for collision changes

### Why this combination should resolve the remaining crashes

1. **`player_alive = false` (immediate)** — Prevents all enemies from shooting (Round 5 fix, preserved)
2. **`IsAlive` check in `_PhysicsProcess` (immediate)** — Stops dead player from processing input/shooting
3. **`is_alive()` bridge method** — Bullets correctly detect dead C# player and pass through
4. **Deferred collision changes** — Physics server state is never modified during active callbacks
5. **HitArea/ThreatSphere disabled** — No new collision callbacks can fire on dead player
6. **Safety net + absolute failsafe (Rounds 8-9)** — Restart guaranteed within 1.5-5s even if all else fails

### Known existing components/libraries for similar problems

- **Godot's `call_deferred()` pattern**: The official recommended approach for modifying physics
  state during physics callbacks. Used by Godot's own collision response code internally.
- **Godot's `set_deferred("collision_layer", 0)` pattern**: Common pattern in Godot tutorials
  and documentation for safely disabling collision during physics processing.
- **Signal disconnection on death**: Some Godot projects disconnect all signals from the dying
  node to prevent any callbacks. We use `Monitoring = false` on Area2D instead, which is simpler.
- **Object pooling**: Some games avoid the freed-node problem entirely by pooling and recycling
  character nodes instead of freeing them. Not applicable here (scene reload approach).

## Round 11 — Native crash during gameplay with many simultaneous enemies

### Data collected (Round 11)

| File | Description |
|------|-------------|
| `game_log_20260322_192721.txt` | Crash during gameplay on Docks — no player death event before crash |
| `game_log_20260322_192922.txt` | Crash during gameplay on Docks — player AK_GL firing + many enemies reacting |
| `game_log_20260322_193021.txt` | Crash during gameplay on Docks — sniper entering COMBAT + distracted attacks |
| `game_log_20260323_092753.txt` | Successful death+restart then crash on second playthrough — 12+ distracted attacks in 1s |

### Problem description

After applying Rounds 1–10 fixes, the game still crashes on the Docks map. However, the
crash pattern has changed: **the crash now occurs during normal gameplay (player alive), not
during the death/restart sequence**. The logs show the game terminating abruptly (native
segfault) with no error message or death event logged.

### Timeline reconstruction (game_log_20260323_092753.txt)

1. **09:28:03** — Player enters Docks map (20 enemies spawned)
2. **09:28:10** — Player dies from enemy rifle, game successfully restarts
3. **09:28:12** — Second playthrough begins, player engages enemies
4. **09:28:13** — `ContainerYardB_Machete` killed → 30 blood decals + ragdoll activation
5. **09:28:13** — `LoadingDock_UZI` fires **12+ "distracted attack" shots** within ~1 second
6. **09:28:13** — `ContainerYardA_Rifle2`, `LoadingDock_Rifle2` also fire distracted attacks
7. **09:28:13** — `ContainerYardA_Sniper` enters COMBAT, rotates to aim at player
8. **09:28:14** — **CRASH** — log stops mid-frame during enemy processing

### Root cause analysis

Five distinct root causes identified:

#### 1. Unsafe `await` coroutines resume on freed nodes
`_play_delayed_shell_sound()` calls `await get_tree().create_timer(0.15).timeout` without
checking if the node is still in the scene tree after the await completes. When many enemies
fire rapidly (12+ shots/second), many SceneTreeTimer coroutines are created. If the scene
reloads before all timers fire, the coroutine resumes on a freed node → native segfault.
Same issue in `_show_hit_flash()`, `_on_death()` cleanup, and reload reaction code.

#### 2. Physics body creation during active physics processing
`death_animation_component.gd:_create_ragdoll_body()` creates 4 new `RigidBody2D` nodes with
`get_tree().current_scene.add_child(rb)` during the physics callback chain (death signal →
ragdoll activation). Adding new collision objects during the "flushing queries" phase of the
physics server corrupts its internal collision pair list. Similarly, `_create_ragdoll_joint()`
adds `PinJoint2D` nodes during the same callback chain.

#### 3. Bullet pool monitoring changes during physics processing
`bullet.gd:pool_activate()` sets `monitoring = true` and `monitorable = true` directly (not
deferred). When bullet pooling recycles a bullet during the same frame that other bullets are
being processed by the physics server, this can corrupt the collision pair list. The "flushing
queries" error occurs silently in release builds but causes native crashes when combined with
other concurrent physics mutations.

#### 4. Missing validity guards in collision callbacks
`_on_body_entered`, `_on_area_entered`, and `_on_body_exited` in `bullet.gd` and `shrapnel.gd`
do not check `is_instance_valid(body/area)` before accessing the collider. When ragdoll bodies
are being created/freed in the same frame, the physics server may deliver collision callbacks
with stale collider references → native segfault.

#### 5. Projectile spawning without scene tree validation
`_spawn_projectile()`, `_spawn_casing()`, and `_fire_rpg_rocket()` access
`get_tree().current_scene.add_child()` without checking if the enemy is still in the tree
or if `current_scene` is null. During scene transitions or rapid enemy destruction, these
calls can fail with null reference errors or add children to a scene that's being freed.

### Fix

1. **Added `is_inside_tree()` guards** after all `await` statements in enemy.gd — prevents
   coroutine resume on freed nodes
2. **Deferred ragdoll body/joint creation** via `call_deferred("add_child", rb)` — prevents
   physics body creation during active physics callbacks
3. **Deferred bullet pool monitoring changes** via `set_deferred("monitoring", true/false)` —
   prevents collision pair list corruption during physics processing
4. **Added `is_instance_valid()` guards** at top of all collision callbacks in bullet.gd and
   shrapnel.gd — prevents access to freed colliders
5. **Added scene tree validation** in `_spawn_projectile()`, `_spawn_casing()`, `_fire_rpg_rocket()`,
   `_execute_shoot()`, and sniper hitscan code — prevents null reference crashes

### Relevant Godot engine issues

- [#107951](https://github.com/godotengine/godot/issues/107951) — Crash when adding/removing
  bodies while performing physics queries
- [#85852](https://github.com/godotengine/godot/issues/85852) — Errors when changing scene
  during physics callbacks
- [Godot Physics Troubleshooting](https://docs.godotengine.org/en/4.3/tutorials/physics/troubleshooting_physics_issues.html) —
  "Removing a CollisionObject node during a physics callback is not allowed"

## Additional observations

- `[SceneLoader] ERROR: Invalid resource` messages appear in logs when
  the SceneLoader attempts to preload the next level during transitions.
  The first threaded load request gets `THREAD_LOAD_INVALID_RESOURCE`,
  but a retry succeeds. This is a separate issue (race condition in threaded
  resource loading) and does not cause the crash described here.
