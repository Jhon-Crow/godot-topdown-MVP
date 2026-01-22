using Godot;
using GodotTopDownTemplate.AbstractClasses;
using GodotTopDownTemplate.Weapons;

namespace GodotTopDownTemplate.Characters;

/// <summary>
/// Player character controller for top-down movement and shooting.
/// Uses physics-based movement with acceleration and friction for smooth control.
/// Supports WASD and arrow key input via configured input actions.
/// Shoots bullets towards the mouse cursor on left mouse button.
/// Supports both automatic (hold to fire) and semi-automatic (click per shot) weapons.
/// Uses R-F-R key sequence for instant reload (press R, then F, then R again).
/// Grenade throwing: G+RMB drag right → hold G+RMB → release G → drag and release RMB to throw.
/// </summary>
public partial class Player : BaseCharacter
{
    /// <summary>
    /// Bullet scene to instantiate when shooting.
    /// </summary>
    [Export]
    public PackedScene? BulletScene { get; set; }

    /// <summary>
    /// Offset from player center for bullet spawn position.
    /// </summary>
    [Export]
    public float BulletSpawnOffset { get; set; } = 20.0f;

    /// <summary>
    /// Reference to the player's current weapon (optional, for weapon system).
    /// </summary>
    [Export]
    public BaseWeapon? CurrentWeapon { get; set; }

    /// <summary>
    /// Color when at full health.
    /// </summary>
    [Export]
    public Color FullHealthColor { get; set; } = new Color(0.2f, 0.6f, 1.0f, 1.0f);

    /// <summary>
    /// Color when at low health (interpolates based on health percentage).
    /// </summary>
    [Export]
    public Color LowHealthColor { get; set; } = new Color(0.1f, 0.2f, 0.4f, 1.0f);

    /// <summary>
    /// Color to flash when hit.
    /// </summary>
    [Export]
    public Color HitFlashColor { get; set; } = new Color(1.0f, 0.3f, 0.3f, 1.0f);

    /// <summary>
    /// Duration of hit flash effect in seconds.
    /// </summary>
    [Export]
    public float HitFlashDuration { get; set; } = 0.1f;

    /// <summary>
    /// Grenade scene to instantiate when throwing.
    /// </summary>
    [Export]
    public PackedScene? GrenadeScene { get; set; }

    /// <summary>
    /// Maximum number of grenades the player can carry.
    /// </summary>
    [Export]
    public int MaxGrenades { get; set; } = 3;

    /// <summary>
    /// Reference to the player model node containing all sprites.
    /// </summary>
    private Node2D? _playerModel;

    /// <summary>
    /// References to individual sprite parts for color changes.
    /// </summary>
    private Sprite2D? _bodySprite;
    private Sprite2D? _headSprite;
    private Sprite2D? _leftArmSprite;
    private Sprite2D? _rightArmSprite;

    /// <summary>
    /// Legacy reference for compatibility (points to body sprite).
    /// </summary>
    private Sprite2D? _sprite;

    /// <summary>
    /// Current step in the reload sequence (0 = waiting for R, 1 = waiting for F, 2 = waiting for R).
    /// </summary>
    private int _reloadSequenceStep = 0;

    /// <summary>
    /// Whether the player is currently in a reload sequence.
    /// </summary>
    private bool _isReloadingSequence = false;

    /// <summary>
    /// Tracks ammo count when reload sequence started (at step 1 after R pressed).
    /// Used to determine if there was a bullet in the chamber.
    /// </summary>
    private int _ammoAtReloadStart = 0;

    /// <summary>
    /// Current number of grenades.
    /// </summary>
    private int _currentGrenades = 3;

    /// <summary>
    /// Whether the player is on the tutorial level (infinite grenades).
    /// </summary>
    private bool _isTutorialLevel = false;

    /// <summary>
    /// Grenade state machine states.
    /// 2-step mechanic:
    /// Step 1: G + RMB drag right → timer starts (pin pulled)
    /// Step 2: Hold G → press+hold RMB → release G → ready to throw (only RMB held)
    /// Step 3: Drag and release RMB → throw grenade
    /// </summary>
    private enum GrenadeState
    {
        Idle,           // No grenade action
        TimerStarted,   // Step 1 complete - grenade timer running, G held, waiting for RMB
        WaitingForGRelease, // Step 2 in progress - G+RMB held, waiting for G release
        Aiming          // Step 2 complete - only RMB held, waiting for drag and release to throw
    }

    /// <summary>
    /// Current grenade state.
    /// </summary>
    private GrenadeState _grenadeState = GrenadeState.Idle;

    /// <summary>
    /// Active grenade instance (created when timer starts).
    /// </summary>
    private RigidBody2D? _activeGrenade = null;

    /// <summary>
    /// Position where the grenade throw drag started.
    /// </summary>
    private Vector2 _grenadeDragStart = Vector2.Zero;

    /// <summary>
    /// Whether the grenade throw drag is active (for step 1).
    /// </summary>
    private bool _grenadeDragActive = false;

    /// <summary>
    /// Minimum drag distance to confirm step 1 (in pixels).
    /// </summary>
    private const float MinDragDistanceForStep1 = 30.0f;

    /// <summary>
    /// Player's rotation before throw (to restore after throw animation).
    /// </summary>
    private float _playerRotationBeforeThrow = 0.0f;

    /// <summary>
    /// Whether player is in throw rotation animation.
    /// </summary>
    private bool _isThrowRotating = false;

    /// <summary>
    /// Target rotation for throw animation.
    /// </summary>
    private float _throwTargetRotation = 0.0f;

    /// <summary>
    /// Time remaining for throw rotation to restore.
    /// </summary>
    private float _throwRotationRestoreTimer = 0.0f;

    /// <summary>
    /// Duration of throw rotation animation.
    /// </summary>
    private const float ThrowRotationDuration = 0.15f;

    #region Weapon Pose Detection

    /// <summary>
    /// Weapon types for arm positioning.
    /// </summary>
    private enum WeaponType
    {
        Rifle,      // Default - extended grip (e.g., AssaultRifle)
        SMG,        // Compact grip (e.g., MiniUzi)
        Shotgun     // Similar to rifle but slightly tighter
    }

    /// <summary>
    /// Currently detected weapon type.
    /// </summary>
    private WeaponType _currentWeaponType = WeaponType.Rifle;

    /// <summary>
    /// Whether weapon pose has been detected and applied.
    /// </summary>
    private bool _weaponPoseApplied = false;

    /// <summary>
    /// Frame counter for delayed weapon pose detection.
    /// Weapons are added by level scripts AFTER player's _Ready() completes.
    /// </summary>
    private int _weaponDetectFrameCount = 0;

    /// <summary>
    /// Number of frames to wait before detecting weapon pose.
    /// This ensures level scripts have finished adding weapons.
    /// </summary>
    private const int WeaponDetectWaitFrames = 3;

    /// <summary>
    /// Arm position offset for SMG weapons - left arm moves back toward body.
    /// UZI and similar compact SMGs should have the left arm closer to the body
    /// for a proper two-handed compact grip.
    /// </summary>
    private static readonly Vector2 SmgLeftArmOffset = new Vector2(-10, 0);

    /// <summary>
    /// Arm position offset for SMG weapons - right arm moves slightly forward.
    /// </summary>
    private static readonly Vector2 SmgRightArmOffset = new Vector2(3, 0);

    #endregion

    #region Walking Animation

    /// <summary>
    /// Walking animation speed multiplier - higher = faster leg cycle.
    /// </summary>
    [Export]
    public float WalkAnimSpeed { get; set; } = 12.0f;

    /// <summary>
    /// Scale multiplier for the player model (body, head, arms).
    /// Default is 1.3 to make the player slightly larger.
    /// </summary>
    [Export]
    public float PlayerModelScale { get; set; } = 1.3f;

    /// <summary>
    /// Walking animation intensity - higher = more pronounced movement.
    /// </summary>
    [Export]
    public float WalkAnimIntensity { get; set; } = 1.0f;

    /// <summary>
    /// Current walk animation time (accumulator for sine wave).
    /// </summary>
    private float _walkAnimTime = 0.0f;

    /// <summary>
    /// Whether the player is currently walking (for animation state).
    /// </summary>
    private bool _isWalking = false;

    /// <summary>
    /// Base positions for body parts (stored on ready for animation offsets).
    /// </summary>
    private Vector2 _baseBodyPos = Vector2.Zero;
    private Vector2 _baseHeadPos = Vector2.Zero;
    private Vector2 _baseLeftArmPos = Vector2.Zero;
    private Vector2 _baseRightArmPos = Vector2.Zero;

    #endregion

    #region Reload Animation System

    /// <summary>
    /// Animation phases for assault rifle reload sequence.
    /// Maps to the R-F-R input system for visual feedback.
    /// Three steps as requested:
    /// 1. Take magazine with left hand from chest
    /// 2. Insert magazine into rifle
    /// 3. Pull the bolt/charging handle
    /// </summary>
    private enum ReloadAnimPhase
    {
        None,           // Normal arm positions (weapon held)
        GrabMagazine,   // Step 1: Left hand moves to chest to grab new magazine
        InsertMagazine, // Step 2: Left hand brings magazine to weapon, inserts it
        PullBolt,       // Step 3: Character pulls the charging handle
        ReturnIdle      // Arms return to normal weapon-holding position
    }

    /// <summary>
    /// Current reload animation phase.
    /// </summary>
    private ReloadAnimPhase _reloadAnimPhase = ReloadAnimPhase.None;

    /// <summary>
    /// Reload animation phase timer for timed transitions.
    /// </summary>
    private float _reloadAnimTimer = 0.0f;

    /// <summary>
    /// Reload animation phase duration in seconds.
    /// </summary>
    private float _reloadAnimDuration = 0.0f;

    // Target positions for reload arm animations (relative offsets from base positions)
    // These are in local PlayerModel space
    // Base positions: LeftArm (24, 6), RightArm (-2, 6)
    // For reload, left arm goes to chest (vest/mag pouch area), then to weapon

    // Step 1: Grab magazine from chest - left arm moves toward body center
    // Base position: LeftArm (24, 6). We want target around (4, 2) = body/chest area
    // So offset should be (4-24, 2-6) = (-20, -4)
    // User feedback: previous -40 was too far (went behind back), -18 was not visible enough
    private static readonly Vector2 ReloadArmLeftGrab = new Vector2(-20, -4);      // Left hand at chest/vest mag pouch (visible but not behind back)
    private static readonly Vector2 ReloadArmRightHold = new Vector2(0, 0);        // Right hand stays on weapon grip

    // Step 2: Insert magazine - left arm moves to weapon magwell (at middle of weapon, not at the end)
    // Weapon length: ~40 pixels from center, magwell at middle
    // Base (24, 6), want target around (12, 6) = middle of weapon, so offset (-12, 0)
    private static readonly Vector2 ReloadArmLeftInsert = new Vector2(-12, 0);     // Left hand at weapon magwell (middle of weapon)
    private static readonly Vector2 ReloadArmRightSteady = new Vector2(0, 2);      // Right hand steadies weapon

    // Step 3: Pull bolt - right arm moves along rifle contour (back and forth motion)
    // The right hand should trace the rifle's right side: forward, then back to pull bolt, then release
    // Base RightArm (-2, 6). For dramatic motion: forward (+10, +2), back (-10, -4)
    private static readonly Vector2 ReloadArmLeftSupport = new Vector2(-10, 0);    // Left hand holds near magwell
    private static readonly Vector2 ReloadArmRightBoltStart = new Vector2(10, 2);  // Right hand at charging handle (forward on rifle)
    private static readonly Vector2 ReloadArmRightBoltPull = new Vector2(-12, -4); // Right hand pulls bolt back (toward player)
    private static readonly Vector2 ReloadArmRightBoltReturn = new Vector2(10, 2); // Right hand returns forward (bolt release)

    // Target rotations for reload arm animations (in degrees)
    private const float ReloadArmRotLeftGrab = -50.0f;     // Arm rotation when grabbing mag from chest
    private const float ReloadArmRotRightHold = 0.0f;      // Right arm steady during grab
    private const float ReloadArmRotLeftInsert = -15.0f;   // Left arm rotation when inserting
    private const float ReloadArmRotRightSteady = 5.0f;    // Slight tilt while steadying
    private const float ReloadArmRotLeftSupport = -10.0f;  // Left arm on foregrip/magwell
    private const float ReloadArmRotRightBoltStart = -10.0f;  // Right arm at bolt handle
    private const float ReloadArmRotRightBoltPull = -35.0f;   // Right arm rotation when pulling bolt back
    private const float ReloadArmRotRightBoltReturn = -10.0f; // Right arm rotation when releasing bolt

    // Animation durations for each reload phase (in seconds)
    // INCREASED bolt durations for visible back-and-forth motion
    private const float ReloadAnimGrabDuration = 0.25f;    // Time to grab magazine from chest
    private const float ReloadAnimInsertDuration = 0.3f;   // Time to insert magazine
    private const float ReloadAnimBoltPullDuration = 0.35f;   // Time to pull bolt back (increased for visibility)
    private const float ReloadAnimBoltReturnDuration = 0.25f; // Time for bolt to return forward (increased for visibility)
    private const float ReloadAnimReturnDuration = 0.2f;   // Time to return to idle

    /// <summary>
    /// Sub-phase for bolt pull animation (0 = pulling, 1 = returning)
    /// </summary>
    private int _boltPullSubPhase = 0;

    #endregion

    #region Grenade Animation System

    /// <summary>
    /// Animation phases for grenade throwing sequence.
    /// Maps to the multi-step input system for visual feedback.
    /// </summary>
    private enum GrenadeAnimPhase
    {
        None,           // Normal arm positions (walking/idle)
        GrabGrenade,    // Left hand moves to chest to grab grenade
        PullPin,        // Right hand pulls pin (quick snap animation)
        HandsApproach,  // Right hand moves toward left hand
        Transfer,       // Grenade transfers to right hand
        WindUp,         // Dynamic wind-up based on drag
        Throw,          // Throwing motion
        ReturnIdle      // Arms return to normal positions
    }

    /// <summary>
    /// Current grenade animation phase.
    /// </summary>
    private GrenadeAnimPhase _grenadeAnimPhase = GrenadeAnimPhase.None;

    /// <summary>
    /// Animation phase timer for timed transitions.
    /// </summary>
    private float _grenadeAnimTimer = 0.0f;

    /// <summary>
    /// Animation phase duration in seconds.
    /// </summary>
    private float _grenadeAnimDuration = 0.0f;

    /// <summary>
    /// Current wind-up intensity (0.0 = no wind-up, 1.0 = maximum wind-up).
    /// </summary>
    private float _windUpIntensity = 0.0f;

    /// <summary>
    /// Previous mouse position for velocity calculation.
    /// </summary>
    private Vector2 _prevMousePos = Vector2.Zero;

    /// <summary>
    /// Whether weapon is in sling position (lowered for grenade handling).
    /// </summary>
    private bool _weaponSlung = false;

    /// <summary>
    /// Reference to weapon mount for sling animation.
    /// </summary>
    private Node2D? _weaponMount;

    /// <summary>
    /// Base weapon mount position (for sling animation).
    /// </summary>
    private Vector2 _baseWeaponMountPos = Vector2.Zero;

    /// <summary>
    /// Base weapon mount rotation (for sling animation).
    /// </summary>
    private float _baseWeaponMountRot = 0.0f;

    // Target positions for arm animations (relative offsets from base positions)
    // These are in local PlayerModel space
    // Base positions: LeftArm (24, 6), RightArm (-2, 6)
    // Body position: (-4, 0), so left shoulder area is approximately x=0 to x=5
    // To move left arm from x=24 to shoulder (x~5), we need offset of ~-20
    // During grenade operations, left arm should be BEHIND the body (toward shoulder)
    // not holding the weapon at the front
    private static readonly Vector2 ArmLeftChest = new Vector2(-15, 0);        // Left hand moves back to chest/shoulder area to grab grenade
    private static readonly Vector2 ArmRightPin = new Vector2(2, -2);          // Right hand slightly up for pin pull
    private static readonly Vector2 ArmLeftExtended = new Vector2(-10, 2);     // Left hand at chest level with grenade (not extended forward)
    private static readonly Vector2 ArmRightApproach = new Vector2(4, 0);      // Right hand approaching left
    private static readonly Vector2 ArmLeftTransfer = new Vector2(-12, 3);     // Left hand drops back after transfer (clearly away from weapon)
    private static readonly Vector2 ArmRightHold = new Vector2(3, 1);          // Right hand holding grenade
    private static readonly Vector2 ArmRightWindMin = new Vector2(4, 3);       // Minimum wind-up position (arm back)
    private static readonly Vector2 ArmRightWindMax = new Vector2(8, 5);       // Maximum wind-up position (arm further back)
    private static readonly Vector2 ArmRightThrow = new Vector2(-4, -2);       // Throw follow-through (arm forward)
    private static readonly Vector2 ArmLeftRelaxed = new Vector2(-20, 2);      // Left arm at shoulder/body - well away from weapon during wind-up/throw

    // Target rotations for arm animations (in degrees)
    // When left arm moves back to shoulder position, rotate to point "down" relative to body
    // This makes the arm look like it's hanging at the side rather than reaching forward
    private const float ArmRotGrab = -45.0f;         // Arm rotation when grabbing at chest (points inward/down)
    private const float ArmRotPinPull = -15.0f;      // Right arm rotation when pulling pin
    private const float ArmRotLeftAtChest = -30.0f;  // Left arm rotation while holding grenade at chest
    private const float ArmRotWindMin = 15.0f;       // Right arm minimum wind-up rotation
    private const float ArmRotWindMax = 35.0f;       // Right arm maximum wind-up rotation
    private const float ArmRotThrow = -25.0f;        // Right arm throw rotation (swings forward)
    private const float ArmRotLeftRelaxed = -60.0f;  // Left arm hangs down at side during wind-up/throw (points backward)

    // Animation durations for each phase (in seconds)
    private const float AnimGrabDuration = 0.2f;
    private const float AnimPinDuration = 0.15f;
    private const float AnimApproachDuration = 0.2f;
    private const float AnimTransferDuration = 0.15f;
    private const float AnimThrowDuration = 0.2f;
    private const float AnimReturnDuration = 0.3f;

    // Animation lerp speeds
    private const float AnimLerpSpeed = 15.0f;        // Position interpolation speed
    private const float AnimLerpSpeedFast = 25.0f;    // Fast interpolation for snappy movements

    // Weapon sling position (lowered and rotated for chest carry)
    private static readonly Vector2 WeaponSlingOffset = new Vector2(0, 15);    // Lower weapon
    private const float WeaponSlingRotation = 1.2f;   // Rotate to hang down (radians, ~70 degrees)

    #endregion

    /// <summary>
    /// Signal emitted when reload sequence progresses.
    /// </summary>
    [Signal]
    public delegate void ReloadSequenceProgressEventHandler(int step, int total);

    /// <summary>
    /// Signal emitted when reload completes.
    /// </summary>
    [Signal]
    public delegate void ReloadCompletedEventHandler();

    /// <summary>
    /// Signal emitted when reload starts (first step of sequence).
    /// This signal notifies enemies that the player has begun reloading.
    /// </summary>
    [Signal]
    public delegate void ReloadStartedEventHandler();

    /// <summary>
    /// Signal emitted when player tries to shoot with empty weapon.
    /// This signal notifies enemies that the player is out of ammo.
    /// </summary>
    [Signal]
    public delegate void AmmoDepletedEventHandler();

    /// <summary>
    /// Signal emitted when grenade count changes.
    /// </summary>
    [Signal]
    public delegate void GrenadeChangedEventHandler(int current, int maximum);

    /// <summary>
    /// Signal emitted when a grenade is thrown.
    /// </summary>
    [Signal]
    public delegate void GrenadeThrownEventHandler();

    public override void _Ready()
    {
        base._Ready();

        // Get player model and sprite references for visual feedback
        _playerModel = GetNodeOrNull<Node2D>("PlayerModel");
        if (_playerModel != null)
        {
            _bodySprite = _playerModel.GetNodeOrNull<Sprite2D>("Body");
            _headSprite = _playerModel.GetNodeOrNull<Sprite2D>("Head");
            _leftArmSprite = _playerModel.GetNodeOrNull<Sprite2D>("LeftArm");
            _rightArmSprite = _playerModel.GetNodeOrNull<Sprite2D>("RightArm");
            // Legacy compatibility - _sprite points to body
            _sprite = _bodySprite;
        }
        else
        {
            // Fallback to old single sprite structure for compatibility
            _sprite = GetNodeOrNull<Sprite2D>("Sprite2D");
        }

        // Configure random health (2-4 HP)
        if (HealthComponent != null)
        {
            HealthComponent.UseRandomHealth = true;
            HealthComponent.MinRandomHealth = 2;
            HealthComponent.MaxRandomHealth = 4;
            HealthComponent.InitializeHealth();

            GD.Print($"[Player] {Name}: Spawned with health {HealthComponent.CurrentHealth}/{HealthComponent.MaxHealth}");

            // Connect to health changed signal for visual feedback
            HealthComponent.HealthChanged += OnPlayerHealthChanged;
        }

        // Update visual based on initial health
        UpdateHealthVisual();

        // Preload bullet scene if not set in inspector
        if (BulletScene == null)
        {
            // Try C# bullet scene first, fallback to GDScript version
            BulletScene = GD.Load<PackedScene>("res://scenes/projectiles/csharp/Bullet.tscn");
            if (BulletScene == null)
            {
                BulletScene = GD.Load<PackedScene>("res://scenes/projectiles/Bullet.tscn");
            }
        }

        // Get grenade scene from GrenadeManager (supports grenade type selection)
        // GrenadeManager handles the currently selected grenade type (Flashbang or Frag)
        if (GrenadeScene == null)
        {
            var grenadeManager = GetNodeOrNull("/root/GrenadeManager");
            if (grenadeManager != null && grenadeManager.HasMethod("get_current_grenade_scene"))
            {
                var sceneVariant = grenadeManager.Call("get_current_grenade_scene");
                GrenadeScene = sceneVariant.As<PackedScene>();
                if (GrenadeScene != null)
                {
                    var grenadeNameVariant = grenadeManager.Call("get_grenade_name", grenadeManager.Get("current_grenade_type"));
                    var grenadeName = grenadeNameVariant.AsString();
                    LogToFile($"[Player.Grenade] Grenade scene loaded from GrenadeManager: {grenadeName}");
                }
                else
                {
                    LogToFile($"[Player.Grenade] WARNING: GrenadeManager returned null grenade scene");
                }
            }
            else
            {
                // Fallback to flashbang if GrenadeManager is not available
                var grenadePath = "res://scenes/projectiles/FlashbangGrenade.tscn";
                GrenadeScene = GD.Load<PackedScene>(grenadePath);
                if (GrenadeScene != null)
                {
                    LogToFile($"[Player.Grenade] Grenade scene loaded from fallback: {grenadePath}");
                }
                else
                {
                    LogToFile($"[Player.Grenade] WARNING: Grenade scene not found at {grenadePath}");
                }
            }
        }
        else
        {
            LogToFile($"[Player.Grenade] Grenade scene already set in inspector");
        }

        // Detect if we're on the tutorial level
        // Tutorial level is: scenes/levels/csharp/TestTier.tscn with tutorial_level.gd script
        var currentScene = GetTree().CurrentScene;
        if (currentScene != null)
        {
            var scenePath = currentScene.SceneFilePath;
            // Tutorial level is detected by:
            // 1. Scene path contains "csharp/TestTier" (the tutorial scene)
            // 2. OR scene uses tutorial_level.gd script
            _isTutorialLevel = scenePath.Contains("csharp/TestTier");

            // Also check if the scene script is tutorial_level.gd
            var script = currentScene.GetScript();
            if (script.Obj is GodotObject scriptObj)
            {
                var scriptPath = scriptObj.Get("resource_path").AsString();
                if (scriptPath.Contains("tutorial_level"))
                {
                    _isTutorialLevel = true;
                }
            }
        }

        // Initialize grenade count based on level type
        // Tutorial: infinite grenades (max count)
        // Other levels: 1 grenade
        if (_isTutorialLevel)
        {
            _currentGrenades = MaxGrenades;
            LogToFile($"[Player.Grenade] Tutorial level detected - infinite grenades enabled");
        }
        else
        {
            _currentGrenades = 1;
            LogToFile($"[Player.Grenade] Normal level - starting with 1 grenade");
        }

        // Auto-equip weapon if not set but a weapon child exists
        if (CurrentWeapon == null)
        {
            CurrentWeapon = GetNodeOrNull<BaseWeapon>("AssaultRifle");
            if (CurrentWeapon != null)
            {
                GD.Print($"[Player] {Name}: Auto-equipped weapon {CurrentWeapon.Name}");
            }
        }

        // Store base positions for walking animation
        if (_bodySprite != null)
        {
            _baseBodyPos = _bodySprite.Position;
            LogToFile($"[Player.Init] Body sprite found at position: {_baseBodyPos}");
        }
        else
        {
            LogToFile("[Player.Init] WARNING: Body sprite NOT found!");
        }
        if (_headSprite != null)
        {
            _baseHeadPos = _headSprite.Position;
            LogToFile($"[Player.Init] Head sprite found at position: {_baseHeadPos}");
        }
        else
        {
            LogToFile("[Player.Init] WARNING: Head sprite NOT found!");
        }
        if (_leftArmSprite != null)
        {
            _baseLeftArmPos = _leftArmSprite.Position;
            LogToFile($"[Player.Init] Left arm sprite found at position: {_baseLeftArmPos}");
        }
        else
        {
            LogToFile("[Player.Init] WARNING: Left arm sprite NOT found!");
        }
        if (_rightArmSprite != null)
        {
            _baseRightArmPos = _rightArmSprite.Position;
            LogToFile($"[Player.Init] Right arm sprite found at position: {_baseRightArmPos}");
        }
        else
        {
            LogToFile("[Player.Init] WARNING: Right arm sprite NOT found!");
        }

        // Apply scale to player model for larger appearance
        if (_playerModel != null)
        {
            _playerModel.Scale = new Vector2(PlayerModelScale, PlayerModelScale);
        }

        // Get weapon mount reference for sling animation
        _weaponMount = _playerModel?.GetNodeOrNull<Node2D>("WeaponMount");
        if (_weaponMount != null)
        {
            _baseWeaponMountPos = _weaponMount.Position;
            _baseWeaponMountRot = _weaponMount.Rotation;
        }

        // Set z-index for proper layering: head should be above weapon
        // The weapon has z_index = 1, so head should be 2 or higher
        if (_headSprite != null)
        {
            _headSprite.ZIndex = 3;  // Head on top (above weapon)
        }
        if (_bodySprite != null)
        {
            _bodySprite.ZIndex = 1;  // Body same level as weapon
        }
        if (_leftArmSprite != null)
        {
            _leftArmSprite.ZIndex = 2;  // Arms between body and head
        }
        if (_rightArmSprite != null)
        {
            _rightArmSprite.ZIndex = 2;  // Arms between body and head
        }

        // Log ready status with full info
        int currentAmmo = CurrentWeapon?.CurrentAmmo ?? 0;
        int maxAmmo = CurrentWeapon?.WeaponData?.MagazineSize ?? 0;
        int currentHealth = (int)(HealthComponent?.CurrentHealth ?? 0);
        int maxHealth = (int)(HealthComponent?.MaxHealth ?? 0);
        LogToFile($"[Player] Ready! Ammo: {currentAmmo}/{maxAmmo}, Grenades: {_currentGrenades}/{MaxGrenades}, Health: {currentHealth}/{maxHealth}");
    }

    /// <summary>
    /// Called when player health changes - updates visual feedback.
    /// </summary>
    private void OnPlayerHealthChanged(float currentHealth, float maxHealth)
    {
        GD.Print($"[Player] {Name}: Health changed to {currentHealth}/{maxHealth} ({HealthComponent?.HealthPercent * 100:F0}%)");
        UpdateHealthVisual();
    }

    /// <summary>
    /// Updates the sprite color based on current health percentage.
    /// </summary>
    private void UpdateHealthVisual()
    {
        if (HealthComponent == null)
        {
            return;
        }

        // Interpolate color based on health percentage
        float healthPercent = HealthComponent.HealthPercent;
        Color color = FullHealthColor.Lerp(LowHealthColor, 1.0f - healthPercent);
        SetAllSpritesModulate(color);
    }

    /// <summary>
    /// Sets the modulate color on all player sprite parts.
    /// </summary>
    /// <param name="color">The color to apply to all sprites.</param>
    private void SetAllSpritesModulate(Color color)
    {
        if (_bodySprite != null)
        {
            _bodySprite.Modulate = color;
        }
        if (_headSprite != null)
        {
            _headSprite.Modulate = color;
        }
        if (_leftArmSprite != null)
        {
            _leftArmSprite.Modulate = color;
        }
        if (_rightArmSprite != null)
        {
            _rightArmSprite.Modulate = color;
        }
        // If using old single sprite structure
        if (_playerModel == null && _sprite != null)
        {
            _sprite.Modulate = color;
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        // Detect weapon pose after waiting a few frames for level scripts to add weapons
        if (!_weaponPoseApplied)
        {
            _weaponDetectFrameCount++;
            if (_weaponDetectFrameCount >= WeaponDetectWaitFrames)
            {
                DetectAndApplyWeaponPose();
                _weaponPoseApplied = true;
            }
        }

        Vector2 inputDirection = GetInputDirection();
        ApplyMovement(inputDirection, (float)delta);

        // Update player model rotation to face the aim direction (rifle direction)
        UpdatePlayerModelRotation();

        // Update walking animation based on movement (only if not in grenade or reload animation)
        if (_grenadeAnimPhase == GrenadeAnimPhase.None && _reloadAnimPhase == ReloadAnimPhase.None)
        {
            UpdateWalkAnimation((float)delta, inputDirection);
        }

        // Update grenade animation
        UpdateGrenadeAnimation((float)delta);

        // Update reload animation
        UpdateReloadAnimation((float)delta);

        // Handle throw rotation animation (restore player rotation after throw)
        HandleThrowRotationAnimation((float)delta);

        // Handle grenade input first (so it can consume shoot input)
        HandleGrenadeInput();

        // Make active grenade follow player if held
        if (_activeGrenade != null && IsInstanceValid(_activeGrenade))
        {
            _activeGrenade.GlobalPosition = GlobalPosition;
        }

        // Handle shooting input - support both automatic and semi-automatic weapons
        // Allow shooting when not in grenade preparation
        bool canShoot = _grenadeState == GrenadeState.Idle || _grenadeState == GrenadeState.TimerStarted;
        if (canShoot)
        {
            HandleShootingInput();
        }

        // Handle reload sequence input (R-F-R)
        HandleReloadSequenceInput();

        // Handle fire mode toggle (B key for burst/auto toggle)
        if (Input.IsActionJustPressed("toggle_fire_mode"))
        {
            ToggleFireMode();
        }
    }

    /// <summary>
    /// Handles shooting input based on weapon type.
    /// For automatic weapons: fires while held.
    /// For semi-automatic/burst: fires on press.
    /// Also handles bullet in chamber mechanics during reload sequence.
    /// </summary>
    private void HandleShootingInput()
    {
        if (CurrentWeapon == null)
        {
            // Fallback to original click-to-shoot behavior
            if (Input.IsActionJustPressed("shoot"))
            {
                Shoot();
            }
            return;
        }

        // Check if weapon is automatic (based on WeaponData)
        bool isAutomatic = CurrentWeapon.WeaponData?.IsAutomatic ?? false;

        // For AssaultRifle, also check if it's in automatic fire mode
        if (CurrentWeapon is AssaultRifle assaultRifle)
        {
            isAutomatic = assaultRifle.CurrentFireMode == FireMode.Automatic;
        }

        // Determine if shooting input is active
        bool shootInputActive = isAutomatic ? Input.IsActionPressed("shoot") : Input.IsActionJustPressed("shoot");

        if (!shootInputActive)
        {
            return;
        }

        // Check if weapon is empty before trying to shoot (not in reload sequence)
        // This notifies enemies that the player tried to shoot with no ammo
        if (!_isReloadingSequence && CurrentWeapon.CurrentAmmo <= 0)
        {
            // Emit signal to notify enemies that player is vulnerable (out of ammo)
            EmitSignal(SignalName.AmmoDepleted);
            // The weapon will play the empty click sound
        }

        // Handle shooting based on reload sequence state
        if (_isReloadingSequence)
        {
            // In reload sequence
            if (_reloadSequenceStep == 1)
            {
                // Step 1 (only R pressed, waiting for F): shooting resets the combo
                GD.Print("[Player] Shooting during reload step 1 - resetting reload sequence");
                ResetReloadSequence();
                Shoot();
            }
            else if (_reloadSequenceStep == 2)
            {
                // Step 2 (R->F pressed, waiting for final R): try to fire chamber bullet
                if (CurrentWeapon.CanFireChamberBullet)
                {
                    // Fire the chamber bullet
                    Vector2 mousePos = GetGlobalMousePosition();
                    Vector2 shootDirection = (mousePos - GlobalPosition).Normalized();

                    if (CurrentWeapon.FireChamberBullet(shootDirection))
                    {
                        GD.Print("[Player] Fired bullet in chamber during reload");
                        // Note: Sound is handled by the weapon's FireChamberBullet implementation
                    }
                }
                else if (CurrentWeapon.ChamberBulletFired)
                {
                    // Chamber bullet already fired, can't shoot until reload completes
                    GD.Print("[Player] Cannot shoot - chamber bullet already fired, wait for reload to complete");
                    PlayEmptyClickSound();
                }
                else
                {
                    // No bullet in chamber (magazine was empty when reload started)
                    GD.Print("[Player] Cannot shoot - no bullet in chamber, wait for reload to complete");
                    PlayEmptyClickSound();
                }
            }
        }
        else
        {
            // Not in reload sequence - normal shooting
            Shoot();
        }
    }

    /// <summary>
    /// Plays the empty click sound when trying to shoot without ammo.
    /// </summary>
    private void PlayEmptyClickSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_empty_click"))
        {
            audioManager.Call("play_empty_click", GlobalPosition);
        }
    }

    /// <summary>
    /// Toggles fire mode on the current weapon (if supported).
    /// </summary>
    private void ToggleFireMode()
    {
        if (CurrentWeapon is AssaultRifle assaultRifle)
        {
            assaultRifle.ToggleFireMode();
        }
    }

    /// <summary>
    /// Updates the player model rotation to face the aim direction.
    /// The player model (body, head, arms) rotates to follow the rifle's aim direction.
    /// This creates the appearance of the player rotating their whole body toward the target.
    /// </summary>
    private void UpdatePlayerModelRotation()
    {
        if (_playerModel == null)
        {
            return;
        }

        // Get the aim direction from the weapon if available
        Vector2 aimDirection;
        if (CurrentWeapon is AssaultRifle assaultRifle)
        {
            aimDirection = assaultRifle.AimDirection;
        }
        else
        {
            // Fallback: calculate direction to mouse cursor
            Vector2 mousePos = GetGlobalMousePosition();
            Vector2 toMouse = mousePos - GlobalPosition;
            if (toMouse.LengthSquared() > 0.001f)
            {
                aimDirection = toMouse.Normalized();
            }
            else
            {
                return; // No valid direction
            }
        }

        // Calculate target rotation angle
        float targetAngle = aimDirection.Angle();

        // Apply rotation to the player model
        _playerModel.Rotation = targetAngle;

        // Handle sprite flipping for left/right aim
        // When aiming left (angle > 90° or < -90°), flip vertically to avoid upside-down appearance
        bool aimingLeft = Mathf.Abs(targetAngle) > Mathf.Pi / 2;

        // Flip the player model vertically when aiming left
        if (aimingLeft)
        {
            _playerModel.Scale = new Vector2(PlayerModelScale, -PlayerModelScale);
        }
        else
        {
            _playerModel.Scale = new Vector2(PlayerModelScale, PlayerModelScale);
        }
    }

    /// <summary>
    /// Detects the equipped weapon type and applies appropriate arm positioning.
    /// Called from _PhysicsProcess() after a few frames to ensure level scripts
    /// have finished adding weapons to the player node.
    /// </summary>
    private void DetectAndApplyWeaponPose()
    {
        LogToFile($"[Player] Detecting weapon pose (frame {_weaponDetectFrameCount})...");
        var detectedType = WeaponType.Rifle;  // Default to rifle pose

        // Check for weapon children - weapons are added directly to player by level scripts
        // Check in order of specificity: MiniUzi (SMG), Shotgun, then default to Rifle
        var miniUzi = GetNodeOrNull<BaseWeapon>("MiniUzi");
        var shotgun = GetNodeOrNull<BaseWeapon>("Shotgun");

        if (miniUzi != null)
        {
            detectedType = WeaponType.SMG;
            LogToFile("[Player] Detected weapon: Mini UZI (SMG pose)");
        }
        else if (shotgun != null)
        {
            detectedType = WeaponType.Shotgun;
            LogToFile("[Player] Detected weapon: Shotgun (Shotgun pose)");
        }
        else
        {
            // Default to rifle (AssaultRifle or no weapon)
            detectedType = WeaponType.Rifle;
            LogToFile("[Player] Detected weapon: Rifle (default pose)");
        }

        _currentWeaponType = detectedType;
        ApplyWeaponArmOffsets();
    }

    /// <summary>
    /// Applies arm position offsets based on current weapon type.
    /// Modifies base arm positions to create appropriate weapon-holding poses.
    /// </summary>
    private void ApplyWeaponArmOffsets()
    {
        // Original positions from Player.tscn: LeftArm (24, 6), RightArm (-2, 6)
        var originalLeftArmPos = new Vector2(24, 6);
        var originalRightArmPos = new Vector2(-2, 6);

        switch (_currentWeaponType)
        {
            case WeaponType.SMG:
                // SMG pose: Compact two-handed grip
                // Left arm moves back toward body for shorter weapon
                // Right arm moves forward slightly to meet left hand
                _baseLeftArmPos = originalLeftArmPos + SmgLeftArmOffset;
                _baseRightArmPos = originalRightArmPos + SmgRightArmOffset;
                LogToFile($"[Player] Applied SMG arm pose: Left={_baseLeftArmPos}, Right={_baseRightArmPos}");
                break;

            case WeaponType.Shotgun:
                // Shotgun pose: Similar to rifle but slightly tighter
                _baseLeftArmPos = originalLeftArmPos + new Vector2(-3, 0);
                _baseRightArmPos = originalRightArmPos + new Vector2(1, 0);
                LogToFile($"[Player] Applied Shotgun arm pose: Left={_baseLeftArmPos}, Right={_baseRightArmPos}");
                break;

            case WeaponType.Rifle:
            default:
                // Rifle pose: Standard extended grip (original positions)
                _baseLeftArmPos = originalLeftArmPos;
                _baseRightArmPos = originalRightArmPos;
                LogToFile($"[Player] Applied Rifle arm pose: Left={_baseLeftArmPos}, Right={_baseRightArmPos}");
                break;
        }

        // Apply new base positions to sprites immediately
        if (_leftArmSprite != null)
        {
            _leftArmSprite.Position = _baseLeftArmPos;
        }
        if (_rightArmSprite != null)
        {
            _rightArmSprite.Position = _baseRightArmPos;
        }
    }

    /// <summary>
    /// Gets the normalized input direction from player input.
    /// </summary>
    /// <returns>Normalized direction vector.</returns>
    private Vector2 GetInputDirection()
    {
        Vector2 direction = Vector2.Zero;
        direction.X = Input.GetAxis("move_left", "move_right");
        direction.Y = Input.GetAxis("move_up", "move_down");

        // Normalize to prevent faster diagonal movement
        if (direction.Length() > 1.0f)
        {
            direction = direction.Normalized();
        }

        return direction;
    }

    /// <summary>
    /// Updates the walking animation based on player movement state.
    /// Creates a natural bobbing motion for body parts during movement.
    /// </summary>
    /// <param name="delta">Time since last frame.</param>
    /// <param name="inputDirection">Current movement input direction.</param>
    private void UpdateWalkAnimation(float delta, Vector2 inputDirection)
    {
        bool isMoving = inputDirection != Vector2.Zero || Velocity.Length() > 10.0f;

        if (isMoving)
        {
            // Accumulate animation time based on movement speed
            float speedFactor = Velocity.Length() / MaxSpeed;
            _walkAnimTime += delta * WalkAnimSpeed * speedFactor;
            _isWalking = true;

            // Calculate animation offsets using sine waves
            // Body bobs up and down (frequency = 2x for double step)
            float bodyBob = Mathf.Sin(_walkAnimTime * 2.0f) * 1.5f * WalkAnimIntensity;

            // Head bobs slightly less than body (dampened)
            float headBob = Mathf.Sin(_walkAnimTime * 2.0f) * 0.8f * WalkAnimIntensity;

            // Arms swing opposite to each other (alternating)
            float armSwing = Mathf.Sin(_walkAnimTime) * 3.0f * WalkAnimIntensity;

            // Apply offsets to sprites
            if (_bodySprite != null)
            {
                _bodySprite.Position = _baseBodyPos + new Vector2(0, bodyBob);
            }

            if (_headSprite != null)
            {
                _headSprite.Position = _baseHeadPos + new Vector2(0, headBob);
            }

            if (_leftArmSprite != null)
            {
                // Left arm swings forward/back (y-axis in top-down)
                _leftArmSprite.Position = _baseLeftArmPos + new Vector2(armSwing, 0);
            }

            if (_rightArmSprite != null)
            {
                // Right arm swings opposite to left arm
                _rightArmSprite.Position = _baseRightArmPos + new Vector2(-armSwing, 0);
            }
        }
        else
        {
            // Return to idle pose smoothly
            if (_isWalking)
            {
                _isWalking = false;
                _walkAnimTime = 0.0f;
            }

            // Interpolate back to base positions
            float lerpSpeed = 10.0f * delta;
            if (_bodySprite != null)
            {
                _bodySprite.Position = _bodySprite.Position.Lerp(_baseBodyPos, lerpSpeed);
            }
            if (_headSprite != null)
            {
                _headSprite.Position = _headSprite.Position.Lerp(_baseHeadPos, lerpSpeed);
            }
            if (_leftArmSprite != null)
            {
                _leftArmSprite.Position = _leftArmSprite.Position.Lerp(_baseLeftArmPos, lerpSpeed);
            }
            if (_rightArmSprite != null)
            {
                _rightArmSprite.Position = _rightArmSprite.Position.Lerp(_baseRightArmPos, lerpSpeed);
            }
        }
    }

    /// <summary>
    /// Handles the R-F-R reload sequence input.
    /// Step 0: Press R to start sequence (eject magazine)
    /// Step 1: Press F to continue (insert new magazine)
    /// Step 2: Press R to complete reload instantly (chamber round)
    ///
    /// Bullet in chamber mechanics:
    /// - At step 1 (R pressed): shooting resets the combo
    /// - At step 2 (R->F pressed): if previous magazine had ammo, one chamber bullet can be fired
    /// - After reload: if chamber bullet was fired, subtract one from new magazine
    ///
    /// Note: This reload sequence is skipped for weapons that use tube magazines (like Shotgun),
    /// which have their own shell-by-shell reload mechanism via RMB drag gestures.
    /// </summary>
    private void HandleReloadSequenceInput()
    {
        if (CurrentWeapon == null)
        {
            return;
        }

        // Skip R-F-R reload sequence for weapons that use tube magazines (like Shotgun)
        // These weapons have their own reload mechanism (shell-by-shell via RMB gestures)
        // Pressing R key should be ignored for these weapons to avoid breaking ammo tracking
        if (CurrentWeapon is Shotgun)
        {
            return;
        }

        // Can't reload if magazine is full (and not in reload sequence)
        if (!_isReloadingSequence && CurrentWeapon.CurrentAmmo >= (CurrentWeapon.WeaponData?.MagazineSize ?? 0))
        {
            return;
        }

        // Can't reload if no reserve ammo (and not in reload sequence)
        if (!_isReloadingSequence && CurrentWeapon.ReserveAmmo <= 0)
        {
            return;
        }

        // Handle R key (first and third step)
        if (Input.IsActionJustPressed("reload"))
        {
            if (_reloadSequenceStep == 0 || _reloadSequenceStep == 1)
            {
                // Check if we can start a new reload (need ammo or already in sequence)
                if (_reloadSequenceStep == 0)
                {
                    // Starting fresh - check conditions
                    if (CurrentWeapon.CurrentAmmo >= (CurrentWeapon.WeaponData?.MagazineSize ?? 0))
                    {
                        return; // Magazine is full
                    }
                    if (CurrentWeapon.ReserveAmmo <= 0)
                    {
                        return; // No reserve ammo
                    }
                }

                // Start or restart reload sequence
                // This handles both initial R press and R->R sequence (restart)
                _isReloadingSequence = true;
                _reloadSequenceStep = 1;
                _ammoAtReloadStart = CurrentWeapon.CurrentAmmo;
                GD.Print($"[Player] Reload sequence started (R pressed) - ammo at start: {_ammoAtReloadStart} - press F next");
                // Start animation: Step 1 - Grab magazine from chest
                StartReloadAnimPhase(ReloadAnimPhase.GrabMagazine, ReloadAnimGrabDuration);
                // Play magazine out sound
                PlayReloadMagOutSound();
                EmitSignal(SignalName.ReloadSequenceProgress, 1, 3);
                // Notify enemies that player has started reloading (vulnerable state)
                EmitSignal(SignalName.ReloadStarted);
            }
            else if (_reloadSequenceStep == 2)
            {
                // Complete reload sequence - instant reload!
                // Start animation: Step 3 - Pull bolt/charging handle (back and forth motion)
                StartReloadAnimPhase(ReloadAnimPhase.PullBolt, ReloadAnimBoltPullDuration);
                // Play bolt cycling sound
                PlayM16BoltSound();
                CompleteReloadSequence();
            }
        }

        // Handle F key (reload_step action - second step)
        if (Input.IsActionJustPressed("reload_step"))
        {
            if (_reloadSequenceStep == 1)
            {
                // Continue to next step - set up chamber bullet
                _reloadSequenceStep = 2;

                // Set up bullet in chamber based on ammo at reload start
                bool hadAmmoInMagazine = _ammoAtReloadStart > 0;
                CurrentWeapon.StartReloadSequence(hadAmmoInMagazine);

                GD.Print($"[Player] Reload sequence step 2 (F pressed) - bullet in chamber: {hadAmmoInMagazine} - press R to complete");
                // Start animation: Step 2 - Insert magazine into rifle
                StartReloadAnimPhase(ReloadAnimPhase.InsertMagazine, ReloadAnimInsertDuration);
                // Play magazine in sound
                PlayReloadMagInSound();
                EmitSignal(SignalName.ReloadSequenceProgress, 2, 3);
            }
            else if (_isReloadingSequence)
            {
                // Wrong key pressed, reset sequence
                GD.Print("[Player] Wrong key! Reload sequence reset (expected R)");
                // Restart animation from grab phase
                StartReloadAnimPhase(ReloadAnimPhase.GrabMagazine, ReloadAnimGrabDuration);
                ResetReloadSequence();
            }
        }
    }

    /// <summary>
    /// Plays the magazine out sound (first reload step).
    /// </summary>
    private void PlayReloadMagOutSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_reload_mag_out"))
        {
            audioManager.Call("play_reload_mag_out", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the magazine in sound (second reload step).
    /// </summary>
    private void PlayReloadMagInSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_reload_mag_in"))
        {
            audioManager.Call("play_reload_mag_in", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the M16 bolt cycling sound (third reload step).
    /// </summary>
    private void PlayM16BoltSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_m16_bolt"))
        {
            audioManager.Call("play_m16_bolt", GlobalPosition);
        }
    }

    /// <summary>
    /// Completes the reload sequence, instantly reloading the weapon.
    /// </summary>
    private void CompleteReloadSequence()
    {
        if (CurrentWeapon == null)
        {
            return;
        }

        // Perform instant reload
        CurrentWeapon.InstantReload();

        GD.Print("[Player] Reload sequence complete! Magazine refilled instantly.");
        EmitSignal(SignalName.ReloadSequenceProgress, 3, 3);
        EmitSignal(SignalName.ReloadCompleted);

        ResetReloadSequence();
    }

    /// <summary>
    /// Resets the reload sequence to the beginning.
    /// Also cancels the weapon's reload sequence state.
    /// </summary>
    private void ResetReloadSequence()
    {
        _reloadSequenceStep = 0;
        _isReloadingSequence = false;
        _ammoAtReloadStart = 0;

        // Return arms to idle if reload animation was active
        if (_reloadAnimPhase != ReloadAnimPhase.None)
        {
            StartReloadAnimPhase(ReloadAnimPhase.ReturnIdle, ReloadAnimReturnDuration);
        }

        // Cancel weapon's reload sequence state
        CurrentWeapon?.CancelReloadSequence();
    }

    /// <summary>
    /// Gets whether the player is currently in a reload sequence.
    /// </summary>
    public bool IsReloadingSequence => _isReloadingSequence;

    /// <summary>
    /// Gets the current reload sequence step (0-2).
    /// </summary>
    public int ReloadSequenceStep => _reloadSequenceStep;

    /// <summary>
    /// Fires a bullet towards the mouse cursor.
    /// Uses weapon system if available, otherwise uses direct bullet spawning.
    /// </summary>
    private void Shoot()
    {
        // Calculate direction towards mouse cursor
        Vector2 mousePos = GetGlobalMousePosition();
        Vector2 shootDirection = (mousePos - GlobalPosition).Normalized();

        // If we have a weapon equipped, use it
        if (CurrentWeapon != null)
        {
            CurrentWeapon.Fire(shootDirection);
            return;
        }

        // Otherwise use direct bullet spawning (original behavior)
        SpawnBullet(shootDirection);
    }

    /// <summary>
    /// Spawns a bullet directly without using the weapon system.
    /// Preserves the original template behavior.
    /// </summary>
    /// <param name="direction">Direction for the bullet to travel.</param>
    private void SpawnBullet(Vector2 direction)
    {
        if (BulletScene == null)
        {
            return;
        }

        // Create bullet instance
        var bullet = BulletScene.Instantiate<Node2D>();

        // Set bullet position with offset in shoot direction
        bullet.GlobalPosition = GlobalPosition + direction * BulletSpawnOffset;

        // Set bullet direction
        bullet.Set("Direction", direction);

        // Set shooter ID to prevent self-damage
        bullet.Set("ShooterId", GetInstanceId());

        // Add bullet to the scene tree
        GetTree().CurrentScene.AddChild(bullet);
    }

    /// <summary>
    /// Called when hit by a projectile via hit_area.gd.
    /// This method name follows GDScript naming convention for cross-language compatibility
    /// with the hit detection system that uses has_method("on_hit") checks.
    /// </summary>
    public void on_hit()
    {
        TakeDamage(1);
    }

    /// <inheritdoc/>
    public override void TakeDamage(float amount)
    {
        if (HealthComponent == null || !IsAlive)
        {
            return;
        }

        GD.Print($"[Player] {Name}: Taking {amount} damage. Current health: {HealthComponent.CurrentHealth}");

        // Show hit flash effect
        ShowHitFlash();

        // Determine if this hit will be lethal before applying damage
        bool willBeFatal = HealthComponent.CurrentHealth <= amount;

        // Play appropriate hit sound
        if (willBeFatal)
        {
            PlayHitLethalSound();
        }
        else
        {
            PlayHitNonLethalSound();
        }

        base.TakeDamage(amount);
    }

    /// <summary>
    /// Plays the lethal hit sound when player dies.
    /// </summary>
    private void PlayHitLethalSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_hit_lethal"))
        {
            audioManager.Call("play_hit_lethal", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the non-lethal hit sound when player is damaged but survives.
    /// </summary>
    private void PlayHitNonLethalSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_hit_non_lethal"))
        {
            audioManager.Call("play_hit_non_lethal", GlobalPosition);
        }
    }

    /// <summary>
    /// Shows a brief flash effect when hit.
    /// </summary>
    private async void ShowHitFlash()
    {
        if (_playerModel == null && _sprite == null)
        {
            return;
        }

        SetAllSpritesModulate(HitFlashColor);

        await ToSignal(GetTree().CreateTimer(HitFlashDuration), "timeout");

        // Restore color based on current health (if still alive)
        if (HealthComponent != null && HealthComponent.IsAlive)
        {
            UpdateHealthVisual();
        }
    }

    /// <inheritdoc/>
    public override void OnDeath()
    {
        base.OnDeath();
        // Handle player death
        GD.Print("Player died!");
    }

    /// <summary>
    /// Equips a new weapon.
    /// </summary>
    /// <param name="weapon">The weapon to equip.</param>
    public void EquipWeapon(BaseWeapon weapon)
    {
        // Unequip current weapon if any
        if (CurrentWeapon != null && CurrentWeapon.GetParent() == this)
        {
            RemoveChild(CurrentWeapon);
        }

        CurrentWeapon = weapon;

        // Add weapon as child if not already in scene tree
        if (CurrentWeapon.GetParent() == null)
        {
            AddChild(CurrentWeapon);
        }
    }

    /// <summary>
    /// Unequips the current weapon.
    /// </summary>
    public void UnequipWeapon()
    {
        if (CurrentWeapon != null && CurrentWeapon.GetParent() == this)
        {
            RemoveChild(CurrentWeapon);
        }
        CurrentWeapon = null;
    }

    #region Grenade System

    /// <summary>
    /// Handle grenade input with 2-step mechanic.
    /// Step 1: G + RMB drag right → starts 4s timer (pin pulled)
    /// Step 2: Hold G → press+hold RMB → release G → ready to throw (only RMB held)
    /// Step 3: Drag and release RMB → throw grenade
    /// </summary>
    private void HandleGrenadeInput()
    {
        // Check for active grenade explosion (explodes in hand after 4 seconds)
        if (_activeGrenade != null && !IsInstanceValid(_activeGrenade))
        {
            // Grenade exploded while held - return arms to idle
            StartGrenadeAnimPhase(GrenadeAnimPhase.ReturnIdle, AnimReturnDuration);
            ResetGrenadeState();
            return;
        }

        switch (_grenadeState)
        {
            case GrenadeState.Idle:
                HandleGrenadeIdleState();
                break;
            case GrenadeState.TimerStarted:
                HandleGrenadeTimerStartedState();
                break;
            case GrenadeState.WaitingForGRelease:
                HandleGrenadeWaitingForGReleaseState();
                break;
            case GrenadeState.Aiming:
                HandleGrenadeAimingState();
                break;
        }
    }

    /// <summary>
    /// Handle grenade input in Idle state.
    /// Waiting for G + RMB drag right to start timer (Step 1).
    /// </summary>
    private void HandleGrenadeIdleState()
    {
        // Start grab animation when G is first pressed (check before the is_action_pressed block)
        if (Input.IsActionJustPressed("grenade_prepare") && _currentGrenades > 0)
        {
            StartGrenadeAnimPhase(GrenadeAnimPhase.GrabGrenade, AnimGrabDuration);
            LogToFile("[Player.Grenade] G pressed - starting grab animation");
        }

        // Check if G key is held and player has grenades
        if (Input.IsActionPressed("grenade_prepare") && _currentGrenades > 0)
        {
            // Check if RMB was just pressed (start of drag)
            if (Input.IsActionJustPressed("grenade_throw"))
            {
                _grenadeDragStart = GetGlobalMousePosition();
                _grenadeDragActive = true;
                LogToFile($"[Player.Grenade] Step 1 started: G held, RMB pressed at {_grenadeDragStart}");
            }

            // Check if RMB was released (end of drag)
            if (_grenadeDragActive && Input.IsActionJustReleased("grenade_throw"))
            {
                Vector2 dragEnd = GetGlobalMousePosition();
                Vector2 dragVector = dragEnd - _grenadeDragStart;

                // Check if drag was to the right and long enough
                if (dragVector.X > MinDragDistanceForStep1)
                {
                    StartGrenadeTimer();
                    // Start pull pin animation
                    StartGrenadeAnimPhase(GrenadeAnimPhase.PullPin, AnimPinDuration);
                    LogToFile($"[Player.Grenade] Step 1 complete! Drag: {dragVector}");
                }
                else
                {
                    LogToFile($"[Player.Grenade] Step 1 failed: drag not far enough right ({dragVector.X} < {MinDragDistanceForStep1})");
                }
                _grenadeDragActive = false;
            }
        }
        else
        {
            _grenadeDragActive = false;
            // If G was released and we were in grab animation, return to idle
            if (_grenadeAnimPhase == GrenadeAnimPhase.GrabGrenade)
            {
                StartGrenadeAnimPhase(GrenadeAnimPhase.ReturnIdle, AnimReturnDuration);
            }
        }
    }

    /// <summary>
    /// Handle grenade input in TimerStarted state.
    /// Waiting for RMB to be pressed while G is held (Step 2 part 1).
    /// </summary>
    private void HandleGrenadeTimerStartedState()
    {
        // If G is released, drop grenade at feet
        if (!Input.IsActionPressed("grenade_prepare"))
        {
            LogToFile("[Player.Grenade] G released - dropping grenade at feet");
            DropGrenadeAtFeet();
            return;
        }

        // Check if RMB is pressed to enter WaitingForGRelease state
        if (Input.IsActionJustPressed("grenade_throw"))
        {
            _grenadeState = GrenadeState.WaitingForGRelease;
            // Start hands approach animation
            StartGrenadeAnimPhase(GrenadeAnimPhase.HandsApproach, AnimApproachDuration);
            LogToFile("[Player.Grenade] Step 2 part 1: G+RMB held - now release G to ready the throw");
        }
    }

    /// <summary>
    /// Handle grenade input in WaitingForGRelease state.
    /// G+RMB are both held, waiting for G to be released (Step 2 part 2).
    /// </summary>
    private void HandleGrenadeWaitingForGReleaseState()
    {
        // If RMB is released before G, go back to TimerStarted
        if (!Input.IsActionPressed("grenade_throw"))
        {
            _grenadeState = GrenadeState.TimerStarted;
            LogToFile("[Player.Grenade] RMB released before G - back to waiting for RMB");
            return;
        }

        // If G is released while RMB is still held, enter Aiming state
        if (!Input.IsActionPressed("grenade_prepare"))
        {
            _grenadeState = GrenadeState.Aiming;
            _grenadeDragStart = GetGlobalMousePosition();
            _prevMousePos = _grenadeDragStart;
            // Start transfer animation (grenade to throwing hand)
            StartGrenadeAnimPhase(GrenadeAnimPhase.Transfer, AnimTransferDuration);
            LogToFile("[Player.Grenade] Step 2 complete: G released, RMB held - now aiming, drag and release RMB to throw");
        }
    }

    /// <summary>
    /// Handle grenade input in Aiming state.
    /// Only RMB is held (G was released), waiting for drag and release to throw.
    /// </summary>
    private void HandleGrenadeAimingState()
    {
        // In this state, G is already released (that's how we got here)
        // We only care about RMB

        // Transition from transfer to wind-up after transfer completes
        if (_grenadeAnimPhase == GrenadeAnimPhase.Transfer && _grenadeAnimTimer <= 0)
        {
            StartGrenadeAnimPhase(GrenadeAnimPhase.WindUp, 0); // Wind-up is continuous
            LogToFile("[Player.Grenade.Anim] Entered wind-up phase");
        }

        // Update wind-up intensity while in wind-up phase
        if (_grenadeAnimPhase == GrenadeAnimPhase.WindUp)
        {
            UpdateWindUpIntensity();
        }

        // If RMB is released, throw the grenade
        if (Input.IsActionJustReleased("grenade_throw"))
        {
            // Start throw animation
            StartGrenadeAnimPhase(GrenadeAnimPhase.Throw, AnimThrowDuration);
            Vector2 dragEnd = GetGlobalMousePosition();
            ThrowGrenade(dragEnd);
        }
    }

    /// <summary>
    /// Start the grenade timer (step 1 complete - pin pulled).
    /// Creates the grenade instance and starts its 4-second fuse.
    /// </summary>
    private void StartGrenadeTimer()
    {
        if (_currentGrenades <= 0)
        {
            LogToFile("[Player.Grenade] Cannot start timer: no grenades");
            return;
        }

        if (GrenadeScene == null)
        {
            LogToFile("[Player.Grenade] Cannot start timer: GrenadeScene is null");
            return;
        }

        // Create grenade instance (held by player)
        _activeGrenade = GrenadeScene.Instantiate<RigidBody2D>();
        if (_activeGrenade == null)
        {
            LogToFile("[Player.Grenade] Failed to instantiate grenade scene");
            return;
        }

        // Add grenade to scene first (must be in tree before setting GlobalPosition)
        GetTree().CurrentScene.AddChild(_activeGrenade);

        // Set position AFTER AddChild (GlobalPosition only works when node is in the scene tree)
        _activeGrenade.GlobalPosition = GlobalPosition;

        // Activate the grenade timer (starts 4s countdown)
        if (_activeGrenade.HasMethod("activate_timer"))
        {
            _activeGrenade.Call("activate_timer");
        }

        _grenadeState = GrenadeState.TimerStarted;

        // Decrement grenade count now (pin is pulled) - but not on tutorial level (infinite)
        if (!_isTutorialLevel)
        {
            _currentGrenades--;
        }
        EmitSignal(SignalName.GrenadeChanged, _currentGrenades, MaxGrenades);

        // Play grenade prepare sound
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_grenade_prepare"))
        {
            audioManager.Call("play_grenade_prepare", GlobalPosition);
        }

        LogToFile($"[Player.Grenade] Timer started, grenade created at {GlobalPosition}");
    }

    /// <summary>
    /// Drop the grenade at player's feet (when G is released before throwing).
    /// </summary>
    private void DropGrenadeAtFeet()
    {
        if (_activeGrenade != null && IsInstanceValid(_activeGrenade))
        {
            // Set position to current player position before unfreezing
            _activeGrenade.GlobalPosition = GlobalPosition;
            // Unfreeze the grenade so physics works and it can explode
            _activeGrenade.Freeze = false;
            // The grenade stays where it is (at player's feet)
            LogToFile($"[Player.Grenade] Grenade dropped at feet at {_activeGrenade.GlobalPosition} (unfrozen)");
        }
        // Start return animation
        StartGrenadeAnimPhase(GrenadeAnimPhase.ReturnIdle, AnimReturnDuration);
        ResetGrenadeState();
    }

    /// <summary>
    /// Reset grenade state to idle.
    /// </summary>
    private void ResetGrenadeState()
    {
        _grenadeState = GrenadeState.Idle;
        _grenadeDragActive = false;
        _grenadeDragStart = Vector2.Zero;
        // Don't null out _activeGrenade - it's now an independent object in the scene
        _activeGrenade = null;
        // Reset wind-up intensity
        _windUpIntensity = 0.0f;
    }

    /// <summary>
    /// Throw the grenade based on aiming drag direction and distance.
    /// Includes player rotation animation to prevent grenade hitting player.
    /// </summary>
    /// <param name="dragEnd">The end position of the drag.</param>
    private void ThrowGrenade(Vector2 dragEnd)
    {
        if (_activeGrenade == null || !IsInstanceValid(_activeGrenade))
        {
            LogToFile("[Player.Grenade] Cannot throw: no active grenade");
            ResetGrenadeState();
            return;
        }

        // Calculate throw direction and distance from drag
        Vector2 dragVector = dragEnd - _grenadeDragStart;
        float dragDistance = dragVector.Length();

        // Direction is the drag direction (normalized)
        Vector2 throwDirection = dragVector.Normalized();

        // If drag is too short, use a minimum distance for the throw
        if (dragDistance < 10.0f)
        {
            // Default to throwing forward (towards mouse from player)
            throwDirection = (GetGlobalMousePosition() - GlobalPosition).Normalized();
            dragDistance = 50.0f; // Minimum throw distance
        }

        // Pass raw drag distance to grenade - GDScript handles the speed calculation
        // The grenade's drag_to_speed_multiplier controls the sensitivity
        LogToFile($"[Player.Grenade] Throwing! Direction: {throwDirection}, Drag distance: {dragDistance}");

        // Rotate player to face throw direction (prevents grenade hitting player when throwing upward)
        RotatePlayerForThrow(throwDirection);

        // IMPORTANT: Set grenade position to player's CURRENT position (not where it was activated)
        // Offset grenade spawn position in throw direction to avoid collision with player
        float spawnOffset = 60.0f; // Increased from 30 to 60 pixels in front of player to avoid hitting
        Vector2 spawnPosition = GlobalPosition + throwDirection * spawnOffset;
        _activeGrenade.GlobalPosition = spawnPosition;

        // Call the throw method on the grenade with raw drag distance
        if (_activeGrenade.HasMethod("throw_grenade"))
        {
            _activeGrenade.Call("throw_grenade", throwDirection, dragDistance);
        }

        // Emit signal
        EmitSignal(SignalName.GrenadeThrown);

        // Play grenade throw sound
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_grenade_throw"))
        {
            audioManager.Call("play_grenade_throw", GlobalPosition);
        }

        LogToFile($"[Player.Grenade] Thrown! Direction: {throwDirection}, Drag distance: {dragDistance}");

        // Reset state (grenade is now independent)
        ResetGrenadeState();
    }

    /// <summary>
    /// Rotate player to face throw direction (with swing animation).
    /// Prevents grenade from hitting player when throwing upward.
    /// </summary>
    /// <param name="throwDirection">The direction of the throw.</param>
    private void RotatePlayerForThrow(Vector2 throwDirection)
    {
        // Store current rotation to restore later
        _playerRotationBeforeThrow = Rotation;

        // Calculate target rotation (face throw direction)
        _throwTargetRotation = throwDirection.Angle();

        // Apply rotation immediately
        Rotation = _throwTargetRotation;

        // Start restore timer
        _isThrowRotating = true;
        _throwRotationRestoreTimer = ThrowRotationDuration;

        LogToFile($"[Player.Grenade] Player rotated for throw: {_playerRotationBeforeThrow} -> {_throwTargetRotation}");
    }

    /// <summary>
    /// Handle throw rotation animation - restore player rotation after throw.
    /// </summary>
    /// <param name="delta">Time since last frame.</param>
    private void HandleThrowRotationAnimation(float delta)
    {
        if (!_isThrowRotating)
        {
            return;
        }

        _throwRotationRestoreTimer -= delta;
        if (_throwRotationRestoreTimer <= 0)
        {
            // Restore original rotation
            Rotation = _playerRotationBeforeThrow;
            _isThrowRotating = false;
            LogToFile($"[Player.Grenade] Player rotation restored to {_playerRotationBeforeThrow}");
        }
    }

    /// <summary>
    /// Get current grenade count.
    /// </summary>
    public int GetCurrentGrenades()
    {
        return _currentGrenades;
    }

    /// <summary>
    /// Get maximum grenade count.
    /// </summary>
    public int GetMaxGrenades()
    {
        return MaxGrenades;
    }

    /// <summary>
    /// Add grenades to inventory (e.g., from pickup).
    /// </summary>
    /// <param name="count">Number of grenades to add.</param>
    public void AddGrenades(int count)
    {
        _currentGrenades = Mathf.Min(_currentGrenades + count, MaxGrenades);
        EmitSignal(SignalName.GrenadeChanged, _currentGrenades, MaxGrenades);
    }

    /// <summary>
    /// Check if player is preparing to throw a grenade.
    /// </summary>
    public bool IsPreparingGrenade()
    {
        return _grenadeState != GrenadeState.Idle;
    }

    #endregion

    #region Grenade Animation Methods

    /// <summary>
    /// Start a new grenade animation phase.
    /// </summary>
    /// <param name="phase">The GrenadeAnimPhase to transition to.</param>
    /// <param name="duration">How long this phase should last (for timed phases).</param>
    private void StartGrenadeAnimPhase(GrenadeAnimPhase phase, float duration)
    {
        _grenadeAnimPhase = phase;
        _grenadeAnimTimer = duration;
        _grenadeAnimDuration = duration;

        // Enable weapon sling when handling grenade
        if (phase != GrenadeAnimPhase.None && phase != GrenadeAnimPhase.ReturnIdle)
        {
            _weaponSlung = true;
        }
        // RETURN_IDLE will unset _weaponSlung when animation completes

        LogToFile($"[Player.Grenade.Anim] Phase changed to: {phase} (duration: {duration:F2}s)");
    }

    /// <summary>
    /// Update grenade animation based on current phase.
    /// Called every frame from _PhysicsProcess.
    /// </summary>
    /// <param name="delta">Time since last frame.</param>
    private void UpdateGrenadeAnimation(float delta)
    {
        // Early exit if no animation active
        if (_grenadeAnimPhase == GrenadeAnimPhase.None)
        {
            // Restore normal z-index when not animating
            RestoreArmZIndex();
            return;
        }

        // Update phase timer
        if (_grenadeAnimTimer > 0)
        {
            _grenadeAnimTimer -= delta;
        }

        // Calculate animation progress (0.0 to 1.0)
        float progress = 1.0f;
        if (_grenadeAnimDuration > 0)
        {
            progress = Mathf.Clamp(1.0f - (_grenadeAnimTimer / _grenadeAnimDuration), 0.0f, 1.0f);
        }

        // Calculate target positions based on current phase
        Vector2 leftArmTarget = _baseLeftArmPos;
        Vector2 rightArmTarget = _baseRightArmPos;
        float leftArmRot = 0.0f;
        float rightArmRot = 0.0f;
        float lerpSpeed = AnimLerpSpeed * delta;

        // Set arms to lower z-index during grenade operations (below weapon)
        // This ensures arms appear below the weapon as user requested
        SetGrenadeAnimZIndex();

        switch (_grenadeAnimPhase)
        {
            case GrenadeAnimPhase.GrabGrenade:
                // Left arm moves back to shoulder/chest area (away from weapon) to grab grenade
                // Large negative X offset pulls the arm from weapon front (x=24) toward body (x~5)
                leftArmTarget = _baseLeftArmPos + ArmLeftChest;
                leftArmRot = Mathf.DegToRad(ArmRotGrab);
                lerpSpeed = AnimLerpSpeedFast * delta;
                break;

            case GrenadeAnimPhase.PullPin:
                // Left hand holds grenade at chest level, right hand pulls pin
                leftArmTarget = _baseLeftArmPos + ArmLeftExtended;
                leftArmRot = Mathf.DegToRad(ArmRotLeftAtChest);
                rightArmTarget = _baseRightArmPos + ArmRightPin;
                rightArmRot = Mathf.DegToRad(ArmRotPinPull);
                lerpSpeed = AnimLerpSpeedFast * delta;
                break;

            case GrenadeAnimPhase.HandsApproach:
                // Both hands at chest level, preparing for transfer
                leftArmTarget = _baseLeftArmPos + ArmLeftExtended;
                leftArmRot = Mathf.DegToRad(ArmRotLeftAtChest);
                rightArmTarget = _baseRightArmPos + ArmRightApproach;
                break;

            case GrenadeAnimPhase.Transfer:
                // Left arm drops back toward body, right hand takes grenade
                leftArmTarget = _baseLeftArmPos + ArmLeftTransfer;
                leftArmRot = Mathf.DegToRad(ArmRotLeftRelaxed * 0.5f);
                rightArmTarget = _baseRightArmPos + ArmRightHold;
                lerpSpeed = AnimLerpSpeed * delta;
                break;

            case GrenadeAnimPhase.WindUp:
                // LEFT ARM: Fully retracted to shoulder/body area, hangs at side
                // This is the key position - arm must be clearly NOT on the weapon
                leftArmTarget = _baseLeftArmPos + ArmLeftRelaxed;
                leftArmRot = Mathf.DegToRad(ArmRotLeftRelaxed);
                // RIGHT ARM: Interpolate between min and max wind-up based on intensity
                Vector2 windUpOffset = ArmRightWindMin.Lerp(ArmRightWindMax, _windUpIntensity);
                rightArmTarget = _baseRightArmPos + windUpOffset;
                float windUpRot = Mathf.Lerp(ArmRotWindMin, ArmRotWindMax, _windUpIntensity);
                rightArmRot = Mathf.DegToRad(windUpRot);
                lerpSpeed = AnimLerpSpeedFast * delta; // Responsive to input
                break;

            case GrenadeAnimPhase.Throw:
                // Throwing motion - right arm swings forward, left stays at body
                leftArmTarget = _baseLeftArmPos + ArmLeftRelaxed;
                leftArmRot = Mathf.DegToRad(ArmRotLeftRelaxed);
                rightArmTarget = _baseRightArmPos + ArmRightThrow;
                rightArmRot = Mathf.DegToRad(ArmRotThrow);
                lerpSpeed = AnimLerpSpeedFast * delta;

                // When throw animation completes, transition to return
                if (_grenadeAnimTimer <= 0)
                {
                    StartGrenadeAnimPhase(GrenadeAnimPhase.ReturnIdle, AnimReturnDuration);
                }
                break;

            case GrenadeAnimPhase.ReturnIdle:
                // Arms returning to base positions (back to holding weapon)
                leftArmTarget = _baseLeftArmPos;
                rightArmTarget = _baseRightArmPos;
                lerpSpeed = AnimLerpSpeed * delta;

                // When return animation completes, end animation
                if (_grenadeAnimTimer <= 0)
                {
                    _grenadeAnimPhase = GrenadeAnimPhase.None;
                    _weaponSlung = false;
                    RestoreArmZIndex();
                    LogToFile("[Player.Grenade.Anim] Animation complete, returning to normal");
                }
                break;
        }

        // Apply arm positions with smooth interpolation
        if (_leftArmSprite != null)
        {
            _leftArmSprite.Position = _leftArmSprite.Position.Lerp(leftArmTarget, lerpSpeed);
            _leftArmSprite.Rotation = Mathf.Lerp(_leftArmSprite.Rotation, leftArmRot, lerpSpeed);
        }

        if (_rightArmSprite != null)
        {
            _rightArmSprite.Position = _rightArmSprite.Position.Lerp(rightArmTarget, lerpSpeed);
            _rightArmSprite.Rotation = Mathf.Lerp(_rightArmSprite.Rotation, rightArmRot, lerpSpeed);
        }

        // Update weapon sling animation
        UpdateWeaponSling(delta);
    }

    /// <summary>
    /// Set arm z-index for grenade animation (arms below weapon).
    /// </summary>
    private void SetGrenadeAnimZIndex()
    {
        // During grenade operations, arms should appear below the weapon
        // Weapon has z_index = 1, so set arms to 0
        if (_leftArmSprite != null)
        {
            _leftArmSprite.ZIndex = 0;
        }
        if (_rightArmSprite != null)
        {
            _rightArmSprite.ZIndex = 0;
        }
    }

    /// <summary>
    /// Restore normal arm z-index (arms above weapon for normal aiming).
    /// </summary>
    private void RestoreArmZIndex()
    {
        // Normal state: arms at z_index 2 (between body and head)
        if (_leftArmSprite != null)
        {
            _leftArmSprite.ZIndex = 2;
        }
        if (_rightArmSprite != null)
        {
            _rightArmSprite.ZIndex = 2;
        }
    }

    /// <summary>
    /// Update weapon sling position (lower weapon when handling grenade).
    /// </summary>
    /// <param name="delta">Time since last frame.</param>
    private void UpdateWeaponSling(float delta)
    {
        if (_weaponMount == null)
        {
            return;
        }

        Vector2 targetPos = _baseWeaponMountPos;
        float targetRot = _baseWeaponMountRot;

        if (_weaponSlung)
        {
            // Lower weapon to chest/sling position
            targetPos = _baseWeaponMountPos + WeaponSlingOffset;
            targetRot = _baseWeaponMountRot + WeaponSlingRotation;
        }

        float lerpSpeed = AnimLerpSpeed * delta;
        _weaponMount.Position = _weaponMount.Position.Lerp(targetPos, lerpSpeed);
        _weaponMount.Rotation = Mathf.Lerp(_weaponMount.Rotation, targetRot, lerpSpeed);
    }

    /// <summary>
    /// Update wind-up intensity based on mouse drag distance during aiming.
    /// </summary>
    private void UpdateWindUpIntensity()
    {
        Vector2 currentMouse = GetGlobalMousePosition();

        // Calculate drag distance from aim start
        Vector2 dragVector = currentMouse - _grenadeDragStart;
        float dragDistance = dragVector.Length();

        // Get viewport for max drag calculation
        var viewport = GetViewport();
        float maxDrag = 600.0f; // Default max drag distance
        if (viewport != null)
        {
            maxDrag = viewport.GetVisibleRect().Size.X * 0.5f;
        }

        // Calculate base intensity from distance
        float intensity = Mathf.Clamp(dragDistance / maxDrag, 0.0f, 1.0f);

        // Add velocity component for more responsive feel
        Vector2 mouseDelta = currentMouse - _prevMousePos;
        float mouseVelocity = mouseDelta.Length();
        float velocityBonus = Mathf.Clamp(mouseVelocity / 50.0f, 0.0f, 0.2f);

        _windUpIntensity = Mathf.Clamp(intensity + velocityBonus, 0.0f, 1.0f);
        _prevMousePos = currentMouse;
    }

    #endregion

    #region Reload Animation Methods

    /// <summary>
    /// Start a new reload animation phase.
    /// </summary>
    /// <param name="phase">The ReloadAnimPhase to transition to.</param>
    /// <param name="duration">How long this phase should last.</param>
    private void StartReloadAnimPhase(ReloadAnimPhase phase, float duration)
    {
        _reloadAnimPhase = phase;
        _reloadAnimTimer = duration;
        _reloadAnimDuration = duration;

        // Reset bolt pull sub-phase when entering bolt pull phase
        if (phase == ReloadAnimPhase.PullBolt)
        {
            _boltPullSubPhase = 0;
        }

        LogToFile($"[Player.Reload.Anim] Phase changed to: {phase} (duration: {duration:F2}s)");
    }

    /// <summary>
    /// Set arm z-index for reload animation (arms BELOW weapon).
    /// User feedback: animated hand should be below weapon, not above it.
    /// </summary>
    private void SetReloadAnimZIndex()
    {
        // During reload operations, arms should appear BELOW the weapon
        // Weapon has z_index = 1, so set arms to 0
        if (_leftArmSprite != null)
        {
            _leftArmSprite.ZIndex = 0;
        }
        if (_rightArmSprite != null)
        {
            _rightArmSprite.ZIndex = 0;
        }
    }

    /// <summary>
    /// Update reload animation based on current phase.
    /// Called every frame from _PhysicsProcess.
    /// </summary>
    /// <param name="delta">Time since last frame.</param>
    private void UpdateReloadAnimation(float delta)
    {
        // Early exit if no animation active
        if (_reloadAnimPhase == ReloadAnimPhase.None)
        {
            // Restore normal z-index when not animating
            RestoreArmZIndex();
            return;
        }

        // Update phase timer
        if (_reloadAnimTimer > 0)
        {
            _reloadAnimTimer -= delta;
        }

        // Calculate target positions based on current phase
        Vector2 leftArmTarget = _baseLeftArmPos;
        Vector2 rightArmTarget = _baseRightArmPos;
        float leftArmRot = 0.0f;
        float rightArmRot = 0.0f;
        float lerpSpeed = AnimLerpSpeed * delta;

        // Set arms to lower z-index during reload operations (BELOW weapon)
        // User feedback: "animated hand should be below weapon, not above it"
        SetReloadAnimZIndex();

        switch (_reloadAnimPhase)
        {
            case ReloadAnimPhase.GrabMagazine:
                // Step 1: Left arm moves to chest to grab new magazine
                leftArmTarget = _baseLeftArmPos + ReloadArmLeftGrab;
                leftArmRot = Mathf.DegToRad(ReloadArmRotLeftGrab);
                rightArmTarget = _baseRightArmPos + ReloadArmRightHold;
                rightArmRot = Mathf.DegToRad(ReloadArmRotRightHold);
                lerpSpeed = AnimLerpSpeedFast * delta;
                break;

            case ReloadAnimPhase.InsertMagazine:
                // Step 2: Left arm brings magazine to weapon magwell (at middle of weapon)
                // User feedback: "step 2 should end at middle of weapon length, not at the end"
                leftArmTarget = _baseLeftArmPos + ReloadArmLeftInsert;
                leftArmRot = Mathf.DegToRad(ReloadArmRotLeftInsert);
                rightArmTarget = _baseRightArmPos + ReloadArmRightSteady;
                rightArmRot = Mathf.DegToRad(ReloadArmRotRightSteady);
                lerpSpeed = AnimLerpSpeed * delta;
                break;

            case ReloadAnimPhase.PullBolt:
                // Step 3: Right hand traces rifle contour - back and forth motion
                // User feedback: "step 3 should be a movement along the rifle contour
                // right towards and away from oneself (back and forth)"
                leftArmTarget = _baseLeftArmPos + ReloadArmLeftSupport;
                leftArmRot = Mathf.DegToRad(ReloadArmRotLeftSupport);

                if (_boltPullSubPhase == 0)
                {
                    // Sub-phase 0: Pull bolt back (toward player)
                    rightArmTarget = _baseRightArmPos + ReloadArmRightBoltPull;
                    rightArmRot = Mathf.DegToRad(ReloadArmRotRightBoltPull);
                    lerpSpeed = AnimLerpSpeedFast * delta;

                    // Log bolt pull progress periodically
                    if (Engine.GetFramesDrawn() % 30 == 0)
                    {
                        LogToFile($"[Player.Reload.Anim] Bolt sub-phase 0 (pull back): timer={_reloadAnimTimer:F2}s, rightArm target={rightArmTarget}");
                    }

                    // When pull back completes, transition to return forward
                    if (_reloadAnimTimer <= 0)
                    {
                        _boltPullSubPhase = 1;
                        _reloadAnimTimer = ReloadAnimBoltReturnDuration;
                        _reloadAnimDuration = ReloadAnimBoltReturnDuration;
                        LogToFile($"[Player.Reload.Anim] Bolt sub-phase transition: pull→return (duration: {ReloadAnimBoltReturnDuration:F2}s)");
                    }
                }
                else
                {
                    // Sub-phase 1: Release bolt (return forward)
                    rightArmTarget = _baseRightArmPos + ReloadArmRightBoltReturn;
                    rightArmRot = Mathf.DegToRad(ReloadArmRotRightBoltReturn);
                    lerpSpeed = AnimLerpSpeedFast * delta;

                    // Log bolt return progress periodically
                    if (Engine.GetFramesDrawn() % 30 == 0)
                    {
                        LogToFile($"[Player.Reload.Anim] Bolt sub-phase 1 (return): timer={_reloadAnimTimer:F2}s, rightArm target={rightArmTarget}");
                    }

                    // When return completes, transition to return idle
                    if (_reloadAnimTimer <= 0)
                    {
                        LogToFile("[Player.Reload.Anim] Bolt animation complete, transitioning to idle");
                        StartReloadAnimPhase(ReloadAnimPhase.ReturnIdle, ReloadAnimReturnDuration);
                    }
                }
                break;

            case ReloadAnimPhase.ReturnIdle:
                // Arms returning to base positions
                leftArmTarget = _baseLeftArmPos;
                rightArmTarget = _baseRightArmPos;
                leftArmRot = 0.0f;
                rightArmRot = 0.0f;
                lerpSpeed = AnimLerpSpeed * delta;

                // When return animation completes, end animation and restore z-index
                if (_reloadAnimTimer <= 0)
                {
                    _reloadAnimPhase = ReloadAnimPhase.None;
                    RestoreArmZIndex();
                    LogToFile("[Player.Reload.Anim] Animation complete, returning to normal");
                }
                break;
        }

        // Apply arm positions with smooth interpolation
        if (_leftArmSprite != null)
        {
            Vector2 oldPos = _leftArmSprite.Position;
            _leftArmSprite.Position = _leftArmSprite.Position.Lerp(leftArmTarget, lerpSpeed);
            _leftArmSprite.Rotation = Mathf.Lerp(_leftArmSprite.Rotation, leftArmRot, lerpSpeed);

            // Log arm position changes periodically (every 60 frames = ~1 second)
            if (Engine.GetFramesDrawn() % 60 == 0)
            {
                LogToFile($"[Player.Reload.Anim] LeftArm: pos={_leftArmSprite.Position}, target={leftArmTarget}, base={_baseLeftArmPos}");
            }
        }
        else if (Engine.GetFramesDrawn() % 60 == 0)
        {
            LogToFile("[Player.Reload.Anim] WARNING: Left arm sprite is null during animation!");
        }

        if (_rightArmSprite != null)
        {
            Vector2 oldPos = _rightArmSprite.Position;
            _rightArmSprite.Position = _rightArmSprite.Position.Lerp(rightArmTarget, lerpSpeed);
            _rightArmSprite.Rotation = Mathf.Lerp(_rightArmSprite.Rotation, rightArmRot, lerpSpeed);

            // Log arm position changes periodically (every 60 frames = ~1 second)
            if (Engine.GetFramesDrawn() % 60 == 0)
            {
                LogToFile($"[Player.Reload.Anim] RightArm: pos={_rightArmSprite.Position}, target={rightArmTarget}, base={_baseRightArmPos}");
            }
        }
        else if (Engine.GetFramesDrawn() % 60 == 0)
        {
            LogToFile("[Player.Reload.Anim] WARNING: Right arm sprite is null during animation!");
        }
    }

    #endregion

    #region Logging

    /// <summary>
    /// Logs a message to the FileLogger (GDScript autoload) for debugging.
    /// </summary>
    /// <param name="message">The message to log.</param>
    private void LogToFile(string message)
    {
        // Print to console
        GD.Print(message);

        // Also log to FileLogger if available
        var fileLogger = GetNodeOrNull("/root/FileLogger");
        if (fileLogger != null && fileLogger.HasMethod("log_info"))
        {
            fileLogger.Call("log_info", message);
        }
    }

    #endregion
}
