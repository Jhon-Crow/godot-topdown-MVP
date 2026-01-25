# GOAP Actions for Enemy Grenade Throwing

This document defines the GOAP actions required for implementing enemy grenade throwing behavior.

## Proposed Action Hierarchy

```
GrenadeActions
├── PrepareGrenadeAction (activates grenade mode)
├── ThrowFragGrenadeAction (offensive grenade)
├── ThrowFlashbangAction (defensive/stun grenade)
├── ThrowGrenadeAtSoundAction (sound-targeted throw)
└── DesperationGrenadeAction (low health desperation)
```

## Action 1: PrepareGrenadeAction

**Purpose**: Transition to "ready to throw grenade" mode based on trigger conditions.

```gdscript
class PrepareGrenadeAction extends GOAPAction:
    func _init() -> void:
        super._init("prepare_grenade", 0.3)
        preconditions = {
            "has_grenades": true,
            "ready_to_throw_grenade": false  # Not already in throw mode
        }
        effects = {
            "ready_to_throw_grenade": true
        }

    func get_cost(_agent: Node, world_state: Dictionary) -> float:
        # Priority based on trigger conditions (lower = higher priority)
        if world_state.get("trigger_6_desperation", false):
            return 0.05  # Highest priority - dying

        if world_state.get("trigger_4_sound_based", false):
            return 0.15  # High priority - vulnerable player

        if world_state.get("trigger_2_pursuit", false):
            return 0.2  # Being chased

        if world_state.get("trigger_3_witness_kills", false):
            return 0.25  # Saw teammates die

        if world_state.get("trigger_5_sustained_fire", false):
            return 0.3  # Area denial

        if world_state.get("trigger_1_suppression_hidden", false):
            return 0.35  # Flush out

        # No trigger condition met
        return 1000.0

    func is_valid(world_state: Dictionary) -> bool:
        if not super.is_valid(world_state):
            return false

        # At least one trigger condition must be met
        return world_state.get("trigger_1_suppression_hidden", false) or \
               world_state.get("trigger_2_pursuit", false) or \
               world_state.get("trigger_3_witness_kills", false) or \
               world_state.get("trigger_4_sound_based", false) or \
               world_state.get("trigger_5_sustained_fire", false) or \
               world_state.get("trigger_6_desperation", false)
```

## Action 2: ThrowFragGrenadeAction

**Purpose**: Throw an offensive (frag) grenade at suspected player position.

```gdscript
class ThrowFragGrenadeAction extends GOAPAction:
    func _init() -> void:
        super._init("throw_frag_grenade", 0.5)
        preconditions = {
            "ready_to_throw_grenade": true,
            "grenade_type": "frag",
            "has_target_position": true
        }
        effects = {
            "grenade_thrown": true,
            "ready_to_throw_grenade": false,
            "grenade_count_reduced": true
        }

    func get_cost(_agent: Node, world_state: Dictionary) -> float:
        # Lower cost if player is in cover (grenade is more effective)
        if world_state.get("player_in_cover", false):
            return 0.3

        # Higher cost if player is moving (harder to hit)
        if world_state.get("player_moving_fast", false):
            return 0.8

        return 0.5

    func execute(agent: Node, _world_state: Dictionary) -> void:
        if agent.has_method("throw_grenade_at_target"):
            agent.throw_grenade_at_target("frag")
```

## Action 3: ThrowFlashbangAction

**Purpose**: Throw a flashbang (stun) grenade to blind and stun the player.

```gdscript
class ThrowFlashbangAction extends GOAPAction:
    func _init() -> void:
        super._init("throw_flashbang", 0.6)
        preconditions = {
            "ready_to_throw_grenade": true,
            "grenade_type": "flashbang",
            "has_target_position": true
        }
        effects = {
            "grenade_thrown": true,
            "ready_to_throw_grenade": false,
            "player_potentially_blinded": true
        }

    func get_cost(_agent: Node, world_state: Dictionary) -> float:
        # Lower cost if player is visible (better chance to blind)
        if world_state.get("player_visible", false):
            return 0.4

        # Slightly higher cost than frag since it doesn't deal damage
        return 0.6

    func execute(agent: Node, _world_state: Dictionary) -> void:
        if agent.has_method("throw_grenade_at_target"):
            agent.throw_grenade_at_target("flashbang")
```

## Action 4: ThrowGrenadeAtSoundAction

**Purpose**: Throw grenade toward heard reload/empty click sound when player is not visible.

```gdscript
class ThrowGrenadeAtSoundAction extends GOAPAction:
    func _init() -> void:
        super._init("throw_grenade_at_sound", 0.4)
        preconditions = {
            "has_grenades": true,
            "trigger_4_sound_based": true,
            "player_visible": false,
            "has_sound_position": true
        }
        effects = {
            "grenade_thrown": true,
            "sound_position_attacked": true
        }

    func get_cost(_agent: Node, world_state: Dictionary) -> float:
        # Lower cost for fresher sounds (more likely player is still there)
        var sound_age: float = world_state.get("sound_age", 5.0)
        if sound_age < 1.0:
            return 0.2  # Very fresh sound
        elif sound_age < 3.0:
            return 0.4
        else:
            return 0.7  # Older sound, player may have moved

    func execute(agent: Node, _world_state: Dictionary) -> void:
        if agent.has_method("throw_grenade_at_sound_source"):
            agent.throw_grenade_at_sound_source()
```

## Action 5: DesperationGrenadeAction

**Purpose**: Last-resort grenade throw when health is critically low.

```gdscript
class DesperationGrenadeAction extends GOAPAction:
    func _init() -> void:
        super._init("desperation_grenade", 0.1)  # Very low cost = high priority
        preconditions = {
            "has_grenades": true,
            "trigger_6_desperation": true
        }
        effects = {
            "grenade_thrown": true,
            "desperation_attack_used": true
        }

    func get_cost(_agent: Node, world_state: Dictionary) -> float:
        # Always highest priority when dying
        if world_state.get("health_critical", false):
            return 0.05  # Absolute priority

        return 1000.0  # Disabled if not dying

    func is_valid(world_state: Dictionary) -> bool:
        # Only valid when health is 1 or less
        var health: int = world_state.get("current_health", 99)
        return super.is_valid(world_state) and health <= 1

    func execute(agent: Node, _world_state: Dictionary) -> void:
        if agent.has_method("throw_desperation_grenade"):
            agent.throw_desperation_grenade()
```

---

## Integration with Existing Actions

### Modified EnemyActions.create_all_actions()

```gdscript
static func create_all_actions() -> Array[GOAPAction]:
    var actions: Array[GOAPAction] = []

    # Existing actions
    actions.append(SeekCoverAction.new())
    actions.append(EngagePlayerAction.new())
    actions.append(FlankPlayerAction.new())
    actions.append(PatrolAction.new())
    actions.append(StaySuppressedAction.new())
    actions.append(ReturnFireAction.new())
    actions.append(FindCoverAction.new())
    actions.append(RetreatAction.new())
    actions.append(RetreatWithFireAction.new())
    actions.append(PursuePlayerAction.new())
    actions.append(AssaultPlayerAction.new())  # Disabled
    actions.append(AttackDistractedPlayerAction.new())
    actions.append(AttackVulnerablePlayerAction.new())
    actions.append(PursueVulnerablePlayerAction.new())
    actions.append(InvestigateHighConfidenceAction.new())
    actions.append(InvestigateMediumConfidenceAction.new())
    actions.append(SearchLowConfidenceAction.new())

    # NEW: Grenade actions (Issue #363)
    actions.append(PrepareGrenadeAction.new())
    actions.append(ThrowFragGrenadeAction.new())
    actions.append(ThrowFlashbangAction.new())
    actions.append(ThrowGrenadeAtSoundAction.new())
    actions.append(DesperationGrenadeAction.new())

    return actions
```

---

## World State Requirements

### New World State Variables

```gdscript
# Grenade inventory
"has_grenades": bool              # Has at least one grenade
"grenade_count": int              # Number of grenades remaining
"grenade_type": String            # "frag" or "flashbang"

# Grenade mode
"ready_to_throw_grenade": bool    # In grenade throwing mode

# Target tracking
"has_target_position": bool       # Has a valid target for grenade
"has_sound_position": bool        # Has sound-based target
"sound_age": float                # Age of last sound in seconds

# Trigger states (from trigger-conditions.md)
"trigger_1_suppression_hidden": bool
"trigger_2_pursuit": bool
"trigger_3_witness_kills": bool
"trigger_4_sound_based": bool
"trigger_5_sustained_fire": bool
"trigger_6_desperation": bool

# Health (already exists)
"health_critical": bool           # Health <= 1
"current_health": int             # Current HP

# Player state (may already exist)
"player_in_cover": bool           # Player is behind cover
"player_moving_fast": bool        # Player is moving quickly
```

---

## Action Cost Comparison

| Action | Base Cost | Condition-adjusted Range |
|--------|-----------|--------------------------|
| DesperationGrenadeAction | 0.1 | 0.05 (dying) |
| AttackDistractedPlayerAction | 0.1 | 0.05 (existing) |
| AttackVulnerablePlayerAction | 0.1 | 0.05 (existing) |
| ThrowGrenadeAtSoundAction | 0.4 | 0.2-0.7 |
| PrepareGrenadeAction | 0.3 | 0.05-0.35 |
| ThrowFragGrenadeAction | 0.5 | 0.3-0.8 |
| ThrowFlashbangAction | 0.6 | 0.4-0.6 |
| EngagePlayerAction | 1.0 | 0.5-2.0 |
| PursuePlayerAction | 2.5 | 1.5-3.0 |

The cost hierarchy ensures:
1. Desperation grenades are highest priority when dying
2. Sound-based grenades are high priority (time-sensitive)
3. Grenades are generally preferred over pursuit/flanking when available
4. Standard engagement is still viable when grenades aren't optimal

---

## Execution Flow

### Typical Grenade Throw Sequence

1. **Trigger condition met** → World state updated
2. **GOAP planner runs** → Selects `PrepareGrenadeAction`
3. **World state updated** → `ready_to_throw_grenade = true`
4. **GOAP planner runs again** → Selects appropriate throw action
5. **Throw action executes** → Grenade instantiated and thrown
6. **World state updated** → `grenade_count -= 1`, `grenade_thrown = true`

### Enemy Method Requirements

```gdscript
# Required methods in enemy.gd for grenade actions

func throw_grenade_at_target(grenade_type: String) -> void:
    # Calculate target position from memory/visibility
    # Instantiate appropriate grenade
    # Calculate throw trajectory
    # Execute throw

func throw_grenade_at_sound_source() -> void:
    # Use stored sound position as target
    # Same throw logic as above

func throw_desperation_grenade() -> void:
    # Throw at player's last known position or current position if visible
    # May have reduced accuracy due to desperation
```
