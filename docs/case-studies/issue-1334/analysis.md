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

## Fix

Two guards were added to `scripts/autoload/game_manager.gd`:

1. **`on_player_death()` early return**: If `player_alive` is already `false`,
   the method returns immediately. This prevents the second timer callback
   from re-triggering the death/restart sequence.

2. **`restart_scene()` reload guard**: A `_reloading` flag prevents
   `reload_current_scene()` from being called while a reload is already in
   progress. The flag is reset via `call_deferred("_reset_reloading")` at the
   end of the frame, after all pending timers have fired.

## Additional observations

- `[SceneLoader] ERROR: Invalid resource` messages appear in logs 2, 3, 4 when
  the SceneLoader attempts to preload the next level during the Labyrinth→Docks
  transition. The first threaded load request gets `THREAD_LOAD_INVALID_RESOURCE`,
  but a retry succeeds. This is a separate issue (race condition in threaded
  resource loading) and does not cause the crash described here.
