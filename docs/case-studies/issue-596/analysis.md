# Case Study: Issue #596 - Beach Map Ammo Counter Not Working

## Issue Summary
The ammo counter (HUD label showing current/reserve ammo) was not updating on the Beach map (BeachLevel), while it worked correctly on all other levels (BuildingLevel, TestTier, CastleLevel).

## Timeline of Events

1. **Issue #579**: BeachLevel was created as a new level with outdoor beach environment
2. **BeachLevel script**: Written as a simplified version of the level template, but missing critical weapon setup and signal connection code
3. **User report (2026-02-07)**: Player noticed ammo counter stays at initial value ("AMMO: 9/9" or "AMMO: 30/30") and never updates when shooting on the Beach map
4. **Log files provided**: `game_log_20260207_175534.txt` and `game_log_20260207_175949.txt` showing multiple Beach level load/restart cycles with no ammo-related signal activity

## Root Cause Analysis

### The Architecture

The game uses a **C# Player** with **C# weapon classes** (BaseWeapon subclasses like MakarovPM, AssaultRifle, Shotgun, etc.). Weapons emit signals using C# PascalCase naming:
- `AmmoChanged(int currentAmmo, int reserveAmmo)` - when ammo count changes
- `MagazinesChanged(int[] magazineAmmoCounts)` - when magazine inventory changes
- `Fired()` - when weapon fires
- `ShellCountChanged(int shellCount, int capacity)` - for shotgun shell-by-shell reload

The GDScript level scripts must connect to these C# signals to update the HUD.

### What Was Missing

**BeachLevel.gd (`_setup_player_tracking`)** was an incomplete implementation:

| Feature | BeachLevel (BEFORE) | BuildingLevel/CastleLevel/TestTier |
|---------|--------------------|------------------------------------|
| `_setup_selected_weapon()` | Missing entirely | Present - handles weapon swap |
| C# weapon signal connections | Missing entirely | Connects to AmmoChanged, MagazinesChanged, Fired, ShellCountChanged |
| `_on_weapon_ammo_changed()` | Missing entirely | Updates ammo label with color coding |
| `_on_magazines_changed()` | Missing entirely | Updates magazines label |
| `_on_shot_fired()` | Missing entirely | Registers shots for accuracy |
| `_on_shell_count_changed()` | Missing entirely | Updates ammo during shotgun reload |
| Reload/AmmoDepleted signals | Missing entirely | Notifies enemies of player vulnerability |
| `_update_ammo_label_magazine()` | Missing entirely | Magazine format display with color coding |
| `_update_magazines_label()` | Missing entirely | Individual magazine count display |
| `_show_death_message()` | Missing | Shows "YOU DIED" |
| `_show_game_over_message()` | Missing | Shows "OUT OF AMMO" |
| `_disable_player_controls()` | Missing | Stops player on level completion |
| Score screen with buttons | Used simple ScoreScreen.tscn | AnimatedScoreScreen with replay/restart/next buttons |

BeachLevel only attempted to connect to GDScript-style signals (`ammo_changed`, `magazine_changed`) which **don't exist on the C# Player**. The C# Player emits PascalCase signals (`AmmoChanged`, `MagazinesChanged`) from the weapon nodes, not from the player node directly.

### Evidence from Logs

In the log files, during BeachLevel loading:
```
[Player] Ready! Ammo: 9/9, Grenades: 1/3, Health: 4/4
```

Notice the **absence** of `[Player.Weapon] Equipped` log entries during early BeachLevel loads (before 17:56:34). This is because:
1. The C# Player's `ApplySelectedWeaponFromGameManager()` runs in `_Ready()`
2. But BeachLevel never calls `_setup_selected_weapon()` to handle the GDScript side
3. Without weapon signal connections, the AmmoLabel stays at its default value

In contrast, later BeachLevel loads (after the level restarted several times) show:
```
[Player.Weapon] Equipped AssaultRifle (ammo: 30/30)
[Player] Ready! Ammo: 30/30, Grenades: 1/3, Health: 4/4
```
The weapon equip happens via C# `_Ready()`, but the ammo label still never updates because the GDScript level script never connects to the weapon's AmmoChanged signal.

## Solution

Ported the complete weapon setup and signal connection infrastructure from BuildingLevel/CastleLevel to BeachLevel:

1. **Added `_setup_selected_weapon()`**: Handles weapon swap based on GameManager selection (all 6 weapon types)
2. **Rewrote `_setup_player_tracking()`**: Follows the exact pattern from other levels - finds weapon node, connects to all C# signals (AmmoChanged, MagazinesChanged, Fired, ShellCountChanged), sets initial ammo display
3. **Added all missing signal handlers**: `_on_weapon_ammo_changed`, `_on_magazines_changed`, `_on_shot_fired`, `_on_shell_count_changed`, `_on_player_ammo_depleted`, `_on_player_reload_started`, `_on_player_reload_completed`
4. **Added ammo display functions**: `_update_ammo_label`, `_update_ammo_label_magazine`, `_update_magazines_label` with color coding (red at <=5, yellow at <=10)
5. **Added missing UI**: death message, game over message, victory message, score screen with animated display and buttons
6. **Added missing game logic**: enemy hit tracking, died_with_info signal, player control disabling, broadcast functions for enemy aggression

## Lessons Learned

1. **Feature parity across levels**: When creating a new level, all existing functionality from other levels must be ported, not just the subset that seems obviously needed
2. **C# / GDScript signal naming mismatch**: C# uses PascalCase signals, GDScript uses snake_case - both must be checked with `has_signal()`
3. **Weapon signals come from weapon nodes, not the player**: The ammo signals are emitted by weapon child nodes (e.g., `Player/MakarovPM`), not by the player itself
4. **Log analysis**: The absence of `[Player.Weapon] Equipped` entries was a clue that weapon setup wasn't happening on the GDScript side
