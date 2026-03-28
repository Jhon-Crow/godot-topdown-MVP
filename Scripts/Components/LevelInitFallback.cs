using Godot;
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

        // Apply camera limits for Building map only, regardless of whether GDScript ran.
        // This is a safety net: the GDScript _configure_camera() may fail silently (Issue #1684).
        // Guard: only run on BuildingLevel — other levels set their own camera limits (Issue #1684).
        if (parent.Name == "BuildingLevel")
            ConfigureBuildingCameraLimits();

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

        // 7. Initialize ScoreManager
        InitializeScoreManager();

        // 8. Setup exit zone
        SetupExitZone(levelRoot);

        // 9. Start replay recording
        StartReplayRecording(levelRoot);

        // 10. Update GDScript properties so they are in sync
        SyncGDScriptProperties(levelRoot);

        // 11. Setup warm ceiling lights (Issue #1206) — mirrors GDScript _setup_room_warm_lights()
        SetupRoomWarmLights(levelRoot);

        // 12. Setup navigation mesh (Issue #1289) — mirrors GDScript _setup_navigation()
        // Must run after physics frame so CollisionShape2D nodes are registered.
        SetupNavigationDeferred(levelRoot);
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

        // Try weapons in order of preference
        Node? weapon = _player.GetNodeOrNull("Shotgun");
        weapon ??= _player.GetNodeOrNull("MiniUzi");
        weapon ??= _player.GetNodeOrNull("SilencedPistol");
        weapon ??= _player.GetNodeOrNull("SniperRifle");
        weapon ??= _player.GetNodeOrNull("AssaultRifle");
        weapon ??= _player.GetNodeOrNull("Revolver");
        weapon ??= _player.GetNodeOrNull("AKGL");
        weapon ??= _player.GetNodeOrNull("MakarovPM");

        if (weapon == null) return;

        if (weapon.HasSignal("AmmoChanged"))
            weapon.Connect("AmmoChanged", new Callable(this, MethodName.OnWeaponAmmoChanged));
        if (weapon.HasSignal("MagazinesChanged"))
            weapon.Connect("MagazinesChanged", new Callable(this, MethodName.OnMagazinesChanged));
        if (weapon.HasSignal("Fired"))
            weapon.Connect("Fired", new Callable(this, MethodName.OnShotFired));
        if (weapon.HasSignal("ShellCountChanged"))
            weapon.Connect("ShellCountChanged", new Callable(this, MethodName.OnShellCountChanged));

        // Initial ammo display
        var currentAmmo = weapon.Get("CurrentAmmo");
        var reserveAmmo = weapon.Get("ReserveAmmo");
        if (currentAmmo.VariantType != Variant.Type.Nil && reserveAmmo.VariantType != Variant.Type.Nil)
        {
            UpdateAmmoLabelMagazine(currentAmmo.AsInt32(), reserveAmmo.AsInt32());
        }

        // Initial magazine display
        if (weapon.HasMethod("GetMagazineAmmoCounts"))
        {
            var magCounts = weapon.Call("GetMagazineAmmoCounts").AsGodotArray();
            UpdateMagazinesLabel(magCounts);
        }

        // Issue #691: Setup revolver cylinder HUD when revolver is equipped
        if (weapon is Revolver revolver)
        {
            SetupRevolverCylinderUI(revolver);
        }

        // Configure silenced pistol ammo
        if (weapon.Name == "SilencedPistol" && weapon.HasMethod("ConfigureAmmoForEnemyCount"))
        {
            weapon.Call("ConfigureAmmoForEnemyCount", _initialEnemyCount);
            LogToFile($"Configured silenced pistol ammo for {_initialEnemyCount} enemies");
        }

        // BuildingLevel-specific ammo config: M16/AK+GL limited to 2 magazines (Issue #949, #1259)
        ApplyBuildingLevelAmmoConfig(weapon);
    }

    /// <summary>
    /// Apply BuildingLevel-specific ammo limits (2 magazines for M16/AKGL) when running as fallback
    /// for BuildingLevel (Issue #949, #1259). Other levels use default ammo counts.
    /// </summary>
    private void ApplyBuildingLevelAmmoConfig(Node weapon)
    {
        var levelRoot = GetParent();
        if (levelRoot == null) return;

        // Only apply on BuildingLevel
        if (levelRoot.Name != "BuildingLevel") return;

        // M16 (AssaultRifle) and AK+GL should have 2 magazines (30+30) on Building level
        bool isLimitedWeapon = weapon.Name == "AKGL" || weapon.Name == "AssaultRifle";
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
                LogToFile($"BuildingLevel: Power Fantasy mode - {weapon.Name} magazines multiplied by {multiplier}x");
            }
        }

        if (weapon.HasMethod("ReinitializeMagazines"))
        {
            weapon.Call("ReinitializeMagazines", baseMagazines, true);
            LogToFile($"BuildingLevel: {weapon.Name} magazines reinitialized to {baseMagazines} (C# fallback, Issue #1259)");
        }

        // Refresh ammo display after reinitializing
        var currentAmmo = weapon.Get("CurrentAmmo");
        var reserveAmmo = weapon.Get("ReserveAmmo");
        if (currentAmmo.VariantType != Variant.Type.Nil && reserveAmmo.VariantType != Variant.Type.Nil)
        {
            UpdateAmmoLabelMagazine(currentAmmo.AsInt32(), reserveAmmo.AsInt32());
        }

        // Apply auto-reload magazine size reduction if active (Issue #1067)
        if (_player != null && _player.HasMethod("ApplyAutoReloadAfterLevelAmmoConfig"))
        {
            _player.Call("ApplyAutoReloadAfterLevelAmmoConfig");
            LogToFile($"BuildingLevel: Re-applied auto-reload magazine reduction after ammo config for {weapon.Name}");
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

        LogToFile($"ScoreManager initialized with {_initialEnemyCount} enemies");
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
        _difficultyLabel.Text = "Difficulty: " + difficultyName;
        _difficultyLabel.SetAnchorsPreset(Control.LayoutPreset.TopLeft);
        _difficultyLabel.OffsetLeft = 10;
        _difficultyLabel.OffsetTop = 80;
        _difficultyLabel.OffsetRight = 200;
        _difficultyLabel.OffsetBottom = 110;
        ui.AddChild(_difficultyLabel);

        _magazinesLabel = new Label();
        _magazinesLabel.Name = "MagazinesLabel";
        _magazinesLabel.Text = "MAGS: -";
        _magazinesLabel.SetAnchorsPreset(Control.LayoutPreset.TopLeft);
        _magazinesLabel.OffsetLeft = 10;
        _magazinesLabel.OffsetTop = 115;
        _magazinesLabel.OffsetRight = 400;
        _magazinesLabel.OffsetBottom = 145;
        ui.AddChild(_magazinesLabel);
    }

    /// <summary>
    /// Setup revolver cylinder HUD display (Issue #691).
    /// Creates the cylinder slot visualization and connects it to the revolver.
    /// Positioned below the ammo label in the top-left UI area.
    /// </summary>
    private void SetupRevolverCylinderUI(Revolver revolver)
    {
        var levelRoot = GetParent();
        if (levelRoot == null) return;

        var ui = levelRoot.GetNodeOrNull("CanvasLayer/UI");
        if (ui == null) return;

        _cylinderUI = new RevolverCylinderUI();
        _cylinderUI.Name = "RevolverCylinderUI";
        _cylinderUI.SetAnchorsPreset(Control.LayoutPreset.TopLeft);
        _cylinderUI.OffsetLeft = 10;
        _cylinderUI.OffsetTop = 30;
        _cylinderUI.OffsetRight = 200;
        _cylinderUI.OffsetBottom = 68;
        ui.AddChild(_cylinderUI);

        _cylinderUI.ConnectToRevolver(revolver);

        LogToFile("[LevelInitFallback] Revolver cylinder HUD created (Issue #691)");
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
        _exitZone.Position = new Vector2(120, 1544);
        _exitZone.Set("zone_width", 60.0f);
        _exitZone.Set("zone_height", 100.0f);

        if (_exitZone.HasSignal("player_reached_exit"))
        {
            _exitZone.Connect("player_reached_exit", new Callable(this, MethodName.OnPlayerReachedExit));
        }

        var environment = levelRoot.GetNodeOrNull("Environment");
        if (environment != null)
            environment.AddChild(_exitZone);
        else
            levelRoot.AddChild(_exitZone);

        LogToFile("Exit zone created at position (120, 1544)");
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

    private void OnShellCountChanged(int shellCount, int capacity)
    {
        int reserveAmmo = 0;
        if (_player != null)
        {
            var weapon = _player.GetNodeOrNull("Shotgun");
            if (weapon != null)
            {
                var reserve = weapon.Get("ReserveAmmo");
                if (reserve.VariantType != Variant.Type.Nil)
                    reserveAmmo = reserve.AsInt32();
            }
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
                soundPropagation.Call("emit_player_reload", _player.GlobalPosition, _player);
        }
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
            _enemyCountLabel.Text = $"Enemies: {_currentEnemyCount}";
    }

    private void UpdateAmmoLabelMagazine(int currentMag, int reserve)
    {
        if (_ammoLabel == null) return;

        _ammoLabel.Text = $"AMMO: {currentMag}/{reserve}";

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

        // Check if player has a weapon with tube magazine (shotgun)
        if (_player != null)
        {
            var weapon = _player.GetNodeOrNull("Shotgun");
            if (weapon != null)
            {
                var usesTube = weapon.Get("UsesTubeMagazine");
                if (usesTube.VariantType != Variant.Type.Nil && usesTube.AsBool())
                {
                    _magazinesLabel.Visible = false;
                    return;
                }
            }
        }

        _magazinesLabel.Visible = true;

        if (magazineAmmoCounts.Count == 0)
        {
            _magazinesLabel.Text = "MAGS: -";
            return;
        }

        var parts = new List<string>();
        for (int i = 0; i < magazineAmmoCounts.Count; i++)
        {
            int ammo = magazineAmmoCounts[i].AsInt32();
            parts.Add(i == 0 ? $"[{ammo}]" : ammo.ToString());
        }
        _magazinesLabel.Text = "MAGS: " + string.Join(" | ", parts);
    }

    private void UpdateDebugUI()
    {
        // Issue #1485: Update difficulty label (replaces old kills/accuracy update).
        if (_difficultyLabel != null)
        {
            var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
            if (difficultyManager != null && difficultyManager.HasMethod("get_difficulty_name"))
                _difficultyLabel.Text = "Difficulty: " + difficultyManager.Call("get_difficulty_name").AsString();
        }
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
    /// Room positions match those in building_level.gd:
    ///   Conference Room (1918,340), Break Room (1918,994), Server Room (2200,1638),
    ///   Main Hall (1200,1724), Office 1 (290,384), Office 2 (718,780).
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

        // Room config: position, energy, texture_scale, label
        var rooms = new (Vector2 Pos, float Energy, float Scale, string Label)[]
        {
            // Large rooms — bigger lights
            (new Vector2(1918, 340),  0.9f, 5.0f, "ConferenceRoom"),
            (new Vector2(1918, 994),  0.9f, 5.0f, "BreakRoom"),
            (new Vector2(2200, 1638), 0.9f, 5.0f, "ServerRoom"),
            (new Vector2(1200, 1724), 0.85f, 4.5f, "MainHall"),
            // Smaller rooms — softer lights
            (new Vector2(290, 384),   0.7f, 3.5f, "Office1"),
            // Office 2: shifted to upper half (y=780 instead of centre y=856)
            (new Vector2(718, 780),   0.7f, 3.5f, "Office2"),
        };

        foreach (var room in rooms)
            CreateRoomWarmLight(container, room.Pos, room.Energy, room.Scale, room.Label, lightTexture, fixtureTexture);

        LogToFile("Warm ceiling lights placed in all rooms (Issue #1206, C# fallback)");
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
