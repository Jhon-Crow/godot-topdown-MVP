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
    /// Saturation overlay for kill effects.
    /// </summary>
    private ColorRect? _saturationOverlay;

    /// <summary>
    /// Kills label for UI.
    /// </summary>
    private Label? _killsLabel;

    /// <summary>
    /// Accuracy label for UI.
    /// </summary>
    private Label? _accuracyLabel;

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

        // GDScript didn't run - perform fallback initialization
        LogToFile("GDScript _ready() did NOT execute - performing C# fallback initialization");
        _didInitialize = true;
        PerformFallbackInit();
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
    /// </summary>
    private void SetupDebugUI(Node levelRoot)
    {
        var ui = levelRoot.GetNodeOrNull("CanvasLayer/UI");
        if (ui == null) return;

        _killsLabel = new Label();
        _killsLabel.Name = "KillsLabel";
        _killsLabel.Text = "Kills: 0";
        _killsLabel.SetAnchorsPreset(Control.LayoutPreset.TopLeft);
        _killsLabel.OffsetLeft = 10;
        _killsLabel.OffsetTop = 45;
        _killsLabel.OffsetRight = 200;
        _killsLabel.OffsetBottom = 75;
        ui.AddChild(_killsLabel);

        _accuracyLabel = new Label();
        _accuracyLabel.Name = "AccuracyLabel";
        _accuracyLabel.Text = "Accuracy: 0%";
        _accuracyLabel.SetAnchorsPreset(Control.LayoutPreset.TopLeft);
        _accuracyLabel.OffsetLeft = 10;
        _accuracyLabel.OffsetTop = 75;
        _accuracyLabel.OffsetRight = 200;
        _accuracyLabel.OffsetBottom = 105;
        ui.AddChild(_accuracyLabel);

        _magazinesLabel = new Label();
        _magazinesLabel.Name = "MagazinesLabel";
        _magazinesLabel.Text = "MAGS: -";
        _magazinesLabel.SetAnchorsPreset(Control.LayoutPreset.TopLeft);
        _magazinesLabel.OffsetLeft = 10;
        _magazinesLabel.OffsetTop = 105;
        _magazinesLabel.OffsetRight = 400;
        _magazinesLabel.OffsetBottom = 135;
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
        _cylinderUI.OffsetBottom = 62;
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
        if (_killsLabel != null) levelRoot.Set("_kills_label", _killsLabel);
        if (_accuracyLabel != null) levelRoot.Set("_accuracy_label", _accuracyLabel);
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

    private void OnEnemyDiedWithInfo(bool isRicochetKill, bool isPenetrationKill)
    {
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
        ShowDeathMessage();
        var gameManager = GetNodeOrNull("/root/GameManager");
        if (gameManager != null && gameManager.HasMethod("on_player_death"))
        {
            var timer = GetTree().CreateTimer(0.5);
            timer.Timeout += () =>
            {
                if (IsInstanceValid(gameManager))
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
        var gameManager = GetNodeOrNull("/root/GameManager");
        if (gameManager == null) return;

        if (_killsLabel != null)
        {
            var kills = gameManager.Get("kills");
            if (kills.VariantType != Variant.Type.Nil)
                _killsLabel.Text = $"Kills: {kills.AsInt32()}";
        }

        if (_accuracyLabel != null && gameManager.HasMethod("get_accuracy"))
        {
            var accuracy = gameManager.Call("get_accuracy").AsDouble();
            _accuracyLabel.Text = $"Accuracy: {accuracy:F1}%";
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
