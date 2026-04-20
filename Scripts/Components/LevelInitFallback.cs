using Godot;
using System;
using System.Collections.Generic;
using GodotTopDownTemplate.Components;
using GodotTopDownTemplate.Weapons;

/// <summary>
/// C# fallback for level initialization when GDScript level scripts fail to execute
/// due to Godot 4.3 binary tokenization bug (godotengine/godot#94150).
///
/// This component is added as a child node in level scenes (e.g., TestTier.tscn).
/// It waits for the scene tree to be ready, then checks if the GDScript _ready()
/// already ran. If not, it performs critical initialization:
/// - Enemy tracking (died signals → counter)
/// - Night mode (RealisticVisibilityComponent)
/// - Score manager initialization
/// - UI setup (enemy count, ammo labels)
/// - Exit zone creation
/// - GameManager signal connections
/// - Replay recording
/// - Navigation mesh baking (Issue #1289)
/// </summary>
public partial class LevelInitFallback : Node
{
    /// <summary>
    /// List of tracked enemy nodes for replay recording and position tracking.
    /// </summary>
    private readonly List<Node> _enemies = new();

    /// <summary>
    /// Current enemy count (decrements on death).
    /// </summary>
    private int _currentEnemyCount;

    /// <summary>
    /// Initial enemy count at level start.
    /// </summary>
    private int _initialEnemyCount;

    /// <summary>
    /// Reference to the player node.
    /// </summary>
    private Node2D? _player;

    /// <summary>
    /// Reference to the enemy count label in UI.
    /// </summary>
    private Label? _enemyCountLabel;

    /// <summary>
    /// Reference to the ammo label in UI.
    /// </summary>
    private Label? _ammoLabel;

    /// <summary>
    /// Whether the level has been cleared (all enemies eliminated).
    /// </summary>
    private bool _levelCleared;

    /// <summary>
    /// Reference to the exit zone.
    /// </summary>
    private Area2D? _exitZone;

    /// <summary>
    /// Whether this fallback actually performed initialization (GDScript didn't run).
    /// </summary>
    private bool _didInitialize;

    /// <summary>
    /// Whether the score screen has been shown.
    /// </summary>
    private bool _scoreShown;

    /// <summary>
    /// Issue #1334: Guard against duplicate death handling.
    /// Prevents re-entrant OnPlayerDied calls and stale timer callbacks.
    /// </summary>
    private bool _isDying;

    /// <summary>
    /// Prevents duplicate out-of-ammo overlays when the empty-click signal fires repeatedly.
    /// </summary>
    private bool _gameOverShown;

    /// <summary>
    /// Saturation overlay for kill effects.
    /// </summary>
    private ColorRect? _saturationOverlay;

    /// <summary>
    /// Difficulty label for UI (Issue #1485: replaces old KillsLabel + AccuracyLabel).
    /// </summary>
    private Label? _difficultyLabel;

    /// <summary>
    /// Magazines label for UI.
    /// </summary>
    private Label? _magazinesLabel;

    /// <summary>
    /// Last magazine counts received from the current weapon, used to rebuild localized text on locale changes.
    /// </summary>
    private Godot.Collections.Array _lastMagazineAmmoCounts = new();

    /// <summary>
    /// Combo label for UI (Issue #1751: shows current combo count).
    /// </summary>
    private Label? _comboLabel;

    /// <summary>
    /// Shared weapon hints component used on non-tutorial combat maps (Issue #1810).
    /// This must also be initialized by the fallback path when the GDScript level
    /// _ready() failed to execute, otherwise Building loses its onboarding hints.
    /// </summary>
    private Node? _weaponHintsComponent;

    /// <summary>
    /// Active combo tween (to cancel if needed, Issue #1790).
    /// </summary>
    private Tween? _comboTween;

    /// <summary>
    /// Revolver cylinder HUD display (Issue #691).
    /// Shows 5 cylinder slots with color-coded active chamber.
    /// </summary>
    private RevolverCylinderUI? _cylinderUI;

    public override void _Ready()
    {
        // Use CallDeferred to run after all other _Ready() methods complete
        // This gives GDScript _ready() a chance to execute first
        CallDeferred(MethodName.CheckAndInitialize);
    }

    /// <summary>
    /// Check if GDScript _ready() already ran. If not, perform fallback initialization.
    /// Detection: If GDScript ran, it would have printed "Полигон loaded" and connected
    /// enemy signals. We check by looking for signs of initialization.
    /// </summary>
    private void CheckAndInitialize()
    {
        var parent = GetParent();
        if (parent == null) return;

        // Apply camera limits for maps known to use this fallback, regardless of
        // whether GDScript ran. This is a safety net: the GDScript _configure_camera()
        // may fail silently in exported builds (Issue #1684).
        if (parent.Name == "BuildingLevel")
            ConfigureBuildingCameraLimits();
        else if (parent.Name == "Labyrinth2Level")
            ConfigureLabyrinth2CameraLimits();

        // Check if GDScript _ready() already ran by checking if it set up enemy tracking.
        // The GDScript sets _enemies array and connects died signals.
        // We can detect this by checking if the parent has the _enemies property populated.
        var enemiesVar = parent.Get("_enemies");

        // If _enemies array exists and has entries, GDScript ran successfully
        if (enemiesVar.VariantType == Variant.Type.Array)
        {
            var enemiesArray = enemiesVar.AsGodotArray();
            if (enemiesArray.Count > 0)
            {
                LogToFile("GDScript _ready() already ran (enemies tracked: " + enemiesArray.Count + ") - skipping fallback");
                return;
            }
        }

        // Also check if _initial_enemy_count was set (another indicator)
        var initialCount = parent.Get("_initial_enemy_count");
        if (initialCount.VariantType == Variant.Type.Int && initialCount.AsInt32() > 0)
        {
            LogToFile("GDScript _ready() already ran (initial_enemy_count: " + initialCount.AsInt32() + ") - skipping fallback");
            return;
        }

        // Check if GDScript created an exit zone (works for zero-enemy levels like RailwayStation).
        // GDScript sets _exit_zone in _setup_exit_zone() which always runs in _ready().
        var exitZoneVar = parent.Get("_exit_zone");
        if (exitZoneVar.VariantType != Variant.Type.Nil && exitZoneVar.AsGodotObject() != null)
        {
            LogToFile("GDScript _ready() already ran (_exit_zone is set) - skipping fallback");
            return;
        }

        // GDScript didn't run - perform fallback initialization
        LogToFile("GDScript _ready() did NOT execute - performing C# fallback initialization");
        _didInitialize = true;
        PerformFallbackInit();
    }

    /// <summary>
    /// Set Camera2D limits for the Building map to prevent the camera from scrolling
    /// past the right and bottom border walls into the void area (Issue #1684).
    ///
    /// This runs unconditionally — even when GDScript _ready() already ran — because
    /// the GDScript _configure_camera() may fail silently if it cannot find Camera2D
    /// on the player node at runtime.
    ///
    /// Wall geometry (from BuildingLevel.tscn):
    ///   WallRight  position=(2480, 1064), half-w=16 → left edge  x=2464 → limit_right  = 2464
    ///   WallBottom position=(1264, 2080), half-h=16 → top edge   y=2064 → limit_bottom = 2064
    ///   WallLeft   position=(  48, 1064), half-w=16 → right edge x=64   → limit_left   = 64
    ///   WallTop    position=(1264,   48), half-h=16 → bottom edge y=64  → limit_top    = 64
    /// </summary>
    private void ConfigureBuildingCameraLimits()
    {
        var levelRoot = GetParent();
        if (levelRoot == null) return;

        var player = levelRoot.GetNodeOrNull<Node2D>("Entities/Player");
        if (player == null)
        {
            LogToFile("WARNING: ConfigureBuildingCameraLimits: Player not found at Entities/Player");
            return;
        }

        var camera = player.GetNodeOrNull<Camera2D>("Camera2D");
        if (camera == null)
        {
            LogToFile("WARNING: ConfigureBuildingCameraLimits: Camera2D not found on player");
            return;
        }

        camera.LimitLeft   =   64;  // WallLeft right edge  (x=48+16)
        camera.LimitTop    =   64;  // WallTop bottom edge  (y=48+16)
        camera.LimitRight  = 2464;  // WallRight left edge  (x=2480-16)
        camera.LimitBottom = 2064;  // WallBottom top edge  (y=2080-16)

        LogToFile($"ConfigureBuildingCameraLimits: limits set — left={camera.LimitLeft} top={camera.LimitTop} right={camera.LimitRight} bottom={camera.LimitBottom} — Issue #1684");
    }

    /// <summary>
    /// Set Camera2D limits for Labyrinth Complex when GDScript initialization is skipped.
    /// Matches scripts/levels/labyrinth2_level.gd.
    /// </summary>
    private void ConfigureLabyrinth2CameraLimits()
    {
        var levelRoot = GetParent();
        if (levelRoot == null) return;

        var player = levelRoot.GetNodeOrNull<Node2D>("Entities/Player");
        if (player == null)
        {
            LogToFile("WARNING: ConfigureLabyrinth2CameraLimits: Player not found at Entities/Player");
            return;
        }

        var camera = player.GetNodeOrNull<Camera2D>("Camera2D");
        if (camera == null)
        {
            LogToFile("WARNING: ConfigureLabyrinth2CameraLimits: Camera2D not found on player");
            return;
        }

        camera.LimitLeft = 64;
        camera.LimitTop = 64;
        camera.LimitRight = 3264;
        camera.LimitBottom = 2464;

        LogToFile($"ConfigureLabyrinth2CameraLimits: limits set — left={camera.LimitLeft} top={camera.LimitTop} right={camera.LimitRight} bottom={camera.LimitBottom} — Issue #1682");
    }

    /// <summary>
    /// Perform the critical level initialization that GDScript _ready() should have done.
    /// </summary>
    private void PerformFallbackInit()
    {
        var levelRoot = GetParent();
        if (levelRoot == null) return;

        LogToFile("Полигон loaded (C# fallback) - Tactical Combat Arena");

        // 1. Setup enemy tracking
        SetupEnemyTracking(levelRoot);

        // 2. Find and setup player
        SetupPlayerTracking(levelRoot);

        // 3. Find UI labels
        _enemyCountLabel = levelRoot.GetNodeOrNull<Label>("CanvasLayer/UI/EnemyCountLabel");
        UpdateEnemyCountLabel();

        // 4. Setup debug UI (kills, accuracy, magazines labels)
        SetupDebugUI(levelRoot);
        var currentWeapon = GetCurrentWeaponNode();
        if (currentWeapon != null)
            RefreshWeaponHud(currentWeapon, "post fallback debug UI setup");

        // 5. Setup saturation overlay
        SetupSaturationOverlay(levelRoot);

        // 6. Connect to GameManager signals
        var gameManager = GetNodeOrNull("/root/GameManager");
        if (gameManager != null)
        {
            if (gameManager.HasSignal("enemy_killed"))
            {
                gameManager.Connect("enemy_killed", new Callable(this, MethodName.OnGameManagerEnemyKilled));
            }
            if (gameManager.HasSignal("stats_updated"))
            {
                gameManager.Connect("stats_updated", new Callable(this, MethodName.UpdateDebugUI));
            }
        }

        var localizationSettings = GetNodeOrNull("/root/LocalizationSettings");
        if (localizationSettings != null &&
            localizationSettings.HasSignal("locale_changed") &&
            !localizationSettings.IsConnected("locale_changed", new Callable(this, MethodName.OnLocaleChanged)))
        {
            localizationSettings.Connect("locale_changed", new Callable(this, MethodName.OnLocaleChanged));
        }

        // 7. Initialize ScoreManager
        InitializeScoreManager();

        // 8. Setup exit zone
        SetupExitZone(levelRoot);

        // 9. Start replay recording
        StartReplayRecording(levelRoot);

        // 10. Setup shared weapon hints component (Issue #1810).
        SetupWeaponHints(levelRoot);

        // 11. Update GDScript properties so they are in sync
        SyncGDScriptProperties(levelRoot);

        // 12. Setup warm ceiling lights (Issue #1206) — mirrors GDScript _setup_room_warm_lights()
        SetupRoomWarmLights(levelRoot);

        // 13. Setup navigation mesh (Issue #1289) — mirrors GDScript _setup_navigation()
        // Must run after physics frame so CollisionShape2D nodes are registered.
        SetupNavigationDeferred(levelRoot);

        RefreshLocalizedHudLabels();
    }

    /// <summary>
    /// Find and connect to all enemies in the scene.
    /// </summary>
    private void SetupEnemyTracking(Node levelRoot)
    {
        var enemiesNode = levelRoot.GetNodeOrNull("Environment/Enemies");
        if (enemiesNode == null)
        {
            LogToFile("WARNING: Environment/Enemies node not found");
            return;
        }

        LogToFile($"Found Environment/Enemies node with {enemiesNode.GetChildCount()} children");

        _enemies.Clear();
        foreach (var child in enemiesNode.GetChildren())
        {
            var hasDiedSignal = child.HasSignal("died");
            LogToFile($"Child '{child.Name}': has_died_signal={hasDiedSignal}");

            if (hasDiedSignal)
            {
                _enemies.Add(child);
                child.Connect("died", new Callable(this, MethodName.OnEnemyDied));

                // Connect to died_with_info for score tracking if available
                if (child.HasSignal("died_with_info"))
                {
                    child.Connect("died_with_info", new Callable(this, MethodName.OnEnemyDiedWithInfo));
                }
            }

            // Track when enemy is hit for accuracy
            if (child.HasSignal("hit"))
            {
                child.Connect("hit", new Callable(this, MethodName.OnEnemyHit));
            }
        }

        _initialEnemyCount = _enemies.Count;
        _currentEnemyCount = _initialEnemyCount;
        LogToFile($"Enemy tracking complete: {_initialEnemyCount} enemies registered");
    }

    /// <summary>
    /// Find the player and setup tracking, weapon signals, night mode.
    /// </summary>
    private void SetupPlayerTracking(Node levelRoot)
    {
        _player = levelRoot.GetNodeOrNull<Node2D>("Entities/Player");
        if (_player == null)
        {
            LogToFile("WARNING: Player not found at Entities/Player");
            return;
        }

        // Setup realistic visibility (night mode)
        SetupRealisticVisibility();

        // Register player with GameManager
        var gameManager = GetNodeOrNull("/root/GameManager");
        if (gameManager != null && gameManager.HasMethod("set_player"))
        {
            gameManager.Call("set_player", _player);
        }

        // Find ammo label
        _ammoLabel = levelRoot.GetNodeOrNull<Label>("CanvasLayer/UI/AmmoLabel");

        // Connect to player death signal
        if (_player.HasSignal("Died"))
        {
            _player.Connect("Died", new Callable(this, MethodName.OnPlayerDied));
        }
        else if (_player.HasSignal("died"))
        {
            _player.Connect("died", new Callable(this, MethodName.OnPlayerDied));
        }

        // Connect weapon signals
        ConnectWeaponSignals();

        // Connect reload/ammo signals
        ConnectReloadSignals();
    }

    /// <summary>
    /// Connect to the current weapon's signals for ammo tracking.
    /// </summary>
    private void ConnectWeaponSignals()
    {
        if (_player == null) return;

        var weapon = GetCurrentWeaponNode();
        if (weapon == null) return;

        if (weapon.HasSignal("AmmoChanged"))
            weapon.Connect("AmmoChanged", new Callable(this, MethodName.OnWeaponAmmoChanged));
        if (weapon.HasSignal("MagazinesChanged"))
            weapon.Connect("MagazinesChanged", new Callable(this, MethodName.OnMagazinesChanged));
        if (weapon.HasSignal("Fired"))
            weapon.Connect("Fired", new Callable(this, MethodName.OnShotFired));
        if (weapon.HasSignal("ShellCountChanged"))
            weapon.Connect("ShellCountChanged", new Callable(this, MethodName.OnShellCountChanged));

        RefreshWeaponHud(weapon, "fallback initial weapon setup");

        // Issue #691: Setup revolver cylinder HUD when revolver is equipped
        if (weapon is Revolver revolver)
        {
            SetupRevolverCylinderUI(revolver);
        }

        ApplySilencedPistolAmmoConfig(weapon);
        ApplyMakarovPmAmmoConfig(weapon);
        ApplyLevelSpecificAmmoConfig(weapon);

        if (_player.HasMethod("ApplyAutoReloadAfterLevelAmmoConfig"))
        {
            _player.Call("ApplyAutoReloadAfterLevelAmmoConfig");
            LogToFile($"Re-applied auto-reload magazine reduction after fallback ammo config for {weapon.Name}");
        }

        RefreshWeaponHud(weapon, "post fallback level ammo config");
    }

    /// <summary>
    /// Return the player's authoritative current weapon. C# Player.CurrentWeapon is
    /// preferred; child-node probing is only a fallback for older scenes.
    /// </summary>
    private Node? GetCurrentWeaponNode()
    {
        if (_player == null) return null;

        var currentWeaponValue = _player.Get("CurrentWeapon");
        if (currentWeaponValue.Obj is Node currentWeapon && IsInstanceValid(currentWeapon))
            return currentWeapon;

        var selectedWeaponNodeName = GetSelectedWeaponNodeName();
        if (!string.IsNullOrEmpty(selectedWeaponNodeName))
        {
            var selectedWeapon = _player.GetNodeOrNull(selectedWeaponNodeName);
            if (selectedWeapon != null)
                return selectedWeapon;
        }

        Node? weapon = _player.GetNodeOrNull("Shotgun");
        weapon ??= _player.GetNodeOrNull("MiniUzi");
        weapon ??= _player.GetNodeOrNull("SilencedPistol");
        weapon ??= _player.GetNodeOrNull("SniperRifle");
        weapon ??= _player.GetNodeOrNull("AssaultRifle");
        weapon ??= _player.GetNodeOrNull("Revolver");
        weapon ??= _player.GetNodeOrNull("AKGL");
        weapon ??= _player.GetNodeOrNull("MakarovPM");
        return weapon;
    }

    private string GetSelectedWeaponNodeName()
    {
        var gameManager = GetNodeOrNull("/root/GameManager");
        if (gameManager == null || !gameManager.HasMethod("get_selected_weapon"))
            return string.Empty;

        return gameManager.Call("get_selected_weapon").AsString() switch
        {
            "shotgun" => "Shotgun",
            "mini_uzi" => "MiniUzi",
            "silenced_pistol" => "SilencedPistol",
            "sniper" => "SniperRifle",
            "m16" => "AssaultRifle",
            "ak_gl" => "AKGL",
            "revolver" => "Revolver",
            "makarov_pm" => "MakarovPM",
            _ => string.Empty,
        };
    }

    private static bool TryGetWeaponDisplayAmmo(Node weapon, out int currentAmmo, out int reserveAmmo)
    {
        if (weapon is Shotgun shotgun)
        {
            currentAmmo = shotgun.ShellsInTube;
            reserveAmmo = shotgun.ReserveAmmo;
            return true;
        }

        var currentAmmoValue = weapon.Get("CurrentAmmo");
        var reserveAmmoValue = weapon.Get("ReserveAmmo");
        if (currentAmmoValue.VariantType != Variant.Type.Nil &&
            reserveAmmoValue.VariantType != Variant.Type.Nil)
        {
            currentAmmo = currentAmmoValue.AsInt32();
            reserveAmmo = reserveAmmoValue.AsInt32();
            return true;
        }

        currentAmmo = 0;
        reserveAmmo = 0;
        return false;
    }

    private void RefreshWeaponHud(Node weapon, string reason)
    {
        if (TryGetWeaponDisplayAmmo(weapon, out var currentAmmo, out var reserveAmmo))
        {
            UpdateAmmoLabelMagazine(currentAmmo, reserveAmmo);
            LogToFile($"HUD ammo refreshed ({reason}): {weapon.Name} {currentAmmo}/{reserveAmmo}");
        }

        if (weapon.HasMethod("GetMagazineAmmoCounts"))
        {
            var magCounts = weapon.Call("GetMagazineAmmoCounts").AsGodotArray();
            UpdateMagazinesLabel(magCounts);
        }
    }

    private void ApplySilencedPistolAmmoConfig(Node weapon)
    {
        if (weapon.Name != "SilencedPistol" || !weapon.HasMethod("ConfigureAmmoForEnemyCount"))
            return;

        int enemyCount = _initialEnemyCount;
        var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
        if (difficultyManager != null && difficultyManager.HasMethod("get_ammo_multiplier"))
        {
            int multiplier = difficultyManager.Call("get_ammo_multiplier").AsInt32();
            if (multiplier > 1)
            {
                enemyCount *= multiplier;
                LogToFile($"Gunslinger/PowerFantasy mode: silenced pistol enemy count multiplied by {multiplier}x");
            }
        }

        weapon.Call("ConfigureAmmoForEnemyCount", enemyCount);
        LogToFile($"Configured silenced pistol ammo for {enemyCount} enemies");
        RefreshWeaponHud(weapon, "silenced pistol config");
    }

    private void ApplyMakarovPmAmmoConfig(Node weapon)
    {
        if (weapon.Name != "MakarovPM" || !weapon.HasMethod("ReinitializeMagazines"))
            return;

        int startingMagazines = 4;
        var startingMagazineValue = weapon.Get("StartingMagazineCount");
        if (startingMagazineValue.VariantType != Variant.Type.Nil)
            startingMagazines = startingMagazineValue.AsInt32();

        int magazines = Mathf.RoundToInt(startingMagazines * 2.5f);
        var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
        if (difficultyManager != null && difficultyManager.HasMethod("get_ammo_multiplier"))
        {
            int multiplier = difficultyManager.Call("get_ammo_multiplier").AsInt32();
            if (multiplier > 1)
            {
                magazines *= multiplier;
                LogToFile($"Gunslinger/PowerFantasy mode: MakarovPM magazines multiplied by {multiplier}x");
            }
        }

        weapon.Call("ReinitializeMagazines", magazines, true);
        LogToFile($"2.5x ammo for MakarovPM: {magazines} magazines (was {startingMagazines})");
        RefreshWeaponHud(weapon, "makarov config");
    }

    /// <summary>
    /// Apply level-specific ammo limits when this fallback replaces GDScript setup.
    /// Building and Labyrinth Complex both limit compact automatic weapons to 2 magazines.
    /// </summary>
    private void ApplyLevelSpecificAmmoConfig(Node weapon)
    {
        var levelRoot = GetParent();
        if (levelRoot == null) return;

        bool isLimitedLevel = levelRoot.Name == "BuildingLevel" || levelRoot.Name == "Labyrinth2Level";
        if (!isLimitedLevel) return;

        bool isLimitedWeapon = weapon.Name == "AKGL" || weapon.Name == "AssaultRifle" || weapon.Name == "MiniUzi";
        if (!isLimitedWeapon) return;

        int baseMagazines = 2;

        // Respect Power Fantasy ammo multiplier if active
        var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
        if (difficultyManager != null && difficultyManager.HasMethod("get_ammo_multiplier"))
        {
            int multiplier = difficultyManager.Call("get_ammo_multiplier").AsInt32();
            if (multiplier > 1)
            {
                baseMagazines *= multiplier;
                LogToFile($"{levelRoot.Name}: Power Fantasy mode - {weapon.Name} magazines multiplied by {multiplier}x");
            }
        }

        if (weapon.HasMethod("ReinitializeMagazines"))
        {
            weapon.Call("ReinitializeMagazines", baseMagazines, true);
            LogToFile($"{levelRoot.Name}: {weapon.Name} magazines reinitialized to {baseMagazines} (C# fallback)");
            RefreshWeaponHud(weapon, "level-specific fallback ammo config");
        }
    }

    /// <summary>
    /// Connect reload signals for enemy aggression behavior.
    /// </summary>
    private void ConnectReloadSignals()
    {
        if (_player == null) return;

        if (_player.HasSignal("ReloadStarted"))
            _player.Connect("ReloadStarted", new Callable(this, MethodName.OnPlayerReloadStarted));
        if (_player.HasSignal("ReloadCompleted"))
            _player.Connect("ReloadCompleted", new Callable(this, MethodName.OnPlayerReloadCompleted));
        if (_player.HasSignal("AmmoDepleted"))
            _player.Connect("AmmoDepleted", new Callable(this, MethodName.OnPlayerAmmoDepleted));
    }

    /// <summary>
    /// Add RealisticVisibilityComponent to the player for night mode support.
    /// </summary>
    private void SetupRealisticVisibility()
    {
        if (_player == null) return;

        // Check if visibility component already exists
        if (_player.GetNodeOrNull("RealisticVisibilityComponent") != null)
        {
            LogToFile("RealisticVisibilityComponent already exists on player");
            return;
        }

        var visibilityScript = GD.Load<Script>("res://scripts/components/realistic_visibility_component.gd");
        if (visibilityScript == null)
        {
            LogToFile("WARNING: RealisticVisibilityComponent script not found");
            return;
        }

        var visibilityComponent = new Node();
        visibilityComponent.Name = "RealisticVisibilityComponent";
        visibilityComponent.SetScript(visibilityScript);
        _player.AddChild(visibilityComponent);
        LogToFile("Realistic visibility component added to player (night mode)");
    }

    /// <summary>
    /// Mirrors the GDScript level setup for WeaponHintsComponent.
    /// Required for BuildingLevel when the GDScript _ready() path is skipped and
    /// this fallback performs level initialization instead.
    /// </summary>
    private void SetupWeaponHints(Node levelRoot)
    {
        if (_player == null)
        {
            LogToFile("WARNING: Weapon hints setup skipped - player is null");
            return;
        }

        var canvasLayer = levelRoot.GetNodeOrNull("CanvasLayer");
        if (canvasLayer == null)
        {
            LogToFile("WARNING: Weapon hints setup skipped - CanvasLayer not found");
            return;
        }

        if (levelRoot.GetNodeOrNull("WeaponHintsComponent") != null)
        {
            LogToFile("Weapon hints component already exists - skipping fallback setup");
            return;
        }

        var hintsScript = GD.Load<Script>("res://scripts/components/weapon_hints_component.gd");
        if (hintsScript == null)
        {
            LogToFile("WARNING: WeaponHintsComponent script not found");
            return;
        }

        _weaponHintsComponent = new Node();
        _weaponHintsComponent.Name = "WeaponHintsComponent";
        _weaponHintsComponent.SetScript(hintsScript);
        levelRoot.AddChild(_weaponHintsComponent);

        if (_weaponHintsComponent.HasMethod("setup"))
        {
            _weaponHintsComponent.Call("setup", _player, canvasLayer);
            LogToFile("Weapon hints component added and setup");
        }
        else
        {
            LogToFile("WARNING: WeaponHintsComponent has no setup() method");
        }
    }

    /// <summary>
    /// Initialize ScoreManager for this level.
    /// </summary>
    private void InitializeScoreManager()
    {
        var scoreManager = GetNodeOrNull("/root/ScoreManager");
        if (scoreManager == null) return;

        if (scoreManager.HasMethod("start_level"))
            scoreManager.Call("start_level", _initialEnemyCount);

        if (_player != null && scoreManager.HasMethod("set_player"))
            scoreManager.Call("set_player", _player);

        // Issue #1751: Connect to combo_changed signal to update the combo label.
        if (scoreManager.HasSignal("combo_changed") &&
            !scoreManager.IsConnected("combo_changed", new Callable(this, MethodName.OnComboChanged)))
        {
            scoreManager.Connect("combo_changed", new Callable(this, MethodName.OnComboChanged));
        }

        LogToFile($"ScoreManager initialized with {_initialEnemyCount} enemies");
    }

    /// <summary>
    /// Called when the combo count changes (Issue #1751, #1790).
    /// Updates the combo label in the HUD with gothic font and bounce animation.
    /// Label stays visible until combo resets to zero.
    /// </summary>
    private void OnComboChanged(int combo, int points)
    {
        if (_comboLabel == null) return;
        if (combo > 0)
        {
            // Two-line format matching GDScript: "x3 COMBO\n+150"
            _comboLabel.Text = $"x{combo} COMBO\n+{points}";
            _comboLabel.Visible = true;
            _comboLabel.AddThemeColorOverride("font_color", GetComboColor(combo));
            // Bounce animation: scale 0.7 -> 1.0 + fade in (stays visible until combo resets)
            if (_comboTween != null && _comboTween.IsValid())
                _comboTween.Kill();
            _comboLabel.Scale = new Vector2(0.7f, 0.7f);
            _comboLabel.Modulate = new Color(1.0f, 1.0f, 1.0f, 0.0f);
            _comboTween = CreateTween();
            _comboTween.SetParallel(true);
            _comboTween.TweenProperty(_comboLabel, "scale", new Vector2(1.0f, 1.0f), 0.15f)
                .SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
            _comboTween.TweenProperty(_comboLabel, "modulate:a", 1.0f, 0.1f);
        }
        else
        {
            // Combo reset: fade out then hide
            if (_comboTween != null && _comboTween.IsValid())
                _comboTween.Kill();
            _comboTween = CreateTween();
            _comboTween.TweenProperty(_comboLabel, "modulate:a", 0.0f, 0.3f);
            _comboTween.TweenCallback(Callable.From(() => { if (_comboLabel != null) _comboLabel.Visible = false; }));
        }
    }

    /// <summary>
    /// Returns a color based on the current combo count (Issue #1751).
    /// Matches the color scheme used by GDScript level scripts.
    /// </summary>
    private static Color GetComboColor(int combo)
    {
        if (combo >= 10) return new Color(1.0f, 0.0f, 1.0f, 1.0f);   // Magenta - extreme
        if (combo >= 7)  return new Color(1.0f, 0.3f, 0.0f, 1.0f);   // Deep orange
        if (combo >= 5)  return new Color(1.0f, 0.5f, 0.0f, 1.0f);   // Orange
        if (combo >= 4)  return new Color(1.0f, 0.7f, 0.0f, 1.0f);   // Amber
        if (combo >= 3)  return new Color(1.0f, 0.8f, 0.0f, 1.0f);   // Yellow-orange
        if (combo >= 2)  return new Color(1.0f, 0.9f, 0.1f, 1.0f);   // Yellow
        return new Color(1.0f, 0.8f, 0.2f, 1.0f);                     // Gold (combo 1)
    }

    /// <summary>
    /// Setup debug UI elements.
    /// DifficultyLabel is always shown (Issue #1485: replaces old KillsLabel + AccuracyLabel).
    /// MagazinesLabel is always shown.
    /// </summary>
    private void SetupDebugUI(Node levelRoot)
    {
        var ui = levelRoot.GetNodeOrNull("CanvasLayer/UI");
        if (ui == null) return;

        // Issue #1485: Show difficulty instead of old kills/accuracy labels,
        // matching the layout used by GDScript level scripts.
        var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
        string difficultyName = difficultyManager != null && difficultyManager.HasMethod("get_difficulty_name")
            ? difficultyManager.Call("get_difficulty_name").AsString()
            : "";

        _difficultyLabel = new Label();
        _difficultyLabel.Name = "DifficultyLabel";
        _difficultyLabel.Text = GetDifficultyText(difficultyName);
        _difficultyLabel.SetAnchorsPreset(Control.LayoutPreset.TopLeft);
        _difficultyLabel.OffsetLeft = 10;
        _difficultyLabel.OffsetTop = 80;
        _difficultyLabel.OffsetRight = 200;
        _difficultyLabel.OffsetBottom = 110;
        ui.AddChild(_difficultyLabel);

        _magazinesLabel = new Label();
        _magazinesLabel.Name = "MagazinesLabel";
        _magazinesLabel.Text = GetMagazinesText(new List<string>());
        _magazinesLabel.SetAnchorsPreset(Control.LayoutPreset.TopLeft);
        _magazinesLabel.OffsetLeft = 10;
        _magazinesLabel.OffsetTop = 115;
        _magazinesLabel.OffsetRight = 400;
        _magazinesLabel.OffsetBottom = 145;
        ui.AddChild(_magazinesLabel);

        // Issue #1751, #1790: Create combo label with Gothic bitmap font.
        // Matches GDScript level scripts: PRESET_TOP_WIDE, gothic font, two-line format, bounce animation.
        var gothicFont = GD.Load<Font>("res://assets/fonts/gothic_bitmap.fnt");
        int comboSize = 112; // default
        var gameplaySettings = GetNodeOrNull<Node>("/root/GameplaySettings");
        if (gameplaySettings != null && gameplaySettings.HasMethod("get_combo_font_size"))
            comboSize = (int)gameplaySettings.Call("get_combo_font_size");
        _comboLabel = new Label();
        _comboLabel.Name = "ComboLabel";
        _comboLabel.Text = "";
        _comboLabel.HorizontalAlignment = HorizontalAlignment.Right;
        _comboLabel.SetAnchorsPreset(Control.LayoutPreset.TopWide);
        _comboLabel.OffsetLeft = 10;
        _comboLabel.OffsetRight = -10;
        _comboLabel.OffsetTop = 80;
        _comboLabel.OffsetBottom = _comboLabel.OffsetTop + comboSize * 2 + 20;
        _comboLabel.AddThemeFontSizeOverride("font_size", comboSize);
        _comboLabel.AddThemeConstantOverride("line_spacing", 0);
        _comboLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.8f, 0.2f, 1.0f));
        if (gothicFont != null)
            _comboLabel.AddThemeFontOverride("font", gothicFont);
        _comboLabel.ClipContents = true;
        _comboLabel.Visible = false;
        ui.AddChild(_comboLabel);
    }

    /// <summary>
    /// CanvasLayer order for the revolver drum HUD (Issue #1765).
    /// Must be above the Black Metal B&amp;W filter (layer 97) and all other difficulty
    /// visual filters (layers 97–103) so the HUD is never desaturated.
    /// </summary>
    private const int CylinderHUDLayer = 110;

    /// <summary>
    /// Name of the dedicated CanvasLayer used for the cylinder HUD (Issue #1765).
    /// </summary>
    private const string CylinderHUDLayerName = "RevolverCylinderHUDLayer";

    /// <summary>
    /// Setup revolver cylinder HUD display (Issue #691).
    /// Issue #1765: The HUD is placed in a dedicated CanvasLayer at layer 110 so that
    /// difficulty visual filters (Black Metal B&amp;W at layer 97, etc.) do not affect it.
    /// </summary>
    private void SetupRevolverCylinderUI(Revolver revolver)
    {
        var levelRoot = GetParent();
        if (levelRoot == null) return;

        // Issue #1765: Don't create duplicate HUD if one already exists (e.g. from Revolver.cs)
        var existingLayer = levelRoot.GetNodeOrNull<CanvasLayer>(CylinderHUDLayerName);
        if (existingLayer != null)
        {
            LogToFile("[LevelInitFallback] Cylinder HUD layer already exists, connecting to existing");
            _cylinderUI = existingLayer.GetNodeOrNull<RevolverCylinderUI>("HUDContainer/RevolverCylinderUI");
            _cylinderUI?.ConnectToRevolver(revolver);
            return;
        }

        // Issue #1765: Create a dedicated CanvasLayer above all difficulty visual filters
        // (Black Metal B&W at layer 97, lightning at 98, cinema at 99, hit at 100, etc.)
        // so the drum HUD always renders in its original colors regardless of difficulty mode.
        var hudLayer = new CanvasLayer();
        hudLayer.Name = CylinderHUDLayerName;
        hudLayer.Layer = CylinderHUDLayer;
        levelRoot.AddChild(hudLayer);

        // Add a full-screen Control as layout container
        var hudContainer = new Control();
        hudContainer.Name = "HUDContainer";
        hudContainer.SetAnchorsPreset(Control.LayoutPreset.FullRect);
        hudContainer.MouseFilter = Control.MouseFilterEnum.Ignore;
        hudLayer.AddChild(hudContainer);

        _cylinderUI = new RevolverCylinderUI();
        _cylinderUI.Name = "RevolverCylinderUI";
        _cylinderUI.SetAnchorsPreset(Control.LayoutPreset.TopLeft);
        _cylinderUI.OffsetLeft = 10;
        _cylinderUI.OffsetTop = 30;
        _cylinderUI.OffsetRight = 200;
        _cylinderUI.OffsetBottom = 68;
        hudContainer.AddChild(_cylinderUI);

        _cylinderUI.ConnectToRevolver(revolver);

        LogToFile("[LevelInitFallback] Revolver cylinder HUD created in dedicated layer 110 above visual filters (Issue #1765)");
    }

    /// <summary>
    /// Setup saturation overlay for kill effects.
    /// </summary>
    private void SetupSaturationOverlay(Node levelRoot)
    {
        var canvasLayer = levelRoot.GetNodeOrNull("CanvasLayer");
        if (canvasLayer == null) return;

        _saturationOverlay = new ColorRect();
        _saturationOverlay.Name = "SaturationOverlay";
        _saturationOverlay.Color = new Color(1.0f, 0.9f, 0.3f, 0.0f);
        _saturationOverlay.SetAnchorsPreset(Control.LayoutPreset.FullRect);
        _saturationOverlay.MouseFilter = Control.MouseFilterEnum.Ignore;
        canvasLayer.AddChild(_saturationOverlay);
        canvasLayer.MoveChild(_saturationOverlay, canvasLayer.GetChildCount() - 1);
    }

    /// <summary>
    /// Setup exit zone near player spawn.
    /// </summary>
    private void SetupExitZone(Node levelRoot)
    {
        var exitZoneScene = GD.Load<PackedScene>("res://scenes/objects/ExitZone.tscn");
        if (exitZoneScene == null)
        {
            LogToFile("WARNING: ExitZone scene not found");
            return;
        }

        _exitZone = exitZoneScene.Instantiate<Area2D>();
        var exitConfig = GetExitZoneConfig(levelRoot.Name.ToString());
        _exitZone.Position = exitConfig.Position;
        _exitZone.Set("zone_width", exitConfig.Width);
        _exitZone.Set("zone_height", exitConfig.Height);

        if (_exitZone.HasSignal("player_reached_exit"))
        {
            _exitZone.Connect("player_reached_exit", new Callable(this, MethodName.OnPlayerReachedExit));
        }

        var environment = levelRoot.GetNodeOrNull("Environment");
        if (environment != null)
            environment.AddChild(_exitZone);
        else
            levelRoot.AddChild(_exitZone);

        LogToFile($"Exit zone created at position ({exitConfig.Position.X}, {exitConfig.Position.Y})");
    }

    private static (Vector2 Position, float Width, float Height) GetExitZoneConfig(string levelName)
    {
        return levelName switch
        {
            "BuildingLevel" => (new Vector2(120, 1250), 60.0f, 100.0f),
            "Labyrinth2Level" => (new Vector2(3200, 1200), 60.0f, 100.0f),
            _ => (new Vector2(120, 1544), 60.0f, 100.0f),
        };
    }

    /// <summary>
    /// Start replay recording.
    /// </summary>
    private void StartReplayRecording(Node levelRoot)
    {
        var replayManager = GetNodeOrNull("/root/ReplayManager");
        if (replayManager == null)
        {
            LogToFile("WARNING: ReplayManager not found");
            return;
        }

        if (replayManager.HasMethod("ClearReplay"))
            replayManager.Call("ClearReplay");

        if (replayManager.HasMethod("StartRecording"))
        {
            var enemiesArray = new Godot.Collections.Array();
            foreach (var enemy in _enemies)
            {
                enemiesArray.Add(enemy);
            }
            replayManager.Call("StartRecording", levelRoot, _player!, enemiesArray);
            LogToFile($"Replay recording started with {_enemies.Count} enemies");
        }
    }

    /// <summary>
    /// Sync state back to GDScript properties for compatibility.
    /// </summary>
    private void SyncGDScriptProperties(Node levelRoot)
    {
        var enemiesArray = new Godot.Collections.Array();
        foreach (var enemy in _enemies)
        {
            enemiesArray.Add(enemy);
        }

        // Set properties on the GDScript level root
        levelRoot.Set("_enemies", enemiesArray);
        levelRoot.Set("_initial_enemy_count", _initialEnemyCount);
        levelRoot.Set("_current_enemy_count", _currentEnemyCount);
        levelRoot.Set("_player", _player);
        levelRoot.Set("_enemy_count_label", _enemyCountLabel);
        levelRoot.Set("_ammo_label", _ammoLabel);
        if (_exitZone != null) levelRoot.Set("_exit_zone", _exitZone);
        if (_saturationOverlay != null) levelRoot.Set("_saturation_overlay", _saturationOverlay);
        if (_difficultyLabel != null) levelRoot.Set("_difficulty_label", _difficultyLabel);
        if (_magazinesLabel != null) levelRoot.Set("_magazines_label", _magazinesLabel);
        if (_weaponHintsComponent != null) levelRoot.Set("_weapon_hints_component", _weaponHintsComponent);

        LogToFile("GDScript properties synced");
    }

    // === Signal Handlers ===

    private void OnEnemyDied()
    {
        _currentEnemyCount--;
        UpdateEnemyCountLabel();

        var gameManager = GetNodeOrNull("/root/GameManager");
        if (gameManager != null && gameManager.HasMethod("register_kill"))
            gameManager.Call("register_kill");

        // Sync count back to GDScript
        var parent = GetParent();
        if (parent != null)
            parent.Set("_current_enemy_count", _currentEnemyCount);

        if (_currentEnemyCount <= 0)
        {
            LogToFile("All enemies eliminated! Arena cleared!");

            var replayManager = GetNodeOrNull("/root/ReplayManager");
            if (replayManager != null && replayManager.HasMethod("StopRecording"))
                replayManager.Call("StopRecording");

            _levelCleared = true;
            if (parent != null) parent.Set("_level_cleared", true);

            CallDeferred(MethodName.ActivateExitZone);
        }
    }

    private void OnEnemyDiedWithInfo(bool isRicochetKill, bool isPenetrationKill, bool isPlayerKill)
    {
        // Issue #1259: signature must match enemy.gd died_with_info(is_ricochet_kill, is_penetration_kill, is_player_kill)
        // Issue #1196 added is_player_kill as the 3rd param. Mismatched arity silently dropped all score calls.
        var scoreManager = GetNodeOrNull("/root/ScoreManager");
        if (scoreManager != null && scoreManager.HasMethod("register_kill"))
            scoreManager.Call("register_kill", isRicochetKill, isPenetrationKill);
    }

    private void OnEnemyHit()
    {
        var gameManager = GetNodeOrNull("/root/GameManager");
        if (gameManager != null && gameManager.HasMethod("register_hit"))
            gameManager.Call("register_hit");
    }

    private void OnShotFired()
    {
        var gameManager = GetNodeOrNull("/root/GameManager");
        if (gameManager != null && gameManager.HasMethod("register_shot"))
            gameManager.Call("register_shot");
    }

    private void OnWeaponAmmoChanged(int currentAmmo, int reserveAmmo)
    {
        UpdateAmmoLabelMagazine(currentAmmo, reserveAmmo);
    }

    private void OnMagazinesChanged(Godot.Collections.Array magazineAmmoCounts)
    {
        UpdateMagazinesLabel(magazineAmmoCounts);
    }

    private void OnLocaleChanged(string _locale)
    {
        RefreshLocalizedHudLabels();
    }

    private void OnShellCountChanged(int shellCount, int capacity)
    {
        int reserveAmmo = 0;
        var weapon = GetCurrentWeaponNode();
        if (weapon != null)
        {
            var reserve = weapon.Get("ReserveAmmo");
            if (reserve.VariantType != Variant.Type.Nil)
                reserveAmmo = reserve.AsInt32();
        }
        UpdateAmmoLabelMagazine(shellCount, reserveAmmo);
    }

    private void OnPlayerDied()
    {
        // Issue #1334: Guard against duplicate death handling
        if (_isDying) return;
        _isDying = true;

        ShowDeathMessage();
        var gameManager = GetNodeOrNull("/root/GameManager");
        if (gameManager != null && gameManager.HasMethod("on_player_death"))
        {
            var timer = GetTree().CreateTimer(0.5);
            timer.Timeout += () =>
            {
                // Issue #1334: Verify both this node and GameManager are still valid
                // before calling on_player_death. SceneTreeTimers persist across
                // scene reloads (godotengine/godot-proposals#8577), so the callback
                // can fire after this node has been freed.
                if (IsInstanceValid(this) && IsInstanceValid(gameManager))
                    gameManager.Call("on_player_death");
            };
        }
    }

    private void OnPlayerReloadStarted()
    {
        BroadcastPlayerState("set_player_reloading", true);
        if (_player != null)
        {
            var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
            if (soundPropagation != null && soundPropagation.HasMethod("emit_player_reload"))
            {
                // Issue #1897: silenced pistol reload is nearly inaudible (100px vs default 900px)
                float reloadSoundRange = IsSilencedPistolEquipped() ? 100.0f : -1.0f;
                soundPropagation.Call("emit_player_reload", _player.GlobalPosition, _player, reloadSoundRange);
            }
        }
    }

    private bool IsSilencedPistolEquipped()
    {
        var weapon = GetCurrentWeaponNode();
        return weapon?.Name == "SilencedPistol";
    }

    private void OnPlayerReloadCompleted()
    {
        BroadcastPlayerState("set_player_reloading", false);
        BroadcastPlayerState("set_player_ammo_empty", false);
    }

    private void OnPlayerAmmoDepleted()
    {
        BroadcastPlayerState("set_player_ammo_empty", true);
        if (_player != null)
        {
            var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
            if (soundPropagation != null && soundPropagation.HasMethod("emit_player_empty_click"))
                soundPropagation.Call("emit_player_empty_click", _player.GlobalPosition, _player);

            if (_currentEnemyCount > 0 && !_gameOverShown)
            {
                var currentAmmoValue = _player.Get("CurrentWeapon");
                if (currentAmmoValue.Obj is Node weapon)
                {
                    if (TryGetWeaponDisplayAmmo(weapon, out var currentAmmo, out var reserveAmmo) &&
                        currentAmmo <= 0 &&
                        reserveAmmo <= 0)
                    {
                        ShowOutOfAmmoMessage();
                    }
                }
            }
        }
    }

    private void OnGameManagerEnemyKilled()
    {
        ShowSaturationEffect();
    }

    private void OnPlayerReachedExit()
    {
        if (!_levelCleared) return;
        LogToFile("Player reached exit - showing score!");
        CallDeferred(MethodName.CompleteLevelWithScore);
    }

    // === Helper Methods ===

    private void BroadcastPlayerState(string method, bool value)
    {
        var parent = GetParent();
        if (parent == null) return;
        var enemiesNode = parent.GetNodeOrNull("Environment/Enemies");
        if (enemiesNode == null) return;

        foreach (var enemy in enemiesNode.GetChildren())
        {
            if (enemy.HasMethod(method))
                enemy.Call(method, value);
        }
    }

    private void ActivateExitZone()
    {
        if (_exitZone != null && _exitZone.HasMethod("activate"))
        {
            _exitZone.Call("activate");
            LogToFile("Exit zone activated - go to exit to see score!");
        }
        else
        {
            CompleteLevelWithScore();
        }
    }

    private void CompleteLevelWithScore()
    {
        // Disable player controls so clicks on the score screen don't trigger shooting.
        if (_player != null && IsInstanceValid(_player))
        {
            _player.SetPhysicsProcess(false);
            _player.SetProcess(false);
            _player.SetProcessInput(false);
            _player.SetProcessUnhandledInput(false);
        }

        var scoreManager = GetNodeOrNull("/root/ScoreManager");
        if (scoreManager != null && scoreManager.HasMethod("complete_level"))
        {
            var scoreData = scoreManager.Call("complete_level").AsGodotDictionary();
            ShowScoreScreen(scoreData);
        }
        else
        {
            ShowVictoryMessage();
        }
    }

    private void ShowScoreScreen(Godot.Collections.Dictionary scoreData)
    {
        var parent = GetParent();
        if (parent == null) return;
        var ui = parent.GetNodeOrNull("CanvasLayer/UI");
        if (ui == null)
        {
            ShowVictoryMessage();
            return;
        }

        var animatedScoreScreenScript = GD.Load<Script>("res://scripts/ui/animated_score_screen.gd");
        if (animatedScoreScreenScript != null)
        {
            var scoreScreen = new Node();
            scoreScreen.SetScript(animatedScoreScreenScript);
            parent.AddChild(scoreScreen);
            // Connect animation_completed signal to add navigation buttons (Issue #1259)
            if (scoreScreen.HasSignal("animation_completed"))
            {
                scoreScreen.Connect("animation_completed",
                    new Callable(this, MethodName.OnScoreAnimationCompleted));
            }
            if (scoreScreen.HasMethod("show_animated_score"))
            {
                scoreScreen.Call("show_animated_score", ui, scoreData);
            }
        }
        else
        {
            ShowVictoryMessage();
        }
    }

    /// <summary>
    /// Called when score animation finishes — add navigation buttons (Issue #1259).
    /// Mirrors _add_score_screen_buttons() in GDScript level scripts.
    /// </summary>
    private void OnScoreAnimationCompleted(Node container)
    {
        _scoreShown = true;

        // Spacer
        var spacer = new Control();
        spacer.CustomMinimumSize = new Vector2(0, 10);
        container.AddChild(spacer);

        var buttonsContainer = new VBoxContainer();
        buttonsContainer.Name = "ButtonsContainer";
        buttonsContainer.Alignment = BoxContainer.AlignmentMode.Center;
        buttonsContainer.AddThemeConstantOverride("separation", 10);
        container.AddChild(buttonsContainer);

        // Next Level button (if there is a next level)
        string nextLevelPath = GetNextLevelPath();
        if (nextLevelPath != "")
        {
            var nextButton = new Button();
            nextButton.Name = "NextLevelButton";
            nextButton.Text = "→ Next Level";
            nextButton.CustomMinimumSize = new Vector2(200, 40);
            nextButton.AddThemeFontSizeOverride("font_size", 18);
            nextButton.Pressed += () => OnNextLevelPressed(nextLevelPath);
            buttonsContainer.AddChild(nextButton);
        }

        // Restart button
        var restartButton = new Button();
        restartButton.Name = "RestartButton";
        restartButton.Text = "↻ Restart (Q)";
        restartButton.CustomMinimumSize = new Vector2(200, 40);
        restartButton.AddThemeFontSizeOverride("font_size", 18);
        restartButton.Pressed += OnRestartPressed;
        buttonsContainer.AddChild(restartButton);

        // Level Select button
        var levelSelectButton = new Button();
        levelSelectButton.Name = "LevelSelectButton";
        levelSelectButton.Text = "☰ Level Select";
        levelSelectButton.CustomMinimumSize = new Vector2(200, 40);
        levelSelectButton.AddThemeFontSizeOverride("font_size", 18);
        levelSelectButton.Pressed += OnLevelSelectPressed;
        buttonsContainer.AddChild(levelSelectButton);

        // Armory button (shown when unlock items are available, Issue #897)
        var unlockManager = GetNodeOrNull("/root/UnlockManager");
        if (unlockManager != null && unlockManager.HasMethod("has_any_available_unlock")
            && unlockManager.Call("has_any_available_unlock").AsBool())
        {
            var armoryButton = new Button();
            armoryButton.Name = "ArmoryButton";
            armoryButton.Text = "★ Armory — Items Available!";
            armoryButton.CustomMinimumSize = new Vector2(200, 40);
            armoryButton.AddThemeFontSizeOverride("font_size", 18);
            armoryButton.AddThemeColorOverride("font_color", new Color(1.0f, 0.85f, 0.2f, 1.0f));
            var armoryStyle = new StyleBoxFlat();
            armoryStyle.BgColor = new Color(0.28f, 0.22f, 0.08f, 0.9f);
            armoryStyle.BorderColor = new Color(1.0f, 0.8f, 0.1f, 1.0f);
            armoryStyle.BorderWidthLeft = 2;
            armoryStyle.BorderWidthRight = 2;
            armoryStyle.BorderWidthTop = 2;
            armoryStyle.BorderWidthBottom = 2;
            armoryStyle.CornerRadiusTopLeft = 4;
            armoryStyle.CornerRadiusTopRight = 4;
            armoryStyle.CornerRadiusBottomLeft = 4;
            armoryStyle.CornerRadiusBottomRight = 4;
            armoryButton.AddThemeStyleboxOverride("normal", armoryStyle);
            armoryButton.Pressed += OnArmoryPressed;
            buttonsContainer.AddChild(armoryButton);
            // Add gold shine shader overlay (Issue #1536).
            var armoryShineShader = GD.Load<Shader>("res://scripts/shaders/gold_shine.gdshader");
            if (armoryShineShader != null)
            {
                var armoryShinemat = new ShaderMaterial();
                armoryShinemat.Shader = armoryShineShader;
                var armoryShineOverlay = new ColorRect();
                armoryShineOverlay.Name = "ArmoryGoldShineOverlay";
                armoryShineOverlay.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
                armoryShineOverlay.MouseFilter = Control.MouseFilterEnum.Ignore;
                armoryShineOverlay.Material = armoryShinemat;
                armoryButton.AddChild(armoryShineOverlay);
            }
        }

        Input.MouseMode = Input.MouseModeEnum.Confined;
        if (nextLevelPath != "")
        {
            var nextBtn = buttonsContainer.GetNodeOrNull<Button>("NextLevelButton");
            nextBtn?.GrabFocus();
        }
        else
        {
            restartButton.GrabFocus();
        }
    }

    private void OnNextLevelPressed(string levelPath)
    {
        Input.MouseMode = Input.MouseModeEnum.ConfinedHidden;
        var tree = GetTree();
        if (tree != null)
        {
            var err = tree.ChangeSceneToFile(levelPath);
            if (err != Error.Ok)
                Input.MouseMode = Input.MouseModeEnum.Confined;
        }
    }

    private void OnRestartPressed()
    {
        var gameManager = GetNodeOrNull("/root/GameManager");
        if (gameManager != null && gameManager.HasMethod("restart_scene"))
            gameManager.Call("restart_scene");
        else
            GetTree()?.ReloadCurrentScene();
    }

    private void OnLevelSelectPressed()
    {
        var levelsMenuScript = GD.Load<Script>("res://scripts/ui/levels_menu.gd");
        if (levelsMenuScript != null)
        {
            var levelsMenu = new CanvasLayer();
            levelsMenu.SetScript(levelsMenuScript);
            levelsMenu.Layer = 100;
            GetTree()?.Root.AddChild(levelsMenu);
            if (levelsMenu.HasSignal("back_pressed"))
                levelsMenu.Connect("back_pressed", Callable.From(() => levelsMenu.QueueFree()));
        }
    }

    private void OnArmoryPressed()
    {
        var armoryMenuScene = GD.Load<PackedScene>("res://scenes/ui/ArmoryMenu.tscn");
        if (armoryMenuScene != null)
        {
            var armoryMenu = armoryMenuScene.Instantiate<CanvasLayer>();
            armoryMenu.Set("layer", 100);
            armoryMenu.Set("opened_from_score_screen", true);
            GetTree()?.Root.AddChild(armoryMenu);
            // Issue #1050: Remove gold highlight from armory button if all available items
            // have been unlocked — matches _remove_armory_button_gold_style() in GDScript levels.
            if (armoryMenu.HasSignal("back_pressed"))
                armoryMenu.Connect("back_pressed", Callable.From(() =>
                {
                    armoryMenu.QueueFree();
                    RemoveArmoryButtonGoldStyle();
                }));
            if (armoryMenu.HasSignal("apply_pressed_from_score_screen"))
                armoryMenu.Connect("apply_pressed_from_score_screen", Callable.From(() =>
                    RemoveArmoryButtonGoldStyle()));
        }
    }

    /// <summary>
    /// Remove the gold highlight from the ArmoryButton when no items remain to unlock.
    /// The button stays visible but loses its gold styling and reverts to plain "Armory" text.
    /// Matches _remove_armory_button_gold_style() in GDScript level scripts (Issue #1050).
    /// </summary>
    private void RemoveArmoryButtonGoldStyle()
    {
        var unlockManager = GetNodeOrNull("/root/UnlockManager");
        bool hasAvailableUnlock = unlockManager != null
            && unlockManager.HasMethod("has_any_available_unlock")
            && unlockManager.Call("has_any_available_unlock").AsBool();
        if (hasAvailableUnlock)
            return; // Still items to unlock — keep the highlight

        var currentScene = GetTree()?.CurrentScene;
        var armoryBtn = currentScene?.FindChild("ArmoryButton", true, false) as Button;
        if (armoryBtn != null)
        {
            armoryBtn.Text = "Armory";
            armoryBtn.RemoveThemeColorOverride("font_color");
            armoryBtn.RemoveThemeStyleboxOverride("normal");
            // Issue #1690: Remove gold shine overlay added by Issue #1536
            var shineOverlay = armoryBtn.FindChild("ArmoryGoldShineOverlay", true, false);
            shineOverlay?.QueueFree();
        }
    }

    /// <summary>
    /// Returns the path of the next level in the campaign order, or empty string if last.
    /// Matches the level ordering in GDScript _get_next_level_path().
    /// </summary>
    private string GetNextLevelPath()
    {
        var tree = GetTree();
        if (tree == null) return "";

        string currentPath = tree.CurrentScene?.SceneFilePath ?? "";
        string[] levelPaths = new[]
        {
            "res://scenes/levels/LabyrinthLevel.tscn",
            "res://scenes/levels/BuildingLevel.tscn",
            "res://scenes/levels/TestTier.tscn",
            "res://scenes/levels/CastleLevel.tscn",
            "res://scenes/levels/RevolverLevel.tscn",
            "res://scenes/levels/CityLevel.tscn",
            "res://scenes/levels/BeachLevel.tscn",
            "res://scenes/levels/DocksLevel.tscn",
            "res://scenes/levels/FactoryLevel.tscn",
            "res://scenes/levels/DecadenceLevel.tscn",
            "res://scenes/levels/Labyrinth2Level.tscn",
        };
        for (int i = 0; i < levelPaths.Length; i++)
        {
            if (levelPaths[i] == currentPath && i + 1 < levelPaths.Length)
                return levelPaths[i + 1];
        }
        return "";
    }

    private void ShowVictoryMessage()
    {
        var parent = GetParent();
        if (parent == null) return;
        var ui = parent.GetNodeOrNull("CanvasLayer/UI");
        if (ui == null) return;

        _scoreShown = true;

        var victoryLabel = new Label();
        victoryLabel.Name = "VictoryLabel";
        victoryLabel.Text = "ARENA CLEARED!";
        victoryLabel.HorizontalAlignment = HorizontalAlignment.Center;
        victoryLabel.VerticalAlignment = VerticalAlignment.Center;
        victoryLabel.AddThemeFontSizeOverride("font_size", 48);
        victoryLabel.AddThemeColorOverride("font_color", new Color(0.2f, 1.0f, 0.3f, 1.0f));
        victoryLabel.SetAnchorsPreset(Control.LayoutPreset.Center);
        victoryLabel.OffsetLeft = -200;
        victoryLabel.OffsetRight = 200;
        victoryLabel.OffsetTop = -80;
        victoryLabel.OffsetBottom = -30;
        ui.AddChild(victoryLabel);
    }

    private void ShowDeathMessage()
    {
        var parent = GetParent();
        if (parent == null) return;
        var ui = parent.GetNodeOrNull("CanvasLayer/UI");
        if (ui == null) return;

        var deathLabel = new Label();
        deathLabel.Name = "DeathLabel";
        deathLabel.Text = "YOU DIED";
        deathLabel.HorizontalAlignment = HorizontalAlignment.Center;
        deathLabel.VerticalAlignment = VerticalAlignment.Center;
        deathLabel.AddThemeFontSizeOverride("font_size", 64);
        deathLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.15f, 0.15f, 1.0f));
        deathLabel.SetAnchorsPreset(Control.LayoutPreset.Center);
        deathLabel.OffsetLeft = -200;
        deathLabel.OffsetRight = 200;
        deathLabel.OffsetTop = -50;
        deathLabel.OffsetBottom = 50;
        ui.AddChild(deathLabel);
    }

    private void ShowOutOfAmmoMessage()
    {
        var parent = GetParent();
        if (parent == null) return;
        var ui = parent.GetNodeOrNull("CanvasLayer/UI");
        if (ui == null) return;

        _gameOverShown = true;

        var existing = ui.GetNodeOrNull<Label>("GameOverLabel");
        if (existing != null)
            existing.QueueFree();

        var gameOverLabel = new Label();
        gameOverLabel.Name = "GameOverLabel";
        gameOverLabel.Text = "OUT OF AMMO!";
        gameOverLabel.HorizontalAlignment = HorizontalAlignment.Center;
        gameOverLabel.VerticalAlignment = VerticalAlignment.Center;
        gameOverLabel.AddThemeFontSizeOverride("font_size", 56);
        gameOverLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.35f, 0.1f, 1.0f));
        gameOverLabel.SetAnchorsPreset(Control.LayoutPreset.Center);
        gameOverLabel.OffsetLeft = -240;
        gameOverLabel.OffsetRight = 240;
        gameOverLabel.OffsetTop = -120;
        gameOverLabel.OffsetBottom = -40;
        ui.AddChild(gameOverLabel);
    }

    private void ShowSaturationEffect()
    {
        if (_saturationOverlay == null) return;

        var tween = CreateTween();
        tween.TweenProperty(_saturationOverlay, "color:a", 0.25f, 0.15f * 0.3f);
        tween.TweenProperty(_saturationOverlay, "color:a", 0.0f, 0.15f * 0.7f);
    }

    private void UpdateEnemyCountLabel()
    {
        if (_enemyCountLabel != null)
            _enemyCountLabel.Text = TrFormat("HUD_ENEMIES", _currentEnemyCount);
    }

    private void UpdateAmmoLabelMagazine(int currentMag, int reserve)
    {
        if (_ammoLabel == null) return;

        _ammoLabel.Text = TrFormat("HUD_AMMO", currentMag, reserve);

        if (currentMag <= 5)
            _ammoLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.2f, 0.2f, 1.0f));
        else if (currentMag <= 10)
            _ammoLabel.AddThemeColorOverride("font_color", new Color(1.0f, 1.0f, 0.2f, 1.0f));
        else
            _ammoLabel.AddThemeColorOverride("font_color", new Color(1.0f, 1.0f, 1.0f, 1.0f));
    }

    private void UpdateMagazinesLabel(Godot.Collections.Array magazineAmmoCounts)
    {
        if (_magazinesLabel == null) return;
        _lastMagazineAmmoCounts = magazineAmmoCounts.Duplicate();

        var weapon = GetCurrentWeaponNode();

        // Hide MAGS for tube-magazine weapons (shotgun) — no detachable magazines
        if (weapon != null)
        {
            var usesTube = weapon.Get("UsesTubeMagazine");
            if (usesTube.VariantType != Variant.Type.Nil && usesTube.AsBool())
            {
                _magazinesLabel.Visible = false;
                return;
            }
        }

        // Hide MAGS for revolver — cylinder HUD already shows ammo (Issue #1750)
        if (weapon != null && weapon.HasSignal("CylinderStateChanged"))
        {
            _magazinesLabel.Visible = false;
            return;
        }

        _magazinesLabel.Visible = true;

        if (magazineAmmoCounts.Count == 0)
        {
            _magazinesLabel.Text = GetMagazinesText(new List<string>());
            return;
        }

        // Get magazine capacities to distinguish full vs partial spares
        int[] magMaxCounts = Array.Empty<int>();
        if (weapon != null && weapon.HasMethod("GetMagazineMaxCounts"))
        {
            var maxArray = weapon.Call("GetMagazineMaxCounts").AsGodotArray();
            magMaxCounts = new int[maxArray.Count];
            for (int i = 0; i < maxArray.Count; i++)
                magMaxCounts[i] = maxArray[i].AsInt32();
        }

        var parts = new List<string>();
        // Current magazine always shown in brackets
        parts.Add($"[{magazineAmmoCounts[0].AsInt32()}]");

        // Spare magazines: skip empty, show partial individually, abbreviate full as + xN
        int fullSpareCount = 0;
        for (int i = 1; i < magazineAmmoCounts.Count; i++)
        {
            int ammo = magazineAmmoCounts[i].AsInt32();
            if (ammo <= 0) continue;
            int cap = i < magMaxCounts.Length ? magMaxCounts[i] : 0;
            if (cap > 0 && ammo >= cap)
                fullSpareCount++;
            else
                parts.Add(ammo.ToString());
        }

        if (fullSpareCount > 0)
            parts.Add($"+ x{fullSpareCount}");

        _magazinesLabel.Text = GetMagazinesText(parts);
    }

    private void UpdateDebugUI()
    {
        RefreshLocalizedHudLabels();
    }

    private void RefreshLocalizedHudLabels()
    {
        UpdateEnemyCountLabel();

        if (_difficultyLabel != null)
        {
            var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
            if (difficultyManager != null && difficultyManager.HasMethod("get_difficulty_name"))
                _difficultyLabel.Text = GetDifficultyText(difficultyManager.Call("get_difficulty_name").AsString());
        }

        if (_magazinesLabel != null)
            UpdateMagazinesLabel(_lastMagazineAmmoCounts);
    }

    private static string Tr(string key)
    {
        return TranslationServer.Translate(key).ToString();
    }

    private static string TrFormat(string key, params object[] args)
    {
        return GodotPercentFormat(Tr(key), args);
    }

    private static string GodotPercentFormat(string format, params object[] args)
    {
        string result = format;
        foreach (var arg in args)
        {
            string replacement = arg?.ToString() ?? "";
            int intIndex = result.IndexOf("%d", StringComparison.Ordinal);
            int stringIndex = result.IndexOf("%s", StringComparison.Ordinal);
            int placeholderIndex;
            if (intIndex == -1)
                placeholderIndex = stringIndex;
            else if (stringIndex == -1)
                placeholderIndex = intIndex;
            else
                placeholderIndex = Math.Min(intIndex, stringIndex);

            if (placeholderIndex == -1)
                break;

            result = result.Substring(0, placeholderIndex) + replacement + result.Substring(placeholderIndex + 2);
        }
        return result;
    }

    private static string GetMagazinesText(IReadOnlyList<string> parts)
    {
        string prefix = Tr("ARMORY_STAT_MAG");
        return parts.Count == 0 ? $"{prefix}: -" : $"{prefix}: {string.Join(" | ", parts)}";
    }

    private static string GetDifficultyText(string difficultyName)
    {
        return TrFormat("HUD_DIFFICULTY", GetLocalizedDifficultyName(difficultyName));
    }

    private static string GetLocalizedDifficultyName(string difficultyName)
    {
        return difficultyName switch
        {
            "Easy" => Tr("EASY"),
            "Normal" => Tr("NORMAL"),
            "Hard" => Tr("HARD"),
            "Gunslinger" => Tr("GUNSLINGER"),
            _ => difficultyName,
        };
    }

    public override void _Process(double delta)
    {
        if (!_didInitialize) return;

        // Update enemy positions for aggressiveness tracking
        var scoreManager = GetNodeOrNull("/root/ScoreManager");
        if (scoreManager != null && scoreManager.HasMethod("update_enemy_positions"))
        {
            var enemiesArray = new Godot.Collections.Array();
            foreach (var enemy in _enemies)
            {
                if (IsInstanceValid(enemy))
                    enemiesArray.Add(enemy);
            }
            scoreManager.Call("update_enemy_positions", enemiesArray);
        }
    }

    /// <summary>
    /// Setup warm ceiling lights in the centers of rooms (Issue #1206).
    /// Mirrors the GDScript _setup_room_warm_lights() / _create_room_warm_light() methods so
    /// that lights are created even when GDScript _ready() silently fails due to the Godot 4.3
    /// binary-tokenization bug (godotengine/godot#94150).
    ///
    /// Room positions match the level-specific GDScript setup for Building and
    /// Labyrinth Complex.
    /// </summary>
    private void SetupRoomWarmLights(Node levelRoot)
    {
        // Respect PerformanceSettings warm_lights toggle (Issue #1693)
        var perfSettings = GetNode<Node>("/root/PerformanceSettings");
        if (perfSettings != null && perfSettings.HasMethod("is_warm_lights_enabled"))
        {
            var enabled = (bool)perfSettings.Call("is_warm_lights_enabled");
            if (!enabled)
            {
                LogToFile("Warm ceiling lights skipped — disabled via PerformanceSettings (Issue #1693)");
                return;
            }
        }

        var environment = levelRoot.GetNodeOrNull("Environment");
        if (environment == null)
        {
            LogToFile("WARNING: Environment node not found — skipping room warm lights setup");
            return;
        }

        // Avoid creating lights twice if somehow GDScript already ran
        if (levelRoot.GetNodeOrNull("Environment/RoomLights") != null)
        {
            LogToFile("RoomLights already exist — skipping warm lights setup");
            return;
        }

        var container = new Node2D();
        container.Name = "RoomLights";
        environment.AddChild(container);

        // Build the warm-light texture once and reuse it (single GPU upload)
        var lightTexture = CreateWarmLightTexture();
        var fixtureTexture = CreateLampFixtureTexture();

        var rooms = GetWarmLightRooms(levelRoot.Name.ToString());

        foreach (var room in rooms)
            CreateRoomWarmLight(container, room.Pos, room.Energy, room.Scale, room.Label, lightTexture, fixtureTexture);

        var logScope = levelRoot.Name == "Labyrinth2Level" ? "all zones" : "all rooms";
        LogToFile($"Warm ceiling lights placed in {logScope} (C# fallback)");
    }

    private static (Vector2 Pos, float Energy, float Scale, string Label)[] GetWarmLightRooms(string levelName)
    {
        if (levelName == "Labyrinth2Level")
        {
            return new (Vector2 Pos, float Energy, float Scale, string Label)[]
            {
                (new Vector2(334, 290),   0.7f, 3.5f, "EntryHall"),
                (new Vector2(906, 290),   0.7f, 3.5f, "WestWing"),
                (new Vector2(1512, 440),  0.85f, 4.5f, "CentralHub"),
                (new Vector2(2112, 290),  0.7f, 3.5f, "NorthSector"),
                (new Vector2(2836, 290),  0.7f, 3.5f, "EastWing"),
                (new Vector2(800, 1512),  0.85f, 4.5f, "CentralCorridor_W"),
                (new Vector2(1664, 1512), 0.85f, 4.5f, "CentralCorridor_C"),
                (new Vector2(2528, 1512), 0.85f, 4.5f, "CentralCorridor_E"),
                (new Vector2(800, 2136),  0.85f, 4.5f, "LowerLabyrinth_W"),
                (new Vector2(1664, 2136), 0.85f, 4.5f, "LowerLabyrinth_C"),
                (new Vector2(2528, 2136), 0.85f, 4.5f, "LowerLabyrinth_E"),
            };
        }

        return new (Vector2 Pos, float Energy, float Scale, string Label)[]
        {
            (new Vector2(1918, 340),  0.9f, 5.0f, "ConferenceRoom"),
            (new Vector2(1918, 994),  0.9f, 5.0f, "BreakRoom"),
            (new Vector2(2200, 1638), 0.9f, 5.0f, "ServerRoom"),
            (new Vector2(1200, 1724), 0.85f, 4.5f, "MainHall"),
            (new Vector2(290, 384),   0.7f, 3.5f, "Office1"),
            (new Vector2(718, 780),   0.7f, 3.5f, "Office2"),
        };
    }

    /// <summary>
    /// Create a single warm ceiling light node at the given position.
    /// </summary>
    private static void CreateRoomWarmLight(
        Node2D parent, Vector2 pos, float energy, float scale, string roomName,
        ImageTexture lightTexture, ImageTexture fixtureTexture)
    {
        var lightNode = new Node2D();
        lightNode.Name = $"WarmLight_{roomName}";
        lightNode.Position = pos;
        parent.AddChild(lightNode);

        // Small visual indicator — round lamp fixture sprite
        var fixture = new Sprite2D();
        fixture.Name = "Fixture";
        fixture.Texture = fixtureTexture;
        fixture.Modulate = new Color(1.0f, 0.85f, 0.5f, 0.5f);
        lightNode.AddChild(fixture);

        // The warm PointLight2D — shadows disabled for performance (Issue #1693).
        // PCF5 shadows on each PointLight2D add a full shadow-map render pass per light,
        // which was causing severe FPS drops (down to ~6 fps baseline) on low-end hardware.
        var light = new PointLight2D();
        light.Name = "PointLight";
        light.Color = new Color(1.0f, 0.75f, 0.3f, 1.0f);
        light.Energy = energy;
        light.ShadowEnabled = false;
        light.Texture = lightTexture;
        light.TextureScale = scale;
        lightNode.AddChild(light);
    }

    /// <summary>
    /// Create a soft radial gradient texture for the warm room lights.
    /// Matches the GDScript _create_warm_light_texture() result exactly.
    /// Uses a power-law falloff: bright core → gentle taper → black at rim.
    /// </summary>
    private static ImageTexture CreateWarmLightTexture()
    {
        const int size = 512;
        var center = new Vector2(size * 0.5f, size * 0.5f);
        float outerR = size * 0.5f;

        var image = Image.Create(size, size, false, Image.Format.Rgba8);

        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
                float dist = new Vector2(x, y).DistanceTo(center);
                float t = Mathf.Clamp(dist / outerR, 0.0f, 1.0f);
                float brightness = Mathf.Pow(1.0f - t, 2.2f);
                image.SetPixel(x, y, new Color(brightness, brightness, brightness, 1.0f));
            }
        }

        return ImageTexture.CreateFromImage(image);
    }

    /// <summary>
    /// Create a small circular texture for the lamp fixture visual indicator.
    /// Matches the GDScript _create_lamp_fixture_texture() result exactly.
    /// </summary>
    private static ImageTexture CreateLampFixtureTexture()
    {
        const int size = 32;
        var center = new Vector2(size * 0.5f, size * 0.5f);
        float outerR = size * 0.5f;

        var image = Image.Create(size, size, false, Image.Format.Rgba8);

        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
                float dist = new Vector2(x, y).DistanceTo(center);
                if (dist >= outerR)
                {
                    image.SetPixel(x, y, new Color(0, 0, 0, 0));
                }
                else
                {
                    float t = Mathf.Clamp(dist / outerR, 0.0f, 1.0f);
                    float alpha = Mathf.Pow(1.0f - t, 1.5f);
                    image.SetPixel(x, y, new Color(1, 1, 1, alpha));
                }
            }
        }

        return ImageTexture.CreateFromImage(image);
    }

    /// <summary>
    /// Setup the navigation mesh for enemy pathfinding (Issue #1289).
    /// Mirrors GDScript _setup_navigation() — waits for the next physics frame so that
    /// CollisionShape2D nodes are registered with PhysicsServer2D, then performs an
    /// explicit parse + bake to carve walls out of the navmesh.
    /// </summary>
    private async void SetupNavigationDeferred(Node levelRoot)
    {
        // Wait for physics frame so CollisionShape2D nodes are registered
        await ToSignal(GetTree(), SceneTree.SignalName.PhysicsFrame);

        // After the await, verify the node is still valid (scene may have changed)
        if (!IsInstanceValid(this) || !IsInsideTree()) return;
        if (!IsInstanceValid(levelRoot) || !levelRoot.IsInsideTree()) return;

        var navRegion = levelRoot.GetNodeOrNull<NavigationRegion2D>("NavigationRegion2D");
        if (navRegion == null)
        {
            LogToFile("NavigationRegion2D not found - enemy pathfinding will be limited");
            return;
        }

        var navPoly = navRegion.NavigationPolygon;
        if (navPoly == null)
        {
            LogToFile("NavigationPolygon not found - enemy pathfinding will be limited");
            return;
        }

        LogToFile("Baking navigation mesh (C# fallback)...");
        var sourceGeometry = new NavigationMeshSourceGeometryData2D();
        NavigationServer2D.ParseSourceGeometryData(navPoly, sourceGeometry, levelRoot);
        NavigationServer2D.BakeFromSourceGeometryData(navPoly, sourceGeometry);
        // Push updated polygon back into the NavigationServer's live map.
        // Without this reassignment, agents still use the pre-bake (uncarved) navmesh.
        navRegion.NavigationPolygon = navPoly;
        navRegion.EmitSignal("bake_finished");
        LogToFile($"Navigation mesh baked successfully (C# fallback) — poly_count={navPoly.GetPolygonCount()}, vertex_count={navPoly.Vertices.Length}");
    }

    /// <summary>
    /// Log a message to the file logger and console.
    /// </summary>
    private void LogToFile(string message)
    {
        var fullMessage = $"[LevelInitFallback] {message}";
        GD.Print(fullMessage);

        var fileLogger = GetNodeOrNull("/root/FileLogger");
        if (fileLogger != null && fileLogger.HasMethod("log_info"))
        {
            fileLogger.Call("log_info", fullMessage);
        }
    }
}
