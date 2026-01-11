# Godot Top-Down Template

A template project for creating top-down games in Godot 4.3+ with C# support.

## Requirements

- [Godot Engine 4.3 .NET](https://godotengine.org/download) or later (with C# support)
- [.NET SDK 6.0](https://dotnet.microsoft.com/download/dotnet/6.0) or later
- OpenGL 3.3 / OpenGL ES 3.0 compatible graphics (most systems from 2012+)

## Getting Started

1. Clone or download this repository
2. Open Godot Engine
3. Click "Import" and select the `project.godot` file
4. Press F5 to run the main scene

## Project Structure

```
godot-topdown-template/
├── project.godot          # Godot project configuration
├── GodotTopDownTemplate.csproj  # C# project file
├── GodotTopDownTemplate.sln     # Visual Studio solution
├── icon.svg               # Project icon
├── scenes/                # All game scenes (.tscn files)
│   ├── main/              # Main scenes
│   │   └── Main.tscn      # Main entry scene (runs on F5)
│   ├── levels/            # Game levels/tiers
│   │   └── TestTier.tscn  # Test level for development
│   ├── characters/        # Character scenes
│   │   └── Player.tscn    # Player character with movement (C#)
│   ├── projectiles/       # Projectile scenes
│   │   └── Bullet.tscn    # Bullet projectile (C#)
│   ├── objects/           # Game object scenes
│   │   └── Target.tscn    # Shootable target/enemy (C#)
│   └── ui/                # UI scenes
│       ├── PauseMenu.tscn # Pause menu with resume/controls/quit
│       └── ControlsMenu.tscn # Key rebinding interface
├── Scripts/               # C# scripts (.cs) - Main game logic
│   ├── Interfaces/        # C# interfaces for architecture
│   │   └── IDamageable.cs # Damage system interface
│   ├── AbstractClasses/   # Base abstract classes
│   │   ├── BaseCharacter.cs # Base class for all characters
│   │   └── BaseWeapon.cs    # Base class for weapons
│   ├── Components/        # Reusable components
│   │   └── HealthComponent.cs # Health management component
│   ├── Data/              # Data resources
│   │   ├── WeaponData.cs  # Weapon configuration resource
│   │   └── BulletData.cs  # Bullet configuration resource
│   ├── Characters/        # Character implementations
│   │   └── Player.cs      # Player character controller
│   ├── Projectiles/       # Projectile implementations
│   │   └── Bullet.cs      # Bullet projectile
│   └── Objects/           # Game objects
│       └── Enemy.cs       # Enemy/target implementation
├── scripts/               # GDScript files (.gd) - UI and utilities
│   ├── main.gd            # Main scene script
│   ├── levels/            # Level scripts
│   │   └── test_tier.gd   # Test tier script
│   ├── autoload/          # Autoload/singleton scripts
│   │   └── input_settings.gd # Input settings manager (singleton)
│   ├── ui/                # UI scripts
│   │   ├── pause_menu.gd  # Pause menu controller
│   │   └── controls_menu.gd # Key rebinding controller
│   └── utils/             # Utility scripts
├── assets/                # Game assets
│   ├── sprites/           # 2D sprites and textures
│   ├── audio/             # Sound effects and music
│   └── fonts/             # Custom fonts
└── addons/                # Third-party Godot plugins
```

## Architecture

This project uses a clean C# architecture following Godot best practices:

### Interfaces (`Scripts/Interfaces/`)

#### IDamageable
Interface for entities that can receive damage. Implement on any game object that should be able to take damage.

```csharp
public interface IDamageable
{
    float CurrentHealth { get; }
    float MaxHealth { get; }
    bool IsAlive { get; }
    void TakeDamage(float amount);
    void Heal(float amount);
    void OnDeath();
}
```

### Abstract Classes (`Scripts/AbstractClasses/`)

#### BaseCharacter
Base class for all characters (players, enemies, NPCs). Provides:
- Physics-based movement with acceleration/friction
- Health management via HealthComponent
- IDamageable implementation
- Damage/heal/death signals

#### BaseWeapon
Base class for all weapons. Provides:
- Ammunition management (magazine + reserve)
- Fire rate control
- Reload system
- Weapon signals (fired, reloading, ammo changed)

### Components (`Scripts/Components/`)

#### HealthComponent
Reusable component for health management. Attach to any node to give it health:
- Configurable max health and initial health
- Invulnerability toggle
- Damage/heal/health changed/died signals

### Data Resources (`Scripts/Data/`)

#### WeaponData
Resource for weapon configuration (save as `.tres` files):
- Damage, fire rate, magazine size
- Reload time, range, spread
- Automatic/semi-automatic mode

#### BulletData
Resource for bullet configuration:
- Speed, damage, lifetime
- Piercing, knockback, color

## Scenes

### Main.tscn
The main entry scene that loads when pressing F5. This is the starting point of the game and can be used to display menus or load other scenes.

### TestTier.tscn
A test level/tier (shooting range) for developing and testing game mechanics. This scene serves as a complete example of how to create a playable level with proper collision setup.

#### Features
- **Enclosed play area** with walls that prevent the player from leaving
- **Obstacles** placed within the arena for cover and movement testing
- **Target zone** with red shooting targets that react when hit
- **Shooting mechanics** - click to shoot bullets at targets
- **UI overlay** showing level name and control instructions

#### Scene Structure
```
TestTier
├── Environment
│   ├── Background      # Dark green background (1280x720)
│   ├── Floor           # Lighter green floor area
│   ├── Walls           # Brown walls with collision (StaticBody2D on layer 3)
│   │   ├── WallTop
│   │   ├── WallBottom
│   │   ├── WallLeft
│   │   └── WallRight
│   ├── Obstacles       # Brown obstacles with collision
│   │   ├── Obstacle1   # Square obstacle
│   │   ├── Obstacle2   # Square obstacle
│   │   └── Obstacle3   # Wide obstacle
│   ├── Targets         # Red target sprites (StaticBody2D)
│   │   ├── Target1
│   │   ├── Target2
│   │   └── Target3
│   └── TargetArea      # Label marking the target zone
├── Entities
│   └── Player          # Player instance at starting position
└── CanvasLayer
    └── UI              # HUD with level label and instructions
```

#### Collision Setup
- **Walls and Obstacles**: Use `collision_layer = 4` (layer 3: obstacles)
- **Player**: Uses `collision_mask = 4` to detect collisions with layer 3
- The player cannot pass through walls or obstacles

#### Running the Test Tier
To test the shooting range directly:
1. Open `scenes/levels/TestTier.tscn` in the Godot editor
2. Press F6 to run the current scene (or F5 if set as main scene)
3. Use WASD or Arrow Keys to move the player
4. Verify collision with walls and obstacles works correctly

### Player.tscn
The player character scene with smooth physics-based movement. Features:
- **CharacterBody2D** root node for physics-based movement
- **CollisionShape2D** with circular collision (16px radius)
- **Sprite2D** with placeholder texture (can be replaced with custom sprites)
- **Camera2D** that smoothly follows the player with configurable limits

#### Player Properties (Inspector)
| Property | Default | Description |
|----------|---------|-------------|
| `max_speed` | 200.0 | Maximum movement speed in pixels/second |
| `acceleration` | 1200.0 | How quickly the player reaches max speed |
| `friction` | 1000.0 | How quickly the player stops when not moving |

The player uses acceleration-based movement for smooth control without jitter. Diagonal movement is normalized to prevent faster diagonal speeds.

#### Shooting System
The player can shoot bullets towards the mouse cursor by clicking the left mouse button. The shooting system includes:
- **Bullet spawning** with offset from player center in the shooting direction
- **Automatic bullet scene loading** via preload
- **Direction calculation** towards mouse cursor position

### Bullet.tscn
A projectile scene for the shooting system. Features:
- **Area2D** root node for collision detection
- **CircleShape2D** for precise hit detection (4px radius)
- **Sprite2D** with yellow placeholder texture
- **Auto-destruction** after collision or lifetime timeout

#### Bullet Properties (Inspector)
| Property | Default | Description |
|----------|---------|-------------|
| `speed` | 600.0 | Bullet travel speed in pixels/second |
| `lifetime` | 3.0 | Maximum lifetime before auto-destruction |

#### Collision Setup
- **Layer**: 5 (projectiles)
- **Mask**: 3 (obstacles) + 6 (targets) - bullets detect walls and targets

### Target.tscn
A shootable target that reacts when hit by bullets. Features:
- **Area2D** root node for hit detection
- **Visual feedback** - changes color when hit (red to green)
- **Respawn system** - resets to original state after delay
- **Optional destruction** - can be configured to destroy on hit

#### Target Properties (Inspector)
| Property | Default | Description |
|----------|---------|-------------|
| `hit_color` | Green | Color when target is hit |
| `normal_color` | Red | Default target color |
| `destroy_on_hit` | false | Whether to destroy target when hit |
| `respawn_delay` | 2.0 | Delay before reset/destroy in seconds |

#### Collision Setup
- **Layer**: 6 (targets)
- **Mask**: 5 (projectiles) - targets detect bullets

### PauseMenu.tscn
A pause menu that appears when pressing Escape during gameplay. Features:
- **Resume** - Return to gameplay
- **Controls** - Open the key rebinding menu
- **Quit** - Exit the game
- Pauses the game tree when visible
- Works during gameplay in any level

### ControlsMenu.tscn
A key rebinding interface accessible from the pause menu. Features:
- **Action list** - Shows all remappable actions with current key bindings
- **Rebinding** - Click any action button and press a new key to reassign
- **Conflict detection** - Warns when a key is already assigned to another action
- **Apply/Reset/Back** - Save changes, reset to defaults, or return to pause menu
- **Persistent settings** - Key bindings are saved to `user://input_settings.cfg`

#### Remappable Actions
| Action | Default Key | Description |
|--------|-------------|-------------|
| Move Up | W | Move player upward |
| Move Down | S | Move player downward |
| Move Left | A | Move player left |
| Move Right | D | Move player right |
| Shoot | Left Mouse Button | Fire projectile towards cursor |
| Pause | Escape | Toggle pause menu |

#### Using the Controls Menu
1. Press Escape to open the pause menu
2. Click "Controls" to open the key rebinding menu
3. Click any action button to start rebinding
4. Press the desired new key (or Escape to cancel)
5. Click "Apply" to save changes
6. Click "Reset" to restore default bindings
7. Click "Back" to return to the pause menu

## Input Actions

The project includes pre-configured input actions for top-down movement:

| Action | Keys |
|--------|------|
| `move_up` | W, Up Arrow |
| `move_down` | S, Down Arrow |
| `move_left` | A, Left Arrow |
| `move_right` | D, Right Arrow |
| `shoot` | Left Mouse Button |
| `pause` | Escape |

## Physics Layers

Pre-configured collision layers for top-down games:

| Layer | Name | Purpose |
|-------|------|---------|
| 1 | player | Player character |
| 2 | enemies | Enemy characters |
| 3 | obstacles | Walls, barriers |
| 4 | pickups | Items, collectibles |
| 5 | projectiles | Bullets, spells |
| 6 | targets | Shooting targets |

## Best Practices

This template follows Godot best practices:

- **Snake_case naming** for files and folders
- **Scenes and scripts grouped together** or in parallel folder structures
- **Modular scene structure** with separate nodes for environment, entities, and UI
- **Input actions** instead of hardcoded key checks
- **Named collision layers** for clear physics setup

## Extending the Template

### Adding a New Character

1. Create a new C# class inheriting from `BaseCharacter`:

```csharp
using GodotTopDownTemplate.AbstractClasses;

public partial class MyEnemy : BaseCharacter
{
    public override void _PhysicsProcess(double delta)
    {
        // AI movement logic
        Vector2 direction = CalculateAIDirection();
        ApplyMovement(direction, (float)delta);
    }

    public override void OnDeath()
    {
        base.OnDeath();
        // Drop loot, play effects, etc.
        QueueFree();
    }
}
```

2. Create a scene in `scenes/characters/` with CharacterBody2D as root
3. Attach your script to the scene

### Adding a New Weapon

1. Create a weapon data resource (`weapons/pistol.tres`):
   - Right-click in FileSystem > New Resource > WeaponData
   - Configure damage, fire rate, magazine size, etc.

2. Create a weapon class if needed:

```csharp
using GodotTopDownTemplate.AbstractClasses;

public partial class Pistol : BaseWeapon
{
    // Override for custom behavior
    public override bool Fire(Vector2 direction)
    {
        if (base.Fire(direction))
        {
            // Play sound, muzzle flash, etc.
            return true;
        }
        return false;
    }
}
```

### Adding a Damageable Object

Implement IDamageable on any object:

```csharp
using GodotTopDownTemplate.Interfaces;

public partial class BreakableBox : StaticBody2D, IDamageable
{
    public float CurrentHealth { get; private set; } = 50;
    public float MaxHealth => 50;
    public bool IsAlive => CurrentHealth > 0;

    public void TakeDamage(float amount)
    {
        CurrentHealth -= amount;
        if (!IsAlive) OnDeath();
    }

    public void Heal(float amount) => CurrentHealth = Mathf.Min(MaxHealth, CurrentHealth + amount);

    public void OnDeath()
    {
        // Spawn debris, play effects
        QueueFree();
    }
}
```

### Adding a New Level
1. Create a new scene in `scenes/levels/`
2. Add a corresponding script in `scripts/levels/`
3. Follow the structure of `TestTier.tscn`

### Adding Autoloads
1. Create a script in `scripts/autoload/`
2. Go to Project > Project Settings > Autoload
3. Add the script as a singleton

## Building

To build the C# project:

```bash
dotnet build
```

Or in Godot:
1. Go to Project > Tools > C# > Create C# Solution (if not exists)
2. Build with Ctrl+Shift+B or via the Build menu

## License

See [LICENSE](LICENSE) for details.
