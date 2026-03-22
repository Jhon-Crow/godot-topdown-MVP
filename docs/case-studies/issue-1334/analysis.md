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

## Additional observations

- `[SceneLoader] ERROR: Invalid resource` messages appear in logs when
  the SceneLoader attempts to preload the next level during transitions.
  The first threaded load request gets `THREAD_LOAD_INVALID_RESOURCE`,
  but a retry succeeds. This is a separate issue (race condition in threaded
  resource loading) and does not cause the crash described here.
