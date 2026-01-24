# Case Study: Issue #261 - Offensive Grenade Player Damage

## Issue Summary

**Issue Title:** fix наступательная граната (fix offensive grenade)
**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/261
**Issue Description (Russian):** наступательная граната должна наносить такой же урон игроку как и врагам.
**Translation:** The offensive grenade should deal the same damage to the player as it does to enemies.

## Timeline of Events

### Current State (Before Fix)
1. Player throws a frag grenade
2. Grenade explodes with 225 pixel effect radius
3. All enemies within radius take 99 damage (instant kill)
4. Player within radius takes **0 damage**

### Expected Behavior (After Fix)
1. Player throws a frag grenade
2. Grenade explodes with 225 pixel effect radius
3. All enemies within radius take 99 damage (instant kill)
4. **Player within radius also takes 99 damage (instant kill)**

## Root Cause Analysis

### Code Investigation

The issue is located in `scripts/projectiles/frag_grenade.gd`.

#### Key Finding 1: Enemy Targeting Only

In `_on_explode()` (line 141-153):
```gdscript
func _on_explode() -> void:
    # Find all enemies within effect radius and apply direct explosion damage
    var enemies := _get_enemies_in_radius()

    for enemy in enemies:
        _apply_explosion_damage(enemy)
    # ... rest of explosion handling
```

The explosion **only queries the "enemies" group** and does not check for the player.

#### Key Finding 2: Group-Based Targeting

In `_get_enemies_in_radius()` (line 206-218):
```gdscript
func _get_enemies_in_radius() -> Array:
    var enemies_in_range: Array = []
    # Get all enemies in the scene
    var enemies := get_tree().get_nodes_in_group("enemies")  # <-- ONLY "enemies" group!

    for enemy in enemies:
        if enemy is Node2D and is_in_effect_radius(enemy.global_position):
            if _has_line_of_sight_to(enemy):
                enemies_in_range.append(enemy)
    return enemies_in_range
```

The player is in the **"player" group**, not the "enemies" group, so they are never included in damage calculations.

#### Key Finding 3: Damage Application Method

In `_apply_explosion_damage()` (line 240-256):
```gdscript
func _apply_explosion_damage(enemy: Node2D) -> void:
    var final_damage := explosion_damage  # = 99

    if enemy.has_method("on_hit_with_info"):
        var hit_direction := (enemy.global_position - global_position).normalized()
        for i in range(final_damage):
            enemy.on_hit_with_info(hit_direction, null)
    elif enemy.has_method("on_hit"):
        for i in range(final_damage):
            enemy.on_hit()
```

The damage method calls `on_hit_with_info()` which **both player and enemies have**, so the fix only requires including the player in the target search.

#### Key Finding 4: Player Detection Already Exists

The grenade already has `_is_player_in_zone()` method (line 180-197) used for audio purposes:
```gdscript
func _is_player_in_zone() -> bool:
    var player: Node2D = null
    var players := get_tree().get_nodes_in_group("player")
    if players.size() > 0 and players[0] is Node2D:
        player = players[0] as Node2D
    # ... fallback logic
    return is_in_effect_radius(player.global_position)
```

This proves the grenade can locate the player - it just doesn't damage them.

## Comparison: Player vs Enemy Health Systems

| Aspect | Player (`player.gd`) | Enemy (`enemy.gd`) |
|--------|---------------------|-------------------|
| **Health Method** | `on_hit_with_info(hit_direction, caliber_data)` | `on_hit_with_info(hit_direction, caliber_data)` |
| **Damage Per Call** | 1 HP | 1 HP |
| **Max Health** | 5 HP | 2-4 HP (random) |
| **Group** | "player" | "enemies" |
| **Grenade Target?** | NO (before fix) | YES |

## Solution

### Fix Strategy

Modify `_on_explode()` in `frag_grenade.gd` to:
1. Check if player is within effect radius
2. Verify line of sight to player (same as enemies)
3. Apply same damage to player as enemies

### Code Change

Add player damage check after enemy damage loop in `_on_explode()`:

```gdscript
func _on_explode() -> void:
    # Find all enemies within effect radius and apply direct explosion damage
    var enemies := _get_enemies_in_radius()

    for enemy in enemies:
        _apply_explosion_damage(enemy)

    # Also damage the player if in blast radius (offensive grenade deals same damage to all)
    var player := _get_player_in_radius()
    if player != null:
        _apply_explosion_damage(player)

    # Spawn shrapnel in all directions
    _spawn_shrapnel()

    # Spawn visual explosion effect
    _spawn_explosion_effect()
```

Add helper method `_get_player_in_radius()`:

```gdscript
## Find the player if within the effect radius (for offensive grenade damage).
func _get_player_in_radius() -> Node2D:
    var player: Node2D = null

    # Check for player in "player" group
    var players := get_tree().get_nodes_in_group("player")
    if players.size() > 0 and players[0] is Node2D:
        player = players[0] as Node2D

    # Fallback: check for node named "Player" in current scene
    if player == null:
        var scene := get_tree().current_scene
        if scene:
            player = scene.get_node_or_null("Player") as Node2D

    if player == null:
        return null

    # Check if player is in effect radius
    if not is_in_effect_radius(player.global_position):
        return null

    # Check line of sight (player must be exposed to blast)
    if not _has_line_of_sight_to(player):
        return null

    return player
```

## Testing Verification

To verify the fix works:
1. Run the game and throw a frag grenade at player's feet
2. Player should die instantly (99 damage > 5 HP)
3. Throw grenade at mixed group (player + enemies)
4. All targets in radius should take damage
5. Throw grenade behind wall - player should NOT take damage (line of sight check)

## Files Modified

- `scripts/projectiles/frag_grenade.gd` - Added player damage in `_on_explode()` and new `_get_player_in_radius()` method

## Conclusion

The bug was caused by the grenade explosion only targeting entities in the "enemies" group while the player belongs to the "player" group. The fix adds player detection and applies the same damage calculation, ensuring offensive grenades deal equal damage to both player and enemies as intended.
