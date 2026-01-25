# Difficulty-Based Grenade Configuration

This document specifies how grenades should be distributed to enemies based on difficulty level.

## Requirements from Issue #363

> дай всем врагам на карте Здание на высокой сложности по 2 наступательные гранаты, а на обычной - по 1 светошумовой.

**Translation**:
> Give all enemies on the "Building" map on hard difficulty 2 offensive grenades each, and on normal difficulty - 1 flashbang each.

## Configuration Matrix

| Map | Difficulty | Grenade Type | Count |
|-----|------------|--------------|-------|
| Building | Easy | None | 0 |
| Building | Normal | Flashbang | 1 |
| Building | Hard | Frag (Offensive) | 2 |
| Other Maps | Any | TBD | TBD |

## Implementation Approach

### Option 1: Enemy Export Variables (Recommended)

Configure grenades per-enemy in the scene:

```gdscript
# In scripts/objects/enemy.gd

## Grenade inventory configuration
@export_group("Grenades")
@export var grenade_type: String = ""  # "frag", "flashbang", or ""
@export var grenade_count: int = 0
```

#### Pros:
- Granular control per enemy
- Easy to configure in Godot editor
- Can have mixed grenade types on same map

#### Cons:
- Must configure each enemy instance manually
- Easy to forget to set on new enemies

### Option 2: Map-Level Configuration

Use a dedicated configuration node in each level scene:

```gdscript
# scripts/levels/level_grenade_config.gd
class_name LevelGrenadeConfig
extends Node

@export var default_grenade_type: String = ""
@export var default_grenade_count: int = 0

## Difficulty overrides
@export var easy_grenade_type: String = ""
@export var easy_grenade_count: int = 0
@export var normal_grenade_type: String = "flashbang"
@export var normal_grenade_count: int = 1
@export var hard_grenade_type: String = "frag"
@export var hard_grenade_count: int = 2
```

#### Pros:
- Central configuration for entire map
- Easy to understand and modify
- Difficulty-aware by design

#### Cons:
- All enemies get same configuration
- Less flexible for mixed scenarios

### Option 3: DifficultyManager Extension (Recommended)

Extend the existing `DifficultyManager` with grenade configuration:

```gdscript
# In scripts/autoload/difficulty_manager.gd

## Get grenade type for a specific map.
## Returns empty string if no grenades for this difficulty/map.
func get_grenade_type_for_map(map_name: String) -> String:
    match map_name:
        "BuildingLevel":
            match current_difficulty:
                Difficulty.EASY:
                    return ""  # No grenades
                Difficulty.NORMAL:
                    return "flashbang"
                Difficulty.HARD:
                    return "frag"
        _:
            return ""  # Default: no grenades


## Get grenade count for a specific map.
func get_grenade_count_for_map(map_name: String) -> int:
    match map_name:
        "BuildingLevel":
            match current_difficulty:
                Difficulty.EASY:
                    return 0
                Difficulty.NORMAL:
                    return 1
                Difficulty.HARD:
                    return 2
        _:
            return 0
```

#### Pros:
- Centralized configuration in existing system
- Easy to add more maps
- Consistent with existing difficulty patterns

#### Cons:
- Hardcoded map names in code
- Requires code changes for new maps

### Option 4: Resource-Based Configuration (Most Flexible)

Create a resource for grenade configuration:

```gdscript
# scripts/data/grenade_config_resource.gd
class_name GrenadeConfigResource
extends Resource

@export var map_name: String = ""
@export var difficulty: int = 1  # 0=Easy, 1=Normal, 2=Hard
@export var grenade_type: String = ""
@export var grenade_count: int = 0
```

```gdscript
# scripts/autoload/difficulty_manager.gd

## Grenade configurations loaded from resources
var _grenade_configs: Array[GrenadeConfigResource] = []

func _ready() -> void:
    _load_grenade_configs()

func _load_grenade_configs() -> void:
    # Load all grenade config resources from a folder
    var dir := DirAccess.open("res://resources/grenade_configs/")
    if dir:
        dir.list_dir_begin()
        var file_name := dir.get_next()
        while file_name != "":
            if file_name.ends_with(".tres"):
                var config := load("res://resources/grenade_configs/" + file_name)
                if config is GrenadeConfigResource:
                    _grenade_configs.append(config)
            file_name = dir.get_next()

func get_grenade_config_for_map(map_name: String) -> Dictionary:
    for config in _grenade_configs:
        if config.map_name == map_name and config.difficulty == current_difficulty:
            return {
                "type": config.grenade_type,
                "count": config.grenade_count
            }
    return {"type": "", "count": 0}
```

#### Pros:
- Data-driven, no code changes for new maps
- Easy for designers to modify
- Can be version-controlled separately

#### Cons:
- More complex setup
- Additional resource files to manage

---

## Recommended Implementation

**Use Option 3 (DifficultyManager Extension)** for initial implementation, with ability to migrate to Option 4 later if more maps are added.

### Implementation Steps

1. **Add grenade configuration to DifficultyManager**:
```gdscript
# scripts/autoload/difficulty_manager.gd

## Building map grenade configuration
const BUILDING_GRENADES := {
    Difficulty.EASY: {"type": "", "count": 0},
    Difficulty.NORMAL: {"type": "flashbang", "count": 1},
    Difficulty.HARD: {"type": "frag", "count": 2}
}

func get_grenade_config(map_name: String) -> Dictionary:
    match map_name:
        "BuildingLevel":
            return BUILDING_GRENADES.get(current_difficulty, {"type": "", "count": 0})
        _:
            return {"type": "", "count": 0}
```

2. **Enemy initialization uses DifficultyManager**:
```gdscript
# In scripts/objects/enemy.gd _ready()

func _ready() -> void:
    # ... existing code ...

    # Initialize grenades based on difficulty
    _init_grenades()

func _init_grenades() -> void:
    var difficulty_manager := get_node_or_null("/root/DifficultyManager")
    if not difficulty_manager:
        return

    # Get current level name
    var level_name := get_tree().current_scene.name

    # Get grenade configuration
    var config := difficulty_manager.get_grenade_config(level_name)
    _grenade_type = config.get("type", "")
    _grenade_count = config.get("count", 0)

    if _grenade_count > 0:
        _world_state["has_grenades"] = true
        _world_state["grenade_type"] = _grenade_type
        _world_state["grenade_count"] = _grenade_count
```

3. **Create grenade inventory component** (optional, for better organization):
```gdscript
# scripts/components/grenade_inventory_component.gd
class_name GrenadeInventoryComponent
extends Node

signal grenade_thrown(grenade_type: String)
signal grenades_depleted()

var grenade_type: String = ""
var grenade_count: int = 0

func _ready() -> void:
    _init_from_difficulty()

func _init_from_difficulty() -> void:
    var difficulty_manager := get_node_or_null("/root/DifficultyManager")
    if not difficulty_manager:
        return

    var level_name := get_tree().current_scene.name
    var config := difficulty_manager.get_grenade_config(level_name)
    grenade_type = config.get("type", "")
    grenade_count = config.get("count", 0)

func has_grenades() -> bool:
    return grenade_count > 0 and grenade_type != ""

func use_grenade() -> String:
    if not has_grenades():
        return ""

    grenade_count -= 1
    grenade_thrown.emit(grenade_type)

    if grenade_count <= 0:
        grenades_depleted.emit()

    return grenade_type

func get_grenade_type() -> String:
    return grenade_type

func get_grenade_count() -> int:
    return grenade_count
```

---

## Testing Considerations

### Unit Tests

```gdscript
# tests/unit/test_grenade_config.gd

func test_building_easy_no_grenades() -> void:
    DifficultyManager.set_difficulty(DifficultyManager.Difficulty.EASY)
    var config := DifficultyManager.get_grenade_config("BuildingLevel")
    assert_eq(config.type, "")
    assert_eq(config.count, 0)

func test_building_normal_one_flashbang() -> void:
    DifficultyManager.set_difficulty(DifficultyManager.Difficulty.NORMAL)
    var config := DifficultyManager.get_grenade_config("BuildingLevel")
    assert_eq(config.type, "flashbang")
    assert_eq(config.count, 1)

func test_building_hard_two_frag() -> void:
    DifficultyManager.set_difficulty(DifficultyManager.Difficulty.HARD)
    var config := DifficultyManager.get_grenade_config("BuildingLevel")
    assert_eq(config.type, "frag")
    assert_eq(config.count, 2)

func test_unknown_map_no_grenades() -> void:
    var config := DifficultyManager.get_grenade_config("UnknownMap")
    assert_eq(config.type, "")
    assert_eq(config.count, 0)
```

### Integration Tests

```gdscript
# tests/integration/test_enemy_grenades.gd

func test_enemy_initializes_grenades_on_building_hard() -> void:
    DifficultyManager.set_difficulty(DifficultyManager.Difficulty.HARD)
    var enemy := _create_enemy_on_building_map()

    assert_true(enemy.has_grenades())
    assert_eq(enemy.get_grenade_type(), "frag")
    assert_eq(enemy.get_grenade_count(), 2)

func test_enemy_no_grenades_on_building_easy() -> void:
    DifficultyManager.set_difficulty(DifficultyManager.Difficulty.EASY)
    var enemy := _create_enemy_on_building_map()

    assert_false(enemy.has_grenades())
```
