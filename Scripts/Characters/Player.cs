using Godot;
using System;
using System.Collections.Generic;
using GodotTopDownTemplate.AbstractClasses;
using GodotTopDownTemplate.Weapons;
using GodotTopdown.Scripts.Projectiles;

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
    /// Reference to the CasingPusher Area2D for detecting shell casings (Issue #392).
    /// </summary>
    private Area2D? _casingPusher;

    /// <summary>
    /// Force to apply to casings when pushed by player walking over them (Issue #392, #424).
    /// Reduced by 2.5x from 50.0 to 20.0 for Issue #424.
    /// </summary>
    private const float CasingPushForce = 20.0f;

    /// <summary>
    /// List of casings currently overlapping with the CasingPusher Area2D (Issue #392 Iteration 8).
    /// Uses signal-based tracking for reliable detection from all directions.
    /// </summary>
    private readonly System.Collections.Generic.List<RigidBody2D> _overlappingCasings = new();

    /// <summary>
    /// Current step in the reload sequence (0 = waiting for R, 1 = waiting for F, 2 = waiting for R).
    /// </summary>
    private int _reloadSequenceStep = 0;

    /// <summary>
    /// Whether the player is currently in a reload sequence.
    /// </summary>
    private bool _isReloadingSequence = false;

    /// <summary>
    /// Whether a semi-automatic shoot input has been buffered.
    /// When the player clicks while the fire timer is still active,
    /// the click is buffered and consumed as soon as the weapon can fire.
    /// This prevents lost inputs when clicking faster than the fire rate allows.
    /// </summary>
    private bool _semiAutoShootBuffered = false;

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
        Aiming,         // Step 2 complete - only RMB held, waiting for drag and release to throw
        SimpleAiming    // Simple mode: RMB held, showing trajectory preview
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
    /// Position where aiming started (for simple mode trajectory).
    /// </summary>
    private Vector2 _aimDragStart = Vector2.Zero;

    /// <summary>
    /// Timestamp when grenade timer was started.
    /// </summary>
    private double _grenadeTimerStartTime = 0.0;

    /// <summary>
    /// Whether player is currently preparing to throw a grenade (for animations).
    /// </summary>
    private bool _isPreparingGrenade = false;

    /// <summary>
    /// Player's rotation before throw (to restore after throw animation).
    /// </summary>
    private float _playerRotationBeforeThrow = 0.0f;

    /// <summary>
    /// Whether player is in throw rotation animation.
    /// </summary>
    private bool _isThrowRotating = false;

    /// <summary>
    /// Whether debug mode is enabled (F7 toggle, shows grenade trajectory).
    /// </summary>
    private bool _debugModeEnabled = false;

    /// <summary>
    /// Whether invincibility mode is enabled (F6 toggle, player takes no damage).
    /// </summary>
    private bool _invincibilityEnabled = false;

    /// <summary>
    /// Label for displaying invincibility mode indicator.
    /// </summary>
    private Label? _invincibilityLabel = null;

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
        Shotgun,    // Similar to rifle but slightly tighter
        Pistol,     // Compact one-handed/two-handed pistol grip (e.g., SilencedPistol)
        Sniper      // Extended heavy grip (e.g., ASVK SniperRifle)
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
    /// Mouse velocity history for smooth velocity calculation (stores last N velocities).
    /// Used to get stable velocity at moment of release.
    /// </summary>
    private List<Vector2> _mouseVelocityHistory = new List<Vector2>();

    /// <summary>
    /// Maximum number of velocity samples to keep in history.
    /// </summary>
    private const int MouseVelocityHistorySize = 5;

    /// <summary>
    /// Current calculated mouse velocity (pixels per second).
    /// </summary>
    private Vector2 _currentMouseVelocity = Vector2.Zero;

    /// <summary>
    /// Total swing distance traveled during aiming (for momentum transfer calculation).
    /// </summary>
    private float _totalSwingDistance = 0.0f;

    /// <summary>
    /// Previous frame time for delta calculation in velocity tracking.
    /// </summary>
    private double _prevFrameTime = 0.0;

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

    #region Flashlight System (Issue #546)

    /// <summary>
    /// Path to the flashlight effect scene.
    /// </summary>
    private const string FlashlightScenePath = "res://scenes/effects/FlashlightEffect.tscn";

    /// <summary>
    /// Whether the flashlight is equipped (active item selected in armory).
    /// </summary>
    private bool _flashlightEquipped = false;

    /// <summary>
    /// Reference to the flashlight effect node (child of PlayerModel).
    /// </summary>
    private Node2D? _flashlightNode = null;

    /// <summary>
    /// Whether the GDScript methods (turn_on/turn_off) are available on the flashlight node.
    /// If false, C# directly controls the PointLight2D as a fallback.
    /// </summary>
    private bool _flashlightHasScript = false;

    /// <summary>
    /// Direct reference to the PointLight2D child (used as fallback when GDScript not loaded).
    /// </summary>
    private PointLight2D? _flashlightPointLight = null;

    /// <summary>
    /// Whether the flashlight is currently on (tracked in C# for fallback mode).
    /// </summary>
    private bool _flashlightIsOn = false;

    /// <summary>
    /// Light energy when the flashlight is on (matches flashlight_effect.gd LIGHT_ENERGY).
    /// </summary>
    private const float FlashlightEnergy = 8.0f;

    #endregion

    #region Teleport Bracers System (Issue #672)

    /// <summary>
    /// Whether teleport bracers are equipped (active item selected in armory).
    /// </summary>
    private bool _teleportBracersEquipped = false;

    /// <summary>
    /// Whether the player is currently aiming the teleport (Space held).
    /// </summary>
    private bool _teleportAiming = false;

    /// <summary>
    /// Current number of teleport charges remaining.
    /// </summary>
    private int _teleportCharges = 6;

    /// <summary>
    /// Maximum number of teleport charges.
    /// </summary>
    private const int MaxTeleportCharges = 6;

    /// <summary>
    /// The computed safe teleport target position (updated each frame while aiming).
    /// </summary>
    private Vector2 _teleportTargetPosition = Vector2.Zero;

    /// <summary>
    /// Player collision radius for teleport safety checks (matches Player.tscn CircleShape2D).
    /// </summary>
    private const float PlayerCollisionRadius = 16.0f;

    /// <summary>
    /// Signal emitted when teleport charges change.
    /// </summary>
    [Signal]
    public delegate void TeleportChargesChangedEventHandler(int current, int maximum);

    #endregion

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

        // Configure health based on difficulty
        if (HealthComponent != null)
        {
            // Check if Power Fantasy mode is active for special health configuration
            var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
            bool isPowerFantasy = difficultyManager != null && (bool)difficultyManager.Call("is_power_fantasy_mode");

            if (isPowerFantasy)
            {
                // Power Fantasy mode: 10 HP (fixed, not random)
                HealthComponent.UseRandomHealth = false;
                HealthComponent.MaxHealth = 10;
                HealthComponent.InitialHealth = 10;
                HealthComponent.InitializeHealth();
                GD.Print($"[Player] {Name}: Power Fantasy mode - spawned with {HealthComponent.CurrentHealth}/{HealthComponent.MaxHealth} HP");
            }
            else
            {
                // Normal difficulties: random health (2-4 HP)
                HealthComponent.UseRandomHealth = true;
                HealthComponent.MinRandomHealth = 2;
                HealthComponent.MaxRandomHealth = 4;
                HealthComponent.InitializeHealth();
                GD.Print($"[Player] {Name}: Spawned with health {HealthComponent.CurrentHealth}/{HealthComponent.MaxHealth}");
            }

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
            // Try MakarovPM first (default starting weapon), then AssaultRifle for backward compatibility
            CurrentWeapon = GetNodeOrNull<BaseWeapon>("MakarovPM");
            if (CurrentWeapon == null)
            {
                CurrentWeapon = GetNodeOrNull<BaseWeapon>("AssaultRifle");
            }
            if (CurrentWeapon != null)
            {
                GD.Print($"[Player] {Name}: Auto-equipped weapon {CurrentWeapon.Name}");
            }
        }

        // Apply weapon selection from GameManager (C# fallback for GDScript level scripts)
        // This ensures weapon selection works even when GDScript level scripts fail to execute
        // due to Godot 4.3 binary tokenization issues (godotengine/godot#94150, #96065)
        ApplySelectedWeaponFromGameManager();

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

        // Connect to GameManager's debug mode signal for F7 toggle
        ConnectDebugModeSignal();

        // Initialize CasingPusher Area2D for pushing shell casings (Issue #392 Iteration 8)
        ConnectCasingPusherSignals();

        // Initialize flashlight if active item manager has flashlight selected (Issue #546)
        InitFlashlight();

        // Initialize teleport bracers if active item manager has them selected (Issue #672)
        InitTeleportBracers();

        // Initialize breaker bullets if active item manager has them selected (Issue #678)
        InitBreakerBullets();

        // Log ready status with full info
        int currentAmmo = CurrentWeapon?.CurrentAmmo ?? 0;
        int maxAmmo = CurrentWeapon?.WeaponData?.MagazineSize ?? 0;
        int currentHealth = (int)(HealthComponent?.CurrentHealth ?? 0);
        int maxHealth = (int)(HealthComponent?.MaxHealth ?? 0);
        LogToFile($"[Player] Ready! Ammo: {currentAmmo}/{maxAmmo}, Grenades: {_currentGrenades}/{MaxGrenades}, Health: {currentHealth}/{maxHealth}");
        LogToFile("[Player.Grenade] Throwing system: VELOCITY-BASED (v2.0 - mouse velocity at release)");
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
    /// Public method to refresh the health visual.
    /// Called by effects managers (like LastChanceEffectsManager) after they finish
    /// modifying player sprite colors, to ensure the player returns to correct
    /// health-based coloring.
    /// </summary>
    public void RefreshHealthVisual()
    {
        UpdateHealthVisual();
    }

    /// <summary>
    /// Sets the modulate color on all player sprite parts.
    /// The armband is a separate sibling sprite (not child of RightArm) that keeps
    /// its original color, so all body parts use the same health-based color.
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
            // Right arm uses the same color as other body parts.
            // The armband is now a separate sibling sprite (Armband node under PlayerModel)
            // that doesn't inherit this modulate, keeping its bright red color visible.
            _rightArmSprite.Modulate = color;
        }
        // If using old single sprite structure
        if (_playerModel == null && _sprite != null)
        {
            _sprite.Modulate = color;
        }
    }

    #region Casing Pusher (Issue #392)

    /// <summary>
    /// Connects the CasingPusher Area2D signals for reliable casing detection (Issue #392 Iteration 8).
    /// Using body_entered/body_exited signals instead of polling get_overlapping_bodies()
    /// ensures casings are detected even when player approaches from narrow side.
    /// </summary>
    private void ConnectCasingPusherSignals()
    {
        _casingPusher = GetNodeOrNull<Area2D>("CasingPusher");
        if (_casingPusher == null)
        {
            // CasingPusher not present in scene - this is fine for older scenes
            return;
        }

        // Connect body_entered and body_exited signals
        _casingPusher.BodyEntered += OnCasingPusherBodyEntered;
        _casingPusher.BodyExited += OnCasingPusherBodyExited;
    }

    /// <summary>
    /// Called when a body enters the CasingPusher Area2D.
    /// Tracks casings for reliable pushing detection.
    /// </summary>
    private void OnCasingPusherBodyEntered(Node2D body)
    {
        if (body is RigidBody2D rigidBody && rigidBody.HasMethod("receive_kick"))
        {
            if (!_overlappingCasings.Contains(rigidBody))
            {
                _overlappingCasings.Add(rigidBody);
            }
        }
    }

    /// <summary>
    /// Called when a body exits the CasingPusher Area2D.
    /// Removes casings from tracking list.
    /// </summary>
    private void OnCasingPusherBodyExited(Node2D body)
    {
        if (body is RigidBody2D rigidBody)
        {
            _overlappingCasings.Remove(rigidBody);
        }
    }

    /// <summary>
    /// Pushes casings that we're overlapping with using Area2D detection (Issue #392 Iteration 8).
    /// Uses signal-tracked casings combined with polling for maximum reliability.
    /// </summary>
    private void PushCasingsWithArea2D()
    {
        if (_casingPusher == null)
        {
            return;
        }

        // Don't push if not moving
        if (Velocity.LengthSquared() < 1.0f)
        {
            return;
        }

        // Combine both signal-tracked casings and polled overlapping bodies for reliability
        var casingsToPush = new System.Collections.Generic.HashSet<RigidBody2D>();

        // Add signal-tracked casings
        foreach (var casing in _overlappingCasings)
        {
            if (IsInstanceValid(casing))
            {
                casingsToPush.Add(casing);
            }
        }

        // Also poll for any casings that might have been missed by signals
        foreach (var body in _casingPusher.GetOverlappingBodies())
        {
            if (body is RigidBody2D rigidBody && rigidBody.HasMethod("receive_kick"))
            {
                casingsToPush.Add(rigidBody);
            }
        }

        // Push all detected casings
        foreach (var casing in casingsToPush)
        {
            // Calculate push direction from player center to casing position (Issue #424)
            // This makes casings fly away based on which side they're pushed from
            var pushDir = (casing.GlobalPosition - GlobalPosition).Normalized();
            var pushStrength = Velocity.Length() * CasingPushForce / 100.0f;
            var impulse = pushDir * pushStrength;
            casing.Call("receive_kick", impulse);
        }
    }

    #endregion

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

        // Push any casings we're overlapping with using Area2D detection (Issue #392 Iteration 8)
        PushCasingsWithArea2D();

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

        // Handle sniper scope input (RMB) when SniperRifle is equipped
        // This takes priority over grenade input since the sniper uses RMB for scoping
        bool sniperScopeConsumedInput = HandleSniperScopeInput();

        // Handle grenade input first (so it can consume shoot input)
        // Skip if sniper scope already consumed the RMB input
        if (!sniperScopeConsumedInput)
        {
            HandleGrenadeInput();
        }

        // Make active grenade follow player if held
        if (_activeGrenade != null && IsInstanceValid(_activeGrenade))
        {
            _activeGrenade.GlobalPosition = GlobalPosition;
        }

        // Handle shooting input - support both automatic and semi-automatic weapons
        // Allow shooting when not in grenade preparation
        // In simple mode, RMB is for grenades so only LMB (shoot) should work
        bool canShoot = _grenadeState == GrenadeState.Idle || _grenadeState == GrenadeState.TimerStarted || _grenadeState == GrenadeState.SimpleAiming;
        if (canShoot)
        {
            HandleShootingInput();
        }

        // Handle revolver manual hammer cocking with RMB (Issue #649)
        // RMB instantly cocks the hammer so the next LMB fires without delay.
        // Only when not preparing grenade (G not held) and not in sniper scope.
        if (CurrentWeapon is Revolver revolverForCock && !sniperScopeConsumedInput
            && _grenadeState == GrenadeState.Idle
            && Input.IsActionJustPressed("grenade_throw"))
        {
            revolverForCock.ManualCockHammer();
        }

        // Handle revolver multi-step cylinder reload (Issue #626)
        // Must be checked before standard reload to prevent R-F-R sequence from intercepting
        if (CurrentWeapon is Revolver)
        {
            HandleRevolverReloadInput();
        }
        else
        {
            // Handle reload sequence input (R-F-R) for non-revolver weapons
            HandleReloadSequenceInput();
        }

        // Handle fire mode toggle (B key for burst/auto toggle)
        if (Input.IsActionJustPressed("toggle_fire_mode"))
        {
            ToggleFireMode();
        }

        // Handle flashlight input (hold Space to turn on, release to turn off) (Issue #546)
        HandleFlashlightInput();

        // Handle teleport bracers input (hold Space to aim, release to teleport) (Issue #672)
        HandleTeleportBracersInput();
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

        // For semi-automatic weapons, buffer click inputs so fast clicking works.
        // When the player clicks while the fire timer is still active, the click
        // is buffered and consumed as soon as the weapon can fire again.
        // This prevents lost inputs when clicking faster than the fire rate allows.
        if (!isAutomatic && Input.IsActionJustPressed("shoot"))
        {
            _semiAutoShootBuffered = true;
        }

        // Determine if shooting input is active
        bool shootInputActive;
        if (isAutomatic)
        {
            shootInputActive = Input.IsActionPressed("shoot");
        }
        else
        {
            // For semi-auto: fire if we have a buffered click and weapon can fire
            shootInputActive = _semiAutoShootBuffered && CurrentWeapon.CanFire;
        }

        if (!shootInputActive)
        {
            return;
        }

        // Consume the buffered input for semi-auto weapons
        if (!isAutomatic)
        {
            _semiAutoShootBuffered = false;
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
    /// TACTICAL RELOAD (Issue #437): During shotgun reload OR when RMB is held (dragging),
    /// player model rotation is locked to allow the player to keep aiming at a specific
    /// spot while performing reload gestures.
    ///
    /// FIX (Issue #437 feedback): Lock rotation as soon as RMB is pressed, not just when
    /// reload state changes. This prevents barrel/player shift during quick one-motion
    /// reload gestures (drag up then down without releasing RMB).
    /// </summary>
    private void UpdatePlayerModelRotation()
    {
        if (_playerModel == null)
        {
            return;
        }

        // TACTICAL RELOAD (Issue #437): Don't rotate player model during shotgun reload
        // OR when dragging (RMB is held). This ensures the player freezes immediately
        // when RMB is pressed, before any state change occurs.
        var shotgun = GetNodeOrNull<Shotgun>("Shotgun");
        if (shotgun != null && (shotgun.ReloadState != ShotgunReloadState.NotReloading || shotgun.IsDragging))
        {
            // Keep current rotation locked - don't follow mouse
            return;
        }

        // TACTICAL RELOAD for revolver (Issue #626): Lock rotation while cylinder is open
        // or when dragging (RMB held for cartridge insertion gesture).
        var revolverForRotation = GetNodeOrNull<Revolver>("Revolver");
        if (revolverForRotation != null && revolverForRotation.ReloadState != RevolverReloadState.NotReloading)
        {
            // Keep current rotation locked during cylinder reload
            return;
        }

        // Get the aim direction from the weapon if available
        Vector2 aimDirection;
        if (CurrentWeapon is AssaultRifle assaultRifle)
        {
            aimDirection = assaultRifle.AimDirection;
        }
        else if (CurrentWeapon is SniperRifle sniperRifle)
        {
            aimDirection = sniperRifle.AimDirection;
        }
        else if (CurrentWeapon is Revolver revolver)
        {
            aimDirection = revolver.AimDirection;
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
        // Check in order of specificity: SniperRifle, MiniUzi (SMG), Shotgun, SilencedPistol, MakarovPM, then default to Rifle
        var sniperRifle = GetNodeOrNull<BaseWeapon>("SniperRifle");
        var miniUzi = GetNodeOrNull<BaseWeapon>("MiniUzi");
        var shotgun = GetNodeOrNull<BaseWeapon>("Shotgun");
        var silencedPistol = GetNodeOrNull<BaseWeapon>("SilencedPistol");
        var makarovPM = GetNodeOrNull<BaseWeapon>("MakarovPM");
        var revolver = GetNodeOrNull<BaseWeapon>("Revolver");

        if (sniperRifle != null)
        {
            detectedType = WeaponType.Sniper;
            LogToFile("[Player] Detected weapon: ASVK Sniper Rifle (Sniper pose)");
        }
        else if (miniUzi != null)
        {
            detectedType = WeaponType.SMG;
            LogToFile("[Player] Detected weapon: Mini UZI (SMG pose)");
        }
        else if (shotgun != null)
        {
            detectedType = WeaponType.Shotgun;
            LogToFile("[Player] Detected weapon: Shotgun (Shotgun pose)");
        }
        else if (revolver != null)
        {
            detectedType = WeaponType.Pistol;
            LogToFile("[Player] Detected weapon: RSh-12 Revolver (Pistol pose)");
        }
        else if (silencedPistol != null)
        {
            detectedType = WeaponType.Pistol;
            LogToFile("[Player] Detected weapon: Silenced Pistol (Pistol pose)");
        }
        else if (makarovPM != null)
        {
            detectedType = WeaponType.Pistol;
            LogToFile("[Player] Detected weapon: Makarov PM (Pistol pose)");
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

            case WeaponType.Pistol:
                // Pistol pose: Two-handed pistol grip (Weaver/Isoceles stance)
                // Extended forward so the pistol is held away from body
                // Left arm supports under the right hand
                // Right arm extends forward for aiming
                _baseLeftArmPos = originalLeftArmPos + new Vector2(-8, 0);  // Extended forward (was -14)
                _baseRightArmPos = originalRightArmPos + new Vector2(6, 0);  // Further forward for aiming (was 4)
                LogToFile($"[Player] Applied Pistol arm pose: Left={_baseLeftArmPos}, Right={_baseRightArmPos}");
                break;

            case WeaponType.Sniper:
                // Sniper pose: Extended forward grip for long heavy weapon (ASVK)
                // Left arm reaches further forward to support the heavy barrel
                // Right arm stays close to body for stable trigger control
                _baseLeftArmPos = originalLeftArmPos + new Vector2(4, 0);
                _baseRightArmPos = originalRightArmPos + new Vector2(-1, 0);
                LogToFile($"[Player] Applied Sniper arm pose: Left={_baseLeftArmPos}, Right={_baseRightArmPos}");
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
    /// When the sniper rifle is bolt cycling, only WASD keys are used for movement.
    /// Arrow keys are reserved for the bolt-action sequence during cycling.
    /// </summary>
    /// <returns>Normalized direction vector.</returns>
    private Vector2 GetInputDirection()
    {
        Vector2 direction = Vector2.Zero;

        // Check if sniper rifle bolt cycling is in progress
        if (CurrentWeapon is SniperRifle sniperRifle && sniperRifle.IsBoltCycling)
        {
            // During bolt cycling: only WASD keys move the player (arrows are for bolt action)
            // Use physical key detection for WASD only
            if (Input.IsPhysicalKeyPressed(Key.A)) direction.X -= 1.0f;
            if (Input.IsPhysicalKeyPressed(Key.D)) direction.X += 1.0f;
            if (Input.IsPhysicalKeyPressed(Key.W)) direction.Y -= 1.0f;
            if (Input.IsPhysicalKeyPressed(Key.S)) direction.Y += 1.0f;
        }
        else
        {
            // Normal mode: use all configured input actions (WASD + arrows)
            direction.X = Input.GetAxis("move_left", "move_right");
            direction.Y = Input.GetAxis("move_up", "move_down");
        }

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

        // Skip R-F-R reload for Revolver - it uses multi-step cylinder reload (Issue #626)
        // R key: open/close cylinder. RMB drag up: insert cartridge. Scroll: rotate cylinder.
        // Handled by HandleRevolverReloadInput() and Revolver.cs input handlers.
        if (CurrentWeapon is Revolver)
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

        // Check if this is a pistol-type weapon that uses R->R reload (2-step) instead of R->F->R (3-step)
        // Note: Revolver is excluded above - it uses multi-step cylinder reload (Issue #626)
        bool isPistolReload = CurrentWeapon is MakarovPM;

        // Handle R key (first and third step, or both steps for pistol)
        if (Input.IsActionJustPressed("reload"))
        {
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

                // Start reload sequence - eject magazine
                _isReloadingSequence = true;
                _reloadSequenceStep = 1;
                _ammoAtReloadStart = CurrentWeapon.CurrentAmmo;
                GD.Print($"[Player] Reload sequence started (R pressed) - ammo at start: {_ammoAtReloadStart}" +
                    (isPistolReload ? " - press R to complete (pistol)" : " - press F next"));
                // Start animation: Step 1 - Grab magazine from chest
                StartReloadAnimPhase(ReloadAnimPhase.GrabMagazine, ReloadAnimGrabDuration);
                // Play first reload sound (PM-specific or generic mag out)
                if (isPistolReload)
                    PlayPmReloadAction1Sound();
                else
                    PlayReloadMagOutSound();
                EmitSignal(SignalName.ReloadSequenceProgress, 1, isPistolReload ? 2 : 3);
                // Notify enemies that player has started reloading (vulnerable state)
                EmitSignal(SignalName.ReloadStarted);
            }
            else if (_reloadSequenceStep == 1 && isPistolReload)
            {
                // Pistol R->R reload: second R completes reload (combines F and final R steps)
                // Set up chamber bullet based on ammo at reload start
                bool hadAmmoInMagazine = _ammoAtReloadStart > 0;
                CurrentWeapon.StartReloadSequence(hadAmmoInMagazine);

                GD.Print("[Player] Pistol reload: R->R complete (magazine inserted)");
                // Start animation: Insert magazine
                StartReloadAnimPhase(ReloadAnimPhase.InsertMagazine, ReloadAnimInsertDuration);
                // Play second PM reload sound
                PlayPmReloadAction2Sound();
                EmitSignal(SignalName.ReloadSequenceProgress, 2, 2);
                CompleteReloadSequence();
            }
            else if (_reloadSequenceStep == 1 && !isPistolReload)
            {
                // Non-pistol: pressing R again at step 1 restarts the sequence
                _isReloadingSequence = true;
                _reloadSequenceStep = 1;
                _ammoAtReloadStart = CurrentWeapon.CurrentAmmo;
                GD.Print($"[Player] Reload sequence restarted (R pressed again) - ammo at start: {_ammoAtReloadStart} - press F next");
                StartReloadAnimPhase(ReloadAnimPhase.GrabMagazine, ReloadAnimGrabDuration);
                PlayReloadMagOutSound();
                EmitSignal(SignalName.ReloadSequenceProgress, 1, 3);
                EmitSignal(SignalName.ReloadStarted);
            }
            else if (_reloadSequenceStep == 2)
            {
                // Complete reload sequence - instant reload! (non-pistol: 3rd step)
                // Start animation: Step 3 - Pull bolt/charging handle (back and forth motion)
                StartReloadAnimPhase(ReloadAnimPhase.PullBolt, ReloadAnimBoltPullDuration);
                // Play bolt cycling sound
                PlayM16BoltSound();
                CompleteReloadSequence();
            }
        }

        // Handle F key (reload_step action - second step, only for non-pistol weapons)
        if (Input.IsActionJustPressed("reload_step") && !isPistolReload)
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
    /// Handles revolver multi-step cylinder reload input (Issue #626).
    /// R key: Open cylinder (if closed) or close cylinder (if open).
    /// RMB drag up (insert cartridge) and scroll wheel (rotate cylinder)
    /// are handled directly by Revolver.cs in _Process() and _Input().
    /// Sequence: R (open) → RMB drag up (insert) → scroll (rotate) → repeat → R (close).
    /// </summary>
    private void HandleRevolverReloadInput()
    {
        var revolver = CurrentWeapon as Revolver;
        if (revolver == null)
        {
            return;
        }

        // Only handle R key press - drag and scroll are handled by Revolver.cs
        if (!Input.IsActionJustPressed("reload"))
        {
            return;
        }

        switch (revolver.ReloadState)
        {
            case RevolverReloadState.NotReloading:
                // R press: Open cylinder to begin reload
                if (revolver.OpenCylinder())
                {
                    _isReloadingSequence = true;
                    // Start arm animation for cylinder open
                    StartReloadAnimPhase(ReloadAnimPhase.GrabMagazine, ReloadAnimGrabDuration);
                    EmitSignal(SignalName.ReloadSequenceProgress, 1, 3);
                    EmitSignal(SignalName.ReloadStarted);
                    LogToFile("[Player] Revolver: cylinder opened (R key)");
                }
                break;

            case RevolverReloadState.CylinderOpen:
            case RevolverReloadState.Loading:
                // R press: Close cylinder to finish reload
                if (revolver.CloseCylinder())
                {
                    _isReloadingSequence = false;
                    // Animate arm return
                    StartReloadAnimPhase(ReloadAnimPhase.ReturnIdle, ReloadAnimReturnDuration);
                    EmitSignal(SignalName.ReloadSequenceProgress, 3, 3);
                    EmitSignal(SignalName.ReloadCompleted);
                    // Emit sound propagation for reload completion
                    var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
                    if (soundPropagation != null && soundPropagation.HasMethod("emit_player_reload_complete"))
                    {
                        soundPropagation.Call("emit_player_reload_complete", GlobalPosition, this);
                    }
                    LogToFile("[Player] Revolver: cylinder closed (R key), reload complete");
                }
                break;
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
    /// Plays the first Makarov PM reload action sound (eject magazine).
    /// </summary>
    private void PlayPmReloadAction1Sound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_pm_reload_action_1"))
        {
            audioManager.Call("play_pm_reload_action_1", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the second Makarov PM reload action sound (insert magazine).
    /// </summary>
    private void PlayPmReloadAction2Sound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_pm_reload_action_2"))
        {
            audioManager.Call("play_pm_reload_action_2", GlobalPosition);
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
            // When SniperRifle scope is active, fire towards the scope crosshair center
            // instead of the mouse cursor (the camera is offset, so mouse != crosshair)
            var sniperRifle = CurrentWeapon as SniperRifle;
            if (sniperRifle != null && sniperRifle.IsScopeActive)
            {
                Vector2 scopeTarget = sniperRifle.GetScopeAimTarget();
                shootDirection = (scopeTarget - GlobalPosition).Normalized();
            }

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
        if (bullet.HasMethod("SetDirection"))
        {
            bullet.Call("SetDirection", direction);
        }
        else
        {
            bullet.Set("direction", direction);
        }

        // Set shooter ID to prevent self-damage
        if (bullet.HasMethod("SetShooterId"))
        {
            bullet.Call("SetShooterId", GetInstanceId());
        }
        else
        {
            bullet.Set("shooter_id", GetInstanceId());
        }

        // Set breaker bullet flag if breaker bullets active item is selected (Issue #678)
        if (_breakerBulletsActive)
        {
            bullet.Set("is_breaker_bullet", true);
        }

        // Add bullet to the scene tree
        GetTree().CurrentScene.AddChild(bullet);
    }

    /// <summary>
    /// Last hit direction stored for blood effect spawning (Issue #350).
    /// </summary>
    private Vector2 _lastHitDirection = Vector2.Right;

    /// <summary>
    /// Last caliber data stored for blood effect scaling (Issue #350).
    /// </summary>
    private Godot.Resource? _lastCaliberData = null;

    /// <summary>
    /// Called when hit by a projectile via hit_area.gd.
    /// This method name follows GDScript naming convention for cross-language compatibility
    /// with the hit detection system that uses has_method("on_hit") checks.
    /// </summary>
    public void on_hit()
    {
        on_hit_with_info(Vector2.Right, null);
    }

    /// <summary>
    /// Called when hit by a projectile with extended hit information (Issue #350).
    /// This method name follows GDScript naming convention for cross-language compatibility
    /// with the hit detection system that uses has_method("on_hit_with_info") checks.
    /// </summary>
    /// <param name="hitDirection">Direction the bullet was traveling.</param>
    /// <param name="caliberData">Caliber resource for effect scaling (can be null).</param>
    public void on_hit_with_info(Vector2 hitDirection, Godot.Resource? caliberData)
    {
        _lastHitDirection = hitDirection;
        _lastCaliberData = caliberData;
        TakeDamage(1);
    }

    /// <inheritdoc/>
    public override void TakeDamage(float amount)
    {
        if (HealthComponent == null || !IsAlive)
        {
            return;
        }

        // Check invincibility mode (F6 toggle)
        if (_invincibilityEnabled)
        {
            LogToFile("[Player] Hit blocked by invincibility mode (C#)");
            ShowHitFlash(); // Still show visual feedback for debugging
            // Spawn blood effect for visual feedback even in invincibility mode (Issue #350)
            SpawnBloodEffect(false);
            return;
        }

        GD.Print($"[Player] {Name}: Taking {amount} damage. Current health: {HealthComponent.CurrentHealth}");

        // Show hit flash effect
        ShowHitFlash();

        // Determine if this hit will be lethal before applying damage
        bool willBeFatal = HealthComponent.CurrentHealth <= amount;

        // Play appropriate hit sound and spawn blood effect (Issue #350)
        if (willBeFatal)
        {
            PlayHitLethalSound();
            SpawnBloodEffect(true);
        }
        else
        {
            PlayHitNonLethalSound();
            SpawnBloodEffect(false);
        }

        base.TakeDamage(amount);
    }

    /// <summary>
    /// Spawns blood effect at the player's position (Issue #350).
    /// This makes blood effects appear when the player is hit, just like for enemies.
    /// </summary>
    /// <param name="isLethal">Whether this was a lethal hit (affects effect scale).</param>
    private void SpawnBloodEffect(bool isLethal)
    {
        var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
        if (impactManager != null && impactManager.HasMethod("spawn_blood_effect"))
        {
            LogToFile($"[Player] Spawning blood effect at {GlobalPosition}, dir={_lastHitDirection}, lethal={isLethal} (C#)");
            impactManager.Call("spawn_blood_effect", GlobalPosition, _lastHitDirection, _lastCaliberData, isLethal);
        }
        else
        {
            LogToFile("[Player] WARNING: ImpactEffectsManager not found, blood effect not spawned (C#)");
        }
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

        // Propagate breaker bullets flag to new weapon (Issue #678)
        if (_breakerBulletsActive)
        {
            CurrentWeapon.IsBreakerBulletActive = true;
        }

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

    /// <summary>
    /// Applies weapon selection from GameManager autoload.
    /// This is a C# fallback that ensures weapon selection works even when
    /// GDScript level scripts (test_tier.gd, building_level.gd) fail to execute
    /// due to Godot 4.3 GDScript binary tokenization issues.
    /// Called from _Ready() after auto-equipping the default AssaultRifle.
    /// </summary>
    private void ApplySelectedWeaponFromGameManager()
    {
        var gameManager = GetNodeOrNull("/root/GameManager");
        if (gameManager == null)
        {
            return;
        }

        // Get selected weapon ID from GameManager (GDScript autoload)
        var selectedWeaponId = gameManager.Call("get_selected_weapon").AsString();
        if (string.IsNullOrEmpty(selectedWeaponId) || selectedWeaponId == "makarov_pm")
        {
            // Default weapon (MakarovPM) - already equipped, nothing to do
            return;
        }

        // Map weapon ID to scene path and node name
        string scenePath;
        string weaponNodeName;
        switch (selectedWeaponId)
        {
            case "m16":
                scenePath = "res://scenes/weapons/csharp/AssaultRifle.tscn";
                weaponNodeName = "AssaultRifle";
                break;
            case "shotgun":
                scenePath = "res://scenes/weapons/csharp/Shotgun.tscn";
                weaponNodeName = "Shotgun";
                break;
            case "mini_uzi":
                scenePath = "res://scenes/weapons/csharp/MiniUzi.tscn";
                weaponNodeName = "MiniUzi";
                break;
            case "silenced_pistol":
                scenePath = "res://scenes/weapons/csharp/SilencedPistol.tscn";
                weaponNodeName = "SilencedPistol";
                break;
            case "sniper":
                scenePath = "res://scenes/weapons/csharp/SniperRifle.tscn";
                weaponNodeName = "SniperRifle";
                break;
            case "revolver":
                scenePath = "res://scenes/weapons/csharp/Revolver.tscn";
                weaponNodeName = "Revolver";
                break;
            case "makarov_pm":
                scenePath = "res://scenes/weapons/csharp/MakarovPM.tscn";
                weaponNodeName = "MakarovPM";
                break;
            default:
                LogToFile($"[Player.Weapon] Unknown weapon ID '{selectedWeaponId}', keeping default");
                return;
        }

        LogToFile($"[Player.Weapon] GameManager weapon selection: {selectedWeaponId} ({weaponNodeName})");

        // Remove the default MakarovPM immediately
        var defaultWeapon = GetNodeOrNull<BaseWeapon>("MakarovPM");
        if (defaultWeapon != null)
        {
            RemoveChild(defaultWeapon);
            defaultWeapon.QueueFree();
            LogToFile("[Player.Weapon] Removed default MakarovPM");
        }
        CurrentWeapon = null;

        // Load and instantiate the selected weapon
        var weaponScene = GD.Load<PackedScene>(scenePath);
        if (weaponScene != null)
        {
            var weapon = weaponScene.Instantiate<BaseWeapon>();
            weapon.Name = weaponNodeName;
            AddChild(weapon);
            CurrentWeapon = weapon;
            LogToFile($"[Player.Weapon] Equipped {weaponNodeName} (ammo: {weapon.CurrentAmmo}/{weapon.WeaponData?.MagazineSize ?? 0})");
        }
        else
        {
            LogToFile($"[Player.Weapon] ERROR: Failed to load weapon scene: {scenePath}");
        }
    }

    #region Sniper Scope System

    /// <summary>
    /// Handles sniper scope input when the SniperRifle is equipped.
    /// RMB activates the scope for aiming beyond the viewport.
    /// Mouse wheel adjusts zoom distance while scoped.
    /// Returns true if the sniper scope consumed the RMB input.
    /// </summary>
    private bool HandleSniperScopeInput()
    {
        // Only handle scope when a SniperRifle is the current weapon
        var sniperRifle = CurrentWeapon as SniperRifle;
        if (sniperRifle == null)
        {
            return false;
        }

        // Handle RMB press to activate scope
        if (Input.IsActionJustPressed("grenade_throw"))
        {
            // Only activate scope if not already in a grenade action
            if (_grenadeState == GrenadeState.Idle && !Input.IsActionPressed("grenade_prepare"))
            {
                sniperRifle.ActivateScope();
                return true;
            }
        }

        // Handle RMB release to deactivate scope
        if (Input.IsActionJustReleased("grenade_throw") && sniperRifle.IsScopeActive)
        {
            sniperRifle.DeactivateScope();
            return true;
        }

        // While scope is active, consume RMB input to prevent grenade handling
        if (sniperRifle.IsScopeActive)
        {
            return true;
        }

        return false;
    }

    /// <summary>
    /// Handles mouse wheel input for scope zoom when sniper scope is active.
    /// This is called from _UnhandledInput to capture wheel events.
    /// </summary>
    public override void _UnhandledInput(InputEvent @event)
    {
        base._UnhandledInput(@event);

        var sniperRifle = CurrentWeapon as SniperRifle;
        if (sniperRifle == null || !sniperRifle.IsScopeActive)
        {
            return;
        }

        if (@event is InputEventMouseButton mouseButton)
        {
            if (mouseButton.Pressed)
            {
                if (mouseButton.ButtonIndex == MouseButton.WheelUp)
                {
                    sniperRifle.AdjustScopeZoom(1.0f);
                    GetViewport().SetInputAsHandled();
                }
                else if (mouseButton.ButtonIndex == MouseButton.WheelDown)
                {
                    sniperRifle.AdjustScopeZoom(-1.0f);
                    GetViewport().SetInputAsHandled();
                }
            }
        }
        // Handle mouse movement for scope fine-tuning (closer/further by ~1/3 viewport)
        else if (@event is InputEventMouseMotion mouseMotion)
        {
            sniperRifle.AdjustScopeFineTune(mouseMotion.Relative);
        }
    }

    #endregion

    #region Grenade System

    /// <summary>
    /// Handle grenade input with either simple or complex mechanic.
    /// Simple mode (default): Hold RMB to aim with trajectory preview, release to throw.
    /// Complex mode (experimental): G + RMB drag right → hold G+RMB → release G → drag and release RMB.
    /// </summary>
    private void HandleGrenadeInput()
    {
        // Handle throw rotation animation
        HandleThrowRotationAnimation((float)GetPhysicsProcessDeltaTime());

        // Check for active grenade explosion (explodes in hand after 4 seconds)
        if (_activeGrenade != null && !IsInstanceValid(_activeGrenade))
        {
            // Grenade exploded while held - return arms to idle
            StartGrenadeAnimPhase(GrenadeAnimPhase.ReturnIdle, AnimReturnDuration);
            ResetGrenadeState();
            return;
        }

        // Check if complex grenade throwing is enabled (experimental setting)
        var experimentalSettings = GetNodeOrNull("/root/ExperimentalSettings");
        bool useComplexThrowing = false;
        if (experimentalSettings != null && experimentalSettings.HasMethod("is_complex_grenade_throwing"))
        {
            useComplexThrowing = (bool)experimentalSettings.Call("is_complex_grenade_throwing");
        }

        // Debug log once per state change to track mode (logged once when grenade action starts)
        if (_grenadeState == GrenadeState.Idle && (Input.IsActionJustPressed("grenade_throw") || Input.IsActionJustPressed("grenade_prepare")))
        {
            LogToFile($"[Player.Grenade] Mode check: complex={useComplexThrowing}, settings_node={experimentalSettings != null}");
        }

        if (useComplexThrowing)
        {
            // Complex 3-step throwing mechanic
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
        else
        {
            // Simple trajectory aiming mode - uses same pin-pull mechanic (G+RMB drag)
            // but replaces mouse-velocity throwing with trajectory-to-cursor aiming
            switch (_grenadeState)
            {
                case GrenadeState.Idle:
                    // Use same G+RMB drag mechanic as complex mode for pin pull (Step 1)
                    HandleGrenadeIdleState();
                    break;
                case GrenadeState.TimerStarted:
                    // After pin is pulled, RMB starts trajectory aiming (instead of Step 2)
                    HandleSimpleGrenadeTimerStartedState();
                    break;
                case GrenadeState.SimpleAiming:
                    // RMB held: show trajectory preview, release to throw to cursor
                    HandleSimpleGrenadeAimingState();
                    break;
                default:
                    // If we're in a complex-mode state but simple mode is now enabled,
                    // reset to allow starting fresh (handles mode switch mid-throw)
                    if (_grenadeState == GrenadeState.WaitingForGRelease ||
                        _grenadeState == GrenadeState.Aiming)
                    {
                        LogToFile($"[Player.Grenade] Mode mismatch: resetting from complex state {_grenadeState} to IDLE");
                        if (_activeGrenade != null && IsInstanceValid(_activeGrenade))
                        {
                            DropGrenadeAtFeet();
                        }
                        else
                        {
                            ResetGrenadeState();
                        }
                    }
                    break;
            }
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
            // Initialize velocity tracking for realistic throwing
            _mouseVelocityHistory.Clear();
            _currentMouseVelocity = Vector2.Zero;
            _totalSwingDistance = 0.0f;
            _prevFrameTime = Time.GetTicksMsec() / 1000.0;
            // Start transfer animation (grenade to throwing hand)
            StartGrenadeAnimPhase(GrenadeAnimPhase.Transfer, AnimTransferDuration);
            LogToFile("[Player.Grenade] Step 2 complete: G released, RMB held - now aiming (velocity-based throwing enabled)");
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

        // Request redraw for debug trajectory visualization
        if (_debugModeEnabled)
        {
            QueueRedraw();
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

    #region Simple Grenade Throwing Mode

    /// <summary>
    /// Handle TIMER_STARTED state for simple grenade throwing mode.
    /// After pin is pulled (G+RMB drag), wait for RMB to start trajectory aiming.
    /// If G is released, drop grenade at feet.
    /// </summary>
    private void HandleSimpleGrenadeTimerStartedState()
    {
        // Make grenade follow player while G is held
        if (_activeGrenade != null && IsInstanceValid(_activeGrenade))
        {
            _activeGrenade.GlobalPosition = GlobalPosition;
        }

        // If G is released, drop grenade at feet
        if (!Input.IsActionPressed("grenade_prepare"))
        {
            LogToFile("[Player.Grenade.Simple] G released - dropping grenade at feet");
            DropGrenadeAtFeet();
            return;
        }

        // Check if RMB is pressed to enter SimpleAiming state
        if (Input.IsActionJustPressed("grenade_throw"))
        {
            _grenadeState = GrenadeState.SimpleAiming;
            _isPreparingGrenade = true;
            // Store initial mouse position for aiming
            _aimDragStart = GetGlobalMousePosition();
            // Start hands approach animation
            StartGrenadeAnimPhase(GrenadeAnimPhase.HandsApproach, AnimApproachDuration);
            LogToFile("[Player.Grenade.Simple] RMB pressed after pin pull - starting trajectory aiming");
        }
    }

    /// <summary>
    /// Handle SIMPLE_AIMING state: RMB held, showing trajectory preview.
    /// Cursor position = landing point. Release RMB to throw.
    /// G can be released while RMB is held - grenade stays ready.
    /// </summary>
    private void HandleSimpleGrenadeAimingState()
    {
        // Request redraw for trajectory visualization (always show in simple mode)
        QueueRedraw();

        // Make grenade follow player
        if (_activeGrenade != null && IsInstanceValid(_activeGrenade))
        {
            _activeGrenade.GlobalPosition = GlobalPosition;
        }

        // Update arm animation based on wind-up
        UpdateSimpleWindUpAnimation();

        // If animation phases need to transition
        if (_grenadeAnimPhase == GrenadeAnimPhase.HandsApproach && _grenadeAnimTimer <= 0)
        {
            _grenadeAnimPhase = GrenadeAnimPhase.WindUp;
        }

        // Check for RMB release - throw the grenade!
        if (Input.IsActionJustReleased("grenade_throw"))
        {
            ThrowSimpleGrenade();
        }

        // Check for cancellation (if grenade was somehow destroyed)
        if (_activeGrenade == null || !IsInstanceValid(_activeGrenade))
        {
            ResetGrenadeState();
            StartGrenadeAnimPhase(GrenadeAnimPhase.ReturnIdle, AnimReturnDuration);
        }
    }

    /// <summary>
    /// Update wind-up animation based on distance from player to cursor.
    /// </summary>
    private void UpdateSimpleWindUpAnimation()
    {
        Vector2 currentMouse = GetGlobalMousePosition();
        float distance = GlobalPosition.DistanceTo(currentMouse);

        // Calculate wind-up intensity based on distance (0-500 pixels = 0-1 intensity)
        const float maxDistance = 500.0f;
        _windUpIntensity = Mathf.Clamp(distance / maxDistance, 0.0f, 1.0f);
    }

    /// <summary>
    /// Throw the grenade in simple mode.
    /// Direction and distance based on cursor position relative to player.
    /// </summary>
    private void ThrowSimpleGrenade()
    {
        if (_activeGrenade == null || !IsInstanceValid(_activeGrenade))
        {
            LogToFile("[Player.Grenade.Simple] Cannot throw: no active grenade");
            ResetGrenadeState();
            return;
        }

        Vector2 targetPos = GetGlobalMousePosition();
        Vector2 toTarget = targetPos - GlobalPosition;

        // Calculate throw direction
        Vector2 throwDirection = toTarget.Length() > 10.0f ? toTarget.Normalized() : new Vector2(1, 0);

        // FIX for issue #398: Account for spawn offset in distance calculation
        // The grenade starts 60 pixels ahead of the player in the throw direction,
        // so we need to calculate distance from spawn position to target, not from player to target
        const float spawnOffset = 60.0f;
        Vector2 spawnPosition = GlobalPosition + throwDirection * spawnOffset;
        float throwDistance = (targetPos - spawnPosition).Length();

        // Ensure minimum throw distance
        if (throwDistance < 10.0f) throwDistance = 10.0f;

        // Get grenade's actual physics properties for accurate calculation
        // FIX for issue #398: Use actual grenade properties instead of hardcoded values
        float groundFriction = 300.0f; // Default
        float maxThrowSpeed = 850.0f;  // Default
        if (_activeGrenade.Get("ground_friction").VariantType != Variant.Type.Nil)
        {
            groundFriction = (float)_activeGrenade.Get("ground_friction");
        }
        if (_activeGrenade.Get("max_throw_speed").VariantType != Variant.Type.Nil)
        {
            maxThrowSpeed = (float)_activeGrenade.Get("max_throw_speed");
        }

        // Calculate throw speed needed to reach target (using physics)
        // Distance = v^2 / (2 * friction) → v = sqrt(2 * friction * distance)
        // FIX for issue #615: Removed the 1.16x compensation factor.
        // Root causes: (1) GDScript + C# were BOTH applying friction (double friction), and
        // (2) Godot's default linear_damp=0.1 in COMBINE mode added hidden damping.
        // Fix: GDScript friction removed entirely (C# GrenadeTimer is sole friction source),
        // and linear_damp_mode set to REPLACE so linear_damp=0 means zero damping.
        // v = sqrt(2*F*d) now works correctly without any compensation factor.
        float requiredSpeed = Mathf.Sqrt(2.0f * groundFriction * throwDistance);

        // Clamp to grenade's max throw speed
        float throwSpeed = Mathf.Min(requiredSpeed, maxThrowSpeed);

        // Calculate actual landing distance with clamped speed (for logging)
        float actualDistance = (throwSpeed * throwSpeed) / (2.0f * groundFriction);

        LogToFile($"[Player.Grenade.Simple] Throwing! Target: {targetPos}, Distance: {actualDistance:F1}, Speed: {throwSpeed:F1}, Friction: {groundFriction:F1}");

        // Rotate player to face throw direction
        RotatePlayerForThrow(throwDirection);

        // Calculate safe spawn position with wall check
        Vector2 intendedSpawnPosition = GlobalPosition + throwDirection * spawnOffset;
        Vector2 safeSpawnPosition = GetSafeGrenadeSpawnPosition(GlobalPosition, intendedSpawnPosition, throwDirection);

        // FIX for issue #398: Set grenade position to spawn point BEFORE throwing
        // The grenade follows the player during aiming at GlobalPosition,
        // but the distance calculation assumes it starts from spawnPosition (60px ahead).
        // Without this fix, the grenade lands ~60px short of the target.
        _activeGrenade.GlobalPosition = safeSpawnPosition;

        // FIX for Issue #432: Mark grenade as thrown BEFORE unfreezing to avoid race condition.
        // If MarkAsThrown() is called after unfreezing, the BodyEntered signal could fire
        // before IsThrown is set, causing impact detection to fail.
        var grenadeTimer = _activeGrenade.GetNodeOrNull<GrenadeTimer>("GrenadeTimer");
        if (grenadeTimer != null)
        {
            grenadeTimer.MarkAsThrown();
        }

        // Unfreeze and throw the grenade
        _activeGrenade.Freeze = false;

        // FIX for Issue #432: ALWAYS set velocity directly in C# as primary mechanism.
        // GDScript methods called via Call() may silently fail in exported builds,
        // causing grenades to fly infinitely (no velocity set) or not move at all.
        // By setting velocity directly in C#, we guarantee the grenade moves correctly.
        _activeGrenade.LinearVelocity = throwDirection * throwSpeed;
        _activeGrenade.Rotation = throwDirection.Angle();

        LogToFile($"[Player.Grenade.Simple] C# set velocity directly: dir={throwDirection}, speed={throwSpeed:F1}, spawn={safeSpawnPosition}");

        // Also try to call GDScript method for any additional setup it might do
        // (visual effects, sound, etc.), but the velocity is already set above
        if (_activeGrenade.HasMethod("throw_grenade_simple"))
        {
            _activeGrenade.Call("throw_grenade_simple", throwDirection, throwSpeed);
        }

        // Start throw animation
        StartGrenadeAnimPhase(GrenadeAnimPhase.Throw, AnimThrowDuration);

        // Emit signal and play sound
        EmitSignal(SignalName.GrenadeThrown);
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_grenade_throw"))
        {
            audioManager.Call("play_grenade_throw", GlobalPosition);
        }

        LogToFile("[Player.Grenade.Simple] Grenade thrown!");

        // Reset state
        ResetGrenadeState();
    }

    #endregion

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

        // FIX for Issue #432 (activation position bug): Freeze the grenade IMMEDIATELY after creation.
        // This MUST happen before setting position to prevent physics engine interference.
        // Root cause: GDScript _ready() sets freeze=true, but GDScript doesn't run in exports!
        // Without this fix, the physics engine can move the unfrozen grenade while player moves,
        // causing the grenade to be thrown from the activation position instead of player's current position.
        // See commit 60f7cae for original fix and docs/case-studies/issue-183/ for detailed analysis.
        _activeGrenade.FreezeMode = RigidBody2D.FreezeModeEnum.Kinematic;
        _activeGrenade.Freeze = true;

        // Set position AFTER AddChild and AFTER freezing (GlobalPosition only works when node is in the scene tree)
        _activeGrenade.GlobalPosition = GlobalPosition;

        // FIX for Issue #432: Add C# GrenadeTimer component for reliable explosion handling.
        // GDScript methods called via Call() may silently fail in exports, causing grenades
        // to fly infinitely without exploding. This C# component provides a reliable fallback.
        AddGrenadeTimerComponent(_activeGrenade);

        // Activate the grenade timer (starts 4s countdown)
        // Try GDScript first, but C# GrenadeTimer will handle it if this fails
        if (_activeGrenade.HasMethod("activate_timer"))
        {
            _activeGrenade.Call("activate_timer");
        }
        // Also activate C# timer as reliable fallback
        var grenadeTimer = _activeGrenade.GetNodeOrNull<GrenadeTimer>("GrenadeTimer");
        if (grenadeTimer != null)
        {
            grenadeTimer.ActivateTimer();
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
    /// Add C# GrenadeTimer component to grenade for reliable explosion handling.
    /// FIX for Issue #432: GDScript methods called via Call() may silently fail in exports.
    /// </summary>
    private void AddGrenadeTimerComponent(RigidBody2D grenade)
    {
        // Determine grenade type from scene name
        var grenadeType = GrenadeTimer.GrenadeType.Flashbang;
        var scenePath = grenade.SceneFilePath;
        if (scenePath.Contains("Frag", StringComparison.OrdinalIgnoreCase))
        {
            grenadeType = GrenadeTimer.GrenadeType.Frag;
        }

        // Create and configure the GrenadeTimer component
        var timer = new GrenadeTimer();
        timer.Name = "GrenadeTimer";
        timer.Type = grenadeType;

        // Copy relevant properties from grenade (if they exist as exported properties)
        if (grenade.HasMeta("fuse_time") || grenade.Get("fuse_time").VariantType != Variant.Type.Nil)
        {
            timer.FuseTime = (float)grenade.Get("fuse_time");
        }
        if (grenade.HasMeta("effect_radius") || grenade.Get("effect_radius").VariantType != Variant.Type.Nil)
        {
            timer.EffectRadius = (float)grenade.Get("effect_radius");
        }
        if (grenade.HasMeta("explosion_damage") || grenade.Get("explosion_damage").VariantType != Variant.Type.Nil)
        {
            timer.ExplosionDamage = (int)grenade.Get("explosion_damage");
        }
        if (grenade.HasMeta("blindness_duration") || grenade.Get("blindness_duration").VariantType != Variant.Type.Nil)
        {
            timer.BlindnessDuration = (float)grenade.Get("blindness_duration");
        }
        if (grenade.HasMeta("stun_duration") || grenade.Get("stun_duration").VariantType != Variant.Type.Nil)
        {
            timer.StunDuration = (float)grenade.Get("stun_duration");
        }
        // FIX for Issue #432: Copy ground_friction for C# friction handling
        // GDScript _physics_process() may not run in exports, so we need C# to apply friction
        if (grenade.HasMeta("ground_friction") || grenade.Get("ground_friction").VariantType != Variant.Type.Nil)
        {
            timer.GroundFriction = (float)grenade.Get("ground_friction");
        }

        // FIX for Issue #432: Apply type-based defaults BEFORE adding to scene.
        // GDScript Get() calls may fail silently in exported builds, leaving us with
        // incorrect values (e.g., Frag grenade using Flashbang's 400 radius instead of 225).
        timer.SetTypeBasedDefaults();

        // Add the timer component to the grenade
        grenade.AddChild(timer);
        LogToFile($"[Player.Grenade] Added GrenadeTimer component (type: {grenadeType})");
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
        // Reset velocity tracking for next throw
        _mouseVelocityHistory.Clear();
        _currentMouseVelocity = Vector2.Zero;
        _totalSwingDistance = 0.0f;
        LogToFile("[Player.Grenade] State reset to IDLE");
    }

    /// <summary>
    /// Sensitivity multiplier for throw distance calculation.
    /// Higher value = farther throw for same drag distance.
    /// Must match the value used in debug visualization.
    /// </summary>
    private const float ThrowSensitivityMultiplier = 9.0f;

    /// <summary>
    /// Throw the grenade using realistic velocity-based physics.
    /// The throw velocity is determined by mouse velocity at release moment, not drag distance.
    /// FIX for issue #313: Direction is now determined by MOUSE VELOCITY (how user moves the mouse)
    /// with snapping to 4 cardinal directions to compensate for imprecise human mouse movement.
    /// </summary>
    /// <param name="dragEnd">The end position of the drag (used for direction fallback).</param>
    private void ThrowGrenade(Vector2 dragEnd)
    {
        if (_activeGrenade == null || !IsInstanceValid(_activeGrenade))
        {
            LogToFile("[Player.Grenade] Cannot throw: no active grenade");
            ResetGrenadeState();
            return;
        }

        // Get the mouse velocity at moment of release (for determining throw speed AND direction)
        Vector2 releaseVelocity = _currentMouseVelocity;
        float velocityMagnitude = releaseVelocity.Length();

        // FIX for issue #313: Use MOUSE VELOCITY DIRECTION (how the mouse is MOVING)
        // User requirement: grenade flies in the direction the mouse is moving at release
        // NOT toward where the mouse cursor is positioned
        // Example: If user moves mouse DOWN, grenade flies DOWN (regardless of where cursor is)
        Vector2 throwDirection;

        if (velocityMagnitude > 10.0f)
        {
            // Primary direction: the direction the mouse is MOVING (velocity direction)
            // FIX for issue #313 v4: Snap to 8 directions (4 cardinal + 4 diagonal)
            // This compensates for imprecise human mouse movement while allowing diagonal throws
            Vector2 rawDirection = releaseVelocity.Normalized();
            throwDirection = SnapToOctantDirection(rawDirection);
            LogToFile($"[Player.Grenade] Raw direction: {rawDirection}, Snapped direction: {throwDirection}");
        }
        else
        {
            // Fallback when mouse is not moving - use player-to-mouse as fallback direction
            // FIX for issue #313 v4: Also snap fallback to 8 directions
            Vector2 playerToMouse = dragEnd - GlobalPosition;
            if (playerToMouse.Length() > 10.0f)
            {
                throwDirection = SnapToOctantDirection(playerToMouse.Normalized());
            }
            else
            {
                throwDirection = new Vector2(1, 0);  // Default direction (right)
            }
            // FIX for issue #313 v4: When velocity is 0, use a minimum throw speed
            // This prevents grenade from getting "stuck" when user stops mouse before release
            float minFallbackVelocity = 2000.0f;  // Minimum velocity to ensure grenade travels
            velocityMagnitude = minFallbackVelocity;
            LogToFile($"[Player.Grenade] Fallback mode: Using minimum velocity {minFallbackVelocity:F1} px/s");
        }

        LogToFile($"[Player.Grenade] Throwing in mouse velocity direction! Direction: {throwDirection}, Mouse velocity: {velocityMagnitude:F1} px/s, Swing: {_totalSwingDistance:F1}");

        // Rotate player to face throw direction (prevents grenade hitting player when throwing upward)
        RotatePlayerForThrow(throwDirection);

        // Calculate intended spawn position (60px in front of player in throw direction)
        float spawnOffset = 60.0f;
        Vector2 intendedSpawnPosition = GlobalPosition + throwDirection * spawnOffset;

        // FIXED: Raycast check to prevent spawning grenade behind/inside walls
        // This fixes grenades passing through walls when thrown at close range ("в упор")
        Vector2 spawnPosition = GetSafeGrenadeSpawnPosition(GlobalPosition, intendedSpawnPosition, throwDirection);
        _activeGrenade.GlobalPosition = spawnPosition;

        // FIX for Issue #432: ALWAYS set velocity directly in C# as primary mechanism.
        // GDScript methods called via Call() may silently fail in exported builds.
        // Calculate throw speed using the same formula as GDScript
        float multiplier = 0.5f;
        float minSwing = 80.0f;
        float maxSpeed = 850.0f;
        float swingTransfer = Mathf.Clamp(_totalSwingDistance / minSwing, 0.0f, 0.65f);
        float finalSpeed = Mathf.Min(velocityMagnitude * multiplier * (0.35f + swingTransfer), maxSpeed);

        // FIX for Issue #432: Mark grenade as thrown BEFORE unfreezing to avoid race condition.
        // If MarkAsThrown() is called after unfreezing, the BodyEntered signal could fire
        // before IsThrown is set, causing impact detection to fail.
        var grenadeTimer = _activeGrenade.GetNodeOrNull<GrenadeTimer>("GrenadeTimer");
        if (grenadeTimer != null)
        {
            grenadeTimer.MarkAsThrown();
        }

        // Unfreeze and set velocity directly
        _activeGrenade.Freeze = false;
        _activeGrenade.LinearVelocity = throwDirection * finalSpeed;
        _activeGrenade.Rotation = throwDirection.Angle();

        LogToFile($"[Player.Grenade] C# set velocity directly: dir={throwDirection}, speed={finalSpeed:F1}, spawn={spawnPosition}");

        // Also try to call GDScript method for any additional setup
        if (_activeGrenade.HasMethod("throw_grenade_with_direction"))
        {
            _activeGrenade.Call("throw_grenade_with_direction", throwDirection, velocityMagnitude, _totalSwingDistance);
        }
        else if (_activeGrenade.HasMethod("throw_grenade_velocity_based"))
        {
            Vector2 directionalVelocity = throwDirection * velocityMagnitude;
            _activeGrenade.Call("throw_grenade_velocity_based", directionalVelocity, _totalSwingDistance);
        }
        else if (_activeGrenade.HasMethod("throw_grenade"))
        {
            float legacyDistance = velocityMagnitude * 0.5f;
            _activeGrenade.Call("throw_grenade", throwDirection, legacyDistance);
        }

        // Emit signal
        EmitSignal(SignalName.GrenadeThrown);

        // Play grenade throw sound
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_grenade_throw"))
        {
            audioManager.Call("play_grenade_throw", GlobalPosition);
        }

        LogToFile($"[Player.Grenade] Thrown! Velocity: {velocityMagnitude:F1}, Swing: {_totalSwingDistance:F1}");

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
    /// Get a safe spawn position for the grenade that doesn't spawn behind/inside walls.
    /// Uses raycast from player position to intended spawn position to detect walls.
    /// If a wall is detected, spawns the grenade just before the wall (5px safety margin).
    /// </summary>
    /// <param name="fromPos">The player's current position.</param>
    /// <param name="intendedPos">The intended spawn position (player + offset in throw direction).</param>
    /// <param name="throwDirection">The normalized throw direction.</param>
    /// <returns>The safe spawn position for the grenade.</returns>
    private Vector2 GetSafeGrenadeSpawnPosition(Vector2 fromPos, Vector2 intendedPos, Vector2 throwDirection)
    {
        // Get physics space state for raycasting
        var spaceState = GetWorld2D().DirectSpaceState;
        if (spaceState == null)
        {
            LogToFile("[Player.Grenade] Warning: Could not get DirectSpaceState for raycast");
            return intendedPos;
        }

        // Create raycast query from player to intended spawn position
        // Collision mask 4 = obstacles layer (walls)
        var query = PhysicsRayQueryParameters2D.Create(fromPos, intendedPos, 4);
        query.Exclude = new Godot.Collections.Array<Rid> { GetRid() }; // Exclude self

        var result = spaceState.IntersectRay(query);

        // If no wall detected, use intended position
        if (result.Count == 0)
        {
            return intendedPos;
        }

        // Wall detected! Calculate safe position (5px before the wall)
        Vector2 wallPosition = (Vector2)result["position"];
        string colliderName = "Unknown";
        if (result.ContainsKey("collider"))
        {
            var collider = result["collider"].AsGodotObject();
            if (collider is Node node)
            {
                colliderName = node.Name;
            }
        }

        float distanceToWall = fromPos.DistanceTo(wallPosition);
        float safeDistance = Mathf.Max(distanceToWall - 5.0f, 10.0f); // At least 10px from player
        Vector2 safePosition = fromPos + throwDirection * safeDistance;

        LogToFile($"[Player.Grenade] Wall detected at {wallPosition} (collider: {colliderName})! Adjusting spawn from {intendedPos} to {safePosition}");

        return safePosition;
    }

    /// <summary>
    /// FIX for issue #313 v4: Snap raw mouse velocity direction to the nearest of 8 directions.
    /// This compensates for imprecise human mouse movement while allowing diagonal throws.
    ///
    /// Uses 8 directions (45° sectors each):
    /// - RIGHT (0°): 0°
    /// - DOWN-RIGHT (45°): 45°
    /// - DOWN (90°): 90°
    /// - DOWN-LEFT (135°): 135°
    /// - LEFT (180°): 180°
    /// - UP-LEFT (-135°): -135°
    /// - UP (-90°): -90°
    /// - UP-RIGHT (-45°): -45°
    /// </summary>
    /// <param name="rawDirection">The raw normalized direction from mouse velocity.</param>
    /// <returns>The snapped direction (one of 8 unit vectors).</returns>
    private Vector2 SnapToOctantDirection(Vector2 rawDirection)
    {
        float angle = rawDirection.Angle();  // Returns angle in radians (-PI to PI)
        float sectorSize = Mathf.Pi / 4.0f;  // 45 degrees per sector (8 directions)
        int sectorIndex = Mathf.RoundToInt(angle / sectorSize);
        float snappedAngle = sectorIndex * sectorSize;
        return new Vector2(Mathf.Cos(snappedAngle), Mathf.Sin(snappedAngle));
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
    /// Update wind-up intensity and track mouse velocity during aiming.
    /// Uses velocity-based physics for realistic throwing.
    /// </summary>
    private void UpdateWindUpIntensity()
    {
        Vector2 currentMouse = GetGlobalMousePosition();
        double currentTime = Time.GetTicksMsec() / 1000.0;

        // Calculate time delta since last frame
        double deltaTime = currentTime - _prevFrameTime;
        if (deltaTime <= 0.0)
        {
            deltaTime = 0.016; // Default to ~60fps if first frame
        }

        // Calculate mouse displacement since last frame
        Vector2 mouseDelta = currentMouse - _prevMousePos;

        // Accumulate total swing distance for momentum transfer calculation
        _totalSwingDistance += mouseDelta.Length();

        // Calculate instantaneous mouse velocity (pixels per second)
        Vector2 instantaneousVelocity = mouseDelta / (float)deltaTime;

        // Add to velocity history for smoothing
        _mouseVelocityHistory.Add(instantaneousVelocity);
        if (_mouseVelocityHistory.Count > MouseVelocityHistorySize)
        {
            _mouseVelocityHistory.RemoveAt(0);
        }

        // Calculate average velocity from history (smoothed velocity)
        Vector2 velocitySum = Vector2.Zero;
        foreach (Vector2 vel in _mouseVelocityHistory)
        {
            velocitySum += vel;
        }
        _currentMouseVelocity = velocitySum / Math.Max(_mouseVelocityHistory.Count, 1);

        // Calculate wind-up intensity based on velocity (for animation)
        // Higher velocity = more wind-up visual effect
        float velocityMagnitude = _currentMouseVelocity.Length();
        // Normalize to a reasonable range (0-2000 pixels/second typical for fast mouse movement)
        float velocityIntensity = Mathf.Clamp(velocityMagnitude / 1500.0f, 0.0f, 1.0f);

        _windUpIntensity = velocityIntensity;

        // Update tracking for next frame
        _prevMousePos = currentMouse;
        _prevFrameTime = currentTime;
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

    #region Flashlight Methods (Issue #546)

    /// <summary>
    /// Initialize the flashlight if the ActiveItemManager has it selected.
    /// Loads and attaches the FlashlightEffect scene to PlayerModel.
    /// </summary>
    private void InitFlashlight()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.Flashlight] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_flashlight"))
        {
            LogToFile("[Player.Flashlight] ActiveItemManager missing has_flashlight method");
            return;
        }

        bool hasFlashlight = (bool)activeItemManager.Call("has_flashlight");
        if (!hasFlashlight)
        {
            LogToFile("[Player.Flashlight] No flashlight selected in ActiveItemManager");
            return;
        }

        LogToFile("[Player.Flashlight] Flashlight is selected, initializing...");

        // Load and instantiate the flashlight effect scene
        if (!ResourceLoader.Exists(FlashlightScenePath))
        {
            LogToFile($"[Player.Flashlight] WARNING: Flashlight scene not found: {FlashlightScenePath}");
            return;
        }

        var flashlightScene = GD.Load<PackedScene>(FlashlightScenePath);
        if (flashlightScene == null)
        {
            LogToFile("[Player.Flashlight] WARNING: Failed to load flashlight scene");
            return;
        }

        _flashlightNode = flashlightScene.Instantiate<Node2D>();
        _flashlightNode.Name = "FlashlightEffect";

        // Add as child of PlayerModel so it rotates with aiming direction
        if (_playerModel != null)
        {
            _playerModel.AddChild(_flashlightNode);
            // Position at the weapon barrel (forward from center, matching BulletSpawnOffset)
            _flashlightNode.Position = new Vector2(BulletSpawnOffset, 0);
            _flashlightEquipped = true;
            LogToFile($"[Player.Flashlight] Flashlight equipped and attached to PlayerModel at offset ({(int)BulletSpawnOffset}, 0)");

            // Check if GDScript methods are available
            _flashlightHasScript = _flashlightNode.HasMethod("turn_on");
            LogToFile($"[Player.Flashlight] GDScript methods available: {_flashlightHasScript}");

            // Get direct reference to PointLight2D for fallback control
            _flashlightPointLight = _flashlightNode.GetNodeOrNull<PointLight2D>("PointLight2D");
            if (_flashlightPointLight != null)
            {
                // Start with light off
                _flashlightPointLight.Visible = false;
                _flashlightPointLight.Energy = 0.0f;
                LogToFile($"[Player.Flashlight] PointLight2D found, shadow={_flashlightPointLight.ShadowEnabled}");
            }
            else
            {
                LogToFile("[Player.Flashlight] WARNING: PointLight2D child not found in flashlight scene");
            }
        }
        else
        {
            LogToFile("[Player.Flashlight] WARNING: _playerModel is null, flashlight not attached");
            _flashlightNode.QueueFree();
            _flashlightNode = null;
        }
    }

    /// <summary>
    /// Handle flashlight input: hold Space to turn on, release to turn off.
    /// Uses GDScript methods when available, falls back to direct PointLight2D control.
    /// </summary>
    private void HandleFlashlightInput()
    {
        if (!_flashlightEquipped || _flashlightNode == null)
        {
            return;
        }

        if (!IsInstanceValid(_flashlightNode))
        {
            return;
        }

        if (Input.IsActionPressed("flashlight_toggle"))
        {
            if (_flashlightHasScript)
            {
                _flashlightNode.Call("turn_on");
            }
            else if (!_flashlightIsOn)
            {
                // C# fallback: directly control PointLight2D
                _flashlightIsOn = true;
                if (_flashlightPointLight != null)
                {
                    _flashlightPointLight.Visible = true;
                    _flashlightPointLight.Energy = FlashlightEnergy;
                }
            }
        }
        else
        {
            if (_flashlightHasScript)
            {
                _flashlightNode.Call("turn_off");
            }
            else if (_flashlightIsOn)
            {
                // C# fallback: directly control PointLight2D
                _flashlightIsOn = false;
                if (_flashlightPointLight != null)
                {
                    _flashlightPointLight.Visible = false;
                    _flashlightPointLight.Energy = 0.0f;
                }
            }
        }
    }

    /// <summary>
    /// Check if the player's flashlight is currently on (Issue #574).
    /// Used by enemy AI to detect the flashlight beam and estimate player position.
    /// Method name follows GDScript naming convention for cross-language compatibility
    /// with the flashlight detection system that uses has_method("is_flashlight_on") checks.
    /// </summary>
    public bool is_flashlight_on()
    {
        if (!_flashlightEquipped || _flashlightNode == null)
            return false;
        if (!IsInstanceValid(_flashlightNode))
            return false;
        if (_flashlightHasScript && _flashlightNode.HasMethod("is_on"))
            return (bool)_flashlightNode.Call("is_on");
        return _flashlightIsOn;
    }

    /// <summary>
    /// Get the flashlight beam direction as a normalized Vector2 (Issue #574).
    /// The beam direction matches the player model's facing direction.
    /// Returns Vector2.Zero if flashlight is off or not equipped.
    /// Method name follows GDScript naming convention for cross-language compatibility.
    /// </summary>
    public Vector2 get_flashlight_direction()
    {
        if (!is_flashlight_on())
            return Vector2.Zero;
        if (_playerModel == null)
            return Vector2.Zero;
        return Vector2.Right.Rotated(_playerModel.GlobalRotation);
    }

    /// <summary>
    /// Get the flashlight beam origin position in global coordinates (Issue #574).
    /// This is the weapon barrel position where the flashlight is attached.
    /// Returns GlobalPosition if flashlight is off or not equipped.
    /// Method name follows GDScript naming convention for cross-language compatibility.
    /// </summary>
    public Vector2 get_flashlight_origin()
    {
        if (!is_flashlight_on() || _flashlightNode == null)
            return GlobalPosition;
        if (!IsInstanceValid(_flashlightNode))
            return GlobalPosition;
        return _flashlightNode.GlobalPosition;
    }

    #endregion

    #region Teleport Bracers Methods (Issue #672)

    /// <summary>
    /// Initialize the teleport bracers if the ActiveItemManager has them selected.
    /// </summary>
    private void InitTeleportBracers()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.TeleportBracers] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_teleport_bracers"))
        {
            LogToFile("[Player.TeleportBracers] ActiveItemManager missing has_teleport_bracers method");
            return;
        }

        bool hasTeleportBracers = (bool)activeItemManager.Call("has_teleport_bracers");
        if (!hasTeleportBracers)
        {
            LogToFile("[Player.TeleportBracers] No teleport bracers selected in ActiveItemManager");
            return;
        }

        _teleportBracersEquipped = true;
        _teleportCharges = MaxTeleportCharges;
        LogToFile($"[Player.TeleportBracers] Teleport bracers equipped with {_teleportCharges} charges");

        // Emit initial charge count for UI
        EmitSignal(SignalName.TeleportChargesChanged, _teleportCharges, MaxTeleportCharges);
    }

    /// <summary>
    /// Handle teleport bracers input: hold Space to aim, release to teleport.
    /// While Space is held, shows targeting reticle with player silhouette.
    /// On release, teleports player to the safe target position.
    /// </summary>
    private void HandleTeleportBracersInput()
    {
        if (!_teleportBracersEquipped)
        {
            return;
        }

        if (Input.IsActionPressed("flashlight_toggle"))
        {
            // Space held — enter/continue aiming mode
            if (!_teleportAiming && _teleportCharges > 0)
            {
                _teleportAiming = true;
                LogToFile("[Player.TeleportBracers] Aiming started");
            }

            if (_teleportAiming)
            {
                // Update target position each frame
                _teleportTargetPosition = GetSafeTeleportPosition(GlobalPosition, GetGlobalMousePosition());
                QueueRedraw();
            }
        }
        else if (_teleportAiming)
        {
            // Space released — execute teleport
            _teleportAiming = false;
            ExecuteTeleport();
        }
    }

    /// <summary>
    /// Execute the teleport to the current target position.
    /// Decrements charges and emits signal for UI update.
    /// </summary>
    private void ExecuteTeleport()
    {
        if (_teleportCharges <= 0)
        {
            LogToFile("[Player.TeleportBracers] No charges remaining");
            QueueRedraw();
            return;
        }

        Vector2 oldPosition = GlobalPosition;
        GlobalPosition = _teleportTargetPosition;
        _teleportCharges--;

        EmitSignal(SignalName.TeleportChargesChanged, _teleportCharges, MaxTeleportCharges);
        LogToFile($"[Player.TeleportBracers] Teleported from {oldPosition} to {_teleportTargetPosition}, charges: {_teleportCharges}/{MaxTeleportCharges}");

        QueueRedraw();
    }

    /// <summary>
    /// Find a safe teleport destination that doesn't place the player inside walls.
    /// The reticle should "skip through" walls — if the cursor is past a wall,
    /// the teleport lands on the far side of the wall, not before it.
    /// Uses multiple raycasts to find clear space beyond obstacles.
    /// </summary>
    /// <param name="fromPos">The player's current position.</param>
    /// <param name="cursorPos">The mouse cursor position (intended target).</param>
    /// <returns>A safe teleport destination position.</returns>
    private Vector2 GetSafeTeleportPosition(Vector2 fromPos, Vector2 cursorPos)
    {
        var spaceState = GetWorld2D().DirectSpaceState;
        if (spaceState == null)
        {
            LogToFile("[Player.TeleportBracers] Warning: Could not get DirectSpaceState");
            return cursorPos;
        }

        // Check if cursor position is directly accessible (no wall between player and cursor)
        var directQuery = PhysicsRayQueryParameters2D.Create(fromPos, cursorPos, 4); // mask 4 = obstacles
        directQuery.Exclude = new Godot.Collections.Array<Rid> { GetRid() };
        var directResult = spaceState.IntersectRay(directQuery);

        if (directResult.Count == 0)
        {
            // No wall in the way — check if cursor position itself is inside a wall
            return EnsureNotInsideWall(spaceState, cursorPos);
        }

        // Wall detected between player and cursor.
        // "Skip through" the wall: find clear space on the far side.
        Vector2 wallHitPos = (Vector2)directResult["position"];
        Vector2 direction = (cursorPos - fromPos).Normalized();
        float totalDistance = fromPos.DistanceTo(cursorPos);
        float wallDistance = fromPos.DistanceTo(wallHitPos);

        // Probe from just past the wall hit point to the cursor, looking for open space
        float probeStart = wallDistance + PlayerCollisionRadius + 2.0f;
        float step = PlayerCollisionRadius;

        // Start from cursor position and work backward to find the closest valid position to cursor
        Vector2 bestPosition = fromPos + direction * Mathf.Max(wallDistance - PlayerCollisionRadius - 2.0f, 0.0f);

        for (float dist = probeStart; dist <= totalDistance + step; dist += step)
        {
            float clampedDist = Mathf.Min(dist, totalDistance);
            Vector2 testPos = fromPos + direction * clampedDist;

            // Check if this position is inside a wall using shape query
            if (!IsPositionInsideWall(spaceState, testPos))
            {
                // Found clear space beyond the wall — verify we can raycast from there
                // back to the cursor (no additional walls in between)
                bestPosition = testPos;

                // Now find the best position closest to the cursor
                // Continue scanning forward to get as close to cursor as possible
                Vector2 lastGoodPos = testPos;
                for (float fwdDist = clampedDist + step; fwdDist <= totalDistance; fwdDist += step)
                {
                    Vector2 fwdTestPos = fromPos + direction * fwdDist;
                    if (!IsPositionInsideWall(spaceState, fwdTestPos))
                    {
                        lastGoodPos = fwdTestPos;
                    }
                    else
                    {
                        // Hit another wall, stop here
                        break;
                    }
                }

                // Also test exact cursor position
                if (!IsPositionInsideWall(spaceState, cursorPos))
                {
                    lastGoodPos = cursorPos;
                }

                return lastGoodPos;
            }
        }

        // Could not find clear space beyond the wall — teleport to just before it
        return bestPosition;
    }

    /// <summary>
    /// Check if a position is inside a wall using a point shape query.
    /// Tests 4 points around the position at the player's collision radius.
    /// </summary>
    private bool IsPositionInsideWall(PhysicsDirectSpaceState2D spaceState, Vector2 position)
    {
        // Test points at cardinal directions from position (at player radius)
        Vector2[] testOffsets = {
            new Vector2(PlayerCollisionRadius, 0),
            new Vector2(-PlayerCollisionRadius, 0),
            new Vector2(0, PlayerCollisionRadius),
            new Vector2(0, -PlayerCollisionRadius)
        };

        // Use a short raycast from center to each offset point
        // If any hits a wall, the position is too close to/inside a wall
        foreach (var offset in testOffsets)
        {
            var query = PhysicsRayQueryParameters2D.Create(position, position + offset, 4);
            query.Exclude = new Godot.Collections.Array<Rid> { GetRid() };
            var result = spaceState.IntersectRay(query);
            if (result.Count > 0)
            {
                float hitDist = position.DistanceTo((Vector2)result["position"]);
                if (hitDist < PlayerCollisionRadius)
                {
                    return true;
                }
            }
        }

        // Also test from the center outward in more directions for better coverage
        var centerQuery = PhysicsRayQueryParameters2D.Create(
            position + new Vector2(0, -1), position + new Vector2(0, 1), 4);
        centerQuery.Exclude = new Godot.Collections.Array<Rid> { GetRid() };
        var centerResult = spaceState.IntersectRay(centerQuery);
        if (centerResult.Count > 0)
        {
            float hitDist = position.DistanceTo((Vector2)centerResult["position"]);
            if (hitDist < 2.0f)
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// Ensure a position is not inside a wall. If it is, nudge it to safety.
    /// </summary>
    private Vector2 EnsureNotInsideWall(PhysicsDirectSpaceState2D spaceState, Vector2 position)
    {
        if (!IsPositionInsideWall(spaceState, position))
        {
            return position;
        }

        // Position is inside wall — try nudging in cardinal directions
        float nudgeDistance = PlayerCollisionRadius + 5.0f;
        Vector2[] nudgeDirections = {
            Vector2.Up, Vector2.Down, Vector2.Left, Vector2.Right,
            new Vector2(-1, -1).Normalized(), new Vector2(1, -1).Normalized(),
            new Vector2(-1, 1).Normalized(), new Vector2(1, 1).Normalized()
        };

        foreach (var dir in nudgeDirections)
        {
            Vector2 nudgedPos = position + dir * nudgeDistance;
            if (!IsPositionInsideWall(spaceState, nudgedPos))
            {
                return nudgedPos;
            }
        }

        // Could not find safe position, return original
        return position;
    }

    #endregion

    #region Breaker Bullets System (Issue #678)

    /// <summary>
    /// Whether breaker bullets are active (passive item, Issue #678).
    /// When true, all spawned bullets will have is_breaker_bullet = true.
    /// </summary>
    private bool _breakerBulletsActive = false;

    /// <summary>
    /// Initialize breaker bullets if the ActiveItemManager has them selected.
    /// Breaker bullets are a passive item — no special nodes needed,
    /// just a flag that modifies bullet behavior on spawn.
    /// </summary>
    private void InitBreakerBullets()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.BreakerBullets] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_breaker_bullets"))
        {
            LogToFile("[Player.BreakerBullets] ActiveItemManager missing has_breaker_bullets method");
            return;
        }

        bool hasBreakerBullets = (bool)activeItemManager.Call("has_breaker_bullets");
        if (!hasBreakerBullets)
        {
            LogToFile("[Player.BreakerBullets] Breaker bullets not selected in ActiveItemManager");
            return;
        }

        _breakerBulletsActive = true;
        LogToFile("[Player.BreakerBullets] Breaker bullets active — bullets will detonate 60px before walls");

        // Set breaker bullet flag on current weapon so all spawned bullets get the flag
        if (CurrentWeapon != null)
        {
            CurrentWeapon.IsBreakerBulletActive = true;
            LogToFile($"[Player.BreakerBullets] Set IsBreakerBulletActive on weapon: {CurrentWeapon.Name}");
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

    #region Debug Trajectory Visualization

    /// <summary>
    /// Connects to GameManager's debug_mode_toggled and invincibility_toggled signals.
    /// </summary>
    private void ConnectDebugModeSignal()
    {
        var gameManager = GetNodeOrNull("/root/GameManager");
        if (gameManager == null)
        {
            LogToFile("[Player.Debug] WARNING: GameManager not found, debug visualization disabled");
            return;
        }

        // Connect to debug mode signal (F7)
        if (gameManager.HasSignal("debug_mode_toggled"))
        {
            gameManager.Connect("debug_mode_toggled", Callable.From<bool>(OnDebugModeToggled));

            // Check if debug mode is already enabled
            if (gameManager.HasMethod("is_debug_mode_enabled"))
            {
                _debugModeEnabled = (bool)gameManager.Call("is_debug_mode_enabled");
                LogToFile($"[Player.Debug] Connected to GameManager, debug mode: {_debugModeEnabled}");
            }
        }
        else
        {
            LogToFile("[Player.Debug] WARNING: GameManager doesn't have debug_mode_toggled signal");
        }

        // Connect to invincibility mode signal (F6)
        if (gameManager.HasSignal("invincibility_toggled"))
        {
            gameManager.Connect("invincibility_toggled", Callable.From<bool>(OnInvincibilityToggled));

            // Check if invincibility mode is already enabled
            if (gameManager.HasMethod("is_invincibility_enabled"))
            {
                _invincibilityEnabled = (bool)gameManager.Call("is_invincibility_enabled");
                LogToFile($"[Player.Debug] Connected to GameManager, invincibility mode: {_invincibilityEnabled}");
                UpdateInvincibilityIndicator();
            }
        }
        else
        {
            LogToFile("[Player.Debug] WARNING: GameManager doesn't have invincibility_toggled signal");
        }
    }

    /// <summary>
    /// Called when debug mode is toggled via F7 key.
    /// </summary>
    /// <param name="enabled">True if debug mode is now enabled.</param>
    private void OnDebugModeToggled(bool enabled)
    {
        _debugModeEnabled = enabled;
        QueueRedraw();
        LogToFile($"[Player.Debug] Debug mode toggled: {(enabled ? "ON" : "OFF")}");
    }

    /// <summary>
    /// Called when invincibility mode is toggled via F6 key.
    /// </summary>
    /// <param name="enabled">True if invincibility mode is now enabled.</param>
    private void OnInvincibilityToggled(bool enabled)
    {
        _invincibilityEnabled = enabled;
        UpdateInvincibilityIndicator();
        LogToFile($"[Player] Invincibility mode: {(enabled ? "ON" : "OFF")}");
    }

    /// <summary>
    /// Updates the visual indicator for invincibility mode.
    /// Shows "INVINCIBLE" label when enabled, hides it when disabled.
    /// </summary>
    private void UpdateInvincibilityIndicator()
    {
        // Create label if it doesn't exist
        if (_invincibilityLabel == null)
        {
            _invincibilityLabel = new Label();
            _invincibilityLabel.Name = "InvincibilityLabel";
            _invincibilityLabel.Text = "БЕССМЕРТИЕ";
            _invincibilityLabel.HorizontalAlignment = HorizontalAlignment.Center;
            _invincibilityLabel.VerticalAlignment = VerticalAlignment.Center;

            // Position above the player
            _invincibilityLabel.Position = new Vector2(-60, -80);
            _invincibilityLabel.Size = new Vector2(120, 30);

            // Style: bright yellow/gold color with outline for visibility
            _invincibilityLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.9f, 0.2f, 1.0f));
            _invincibilityLabel.AddThemeColorOverride("font_outline_color", new Color(0.0f, 0.0f, 0.0f, 1.0f));
            _invincibilityLabel.AddThemeFontSizeOverride("font_size", 14);
            _invincibilityLabel.AddThemeConstantOverride("outline_size", 3);

            AddChild(_invincibilityLabel);
        }

        // Show/hide based on invincibility state
        _invincibilityLabel.Visible = _invincibilityEnabled;
    }

    /// <summary>
    /// Override _Draw to visualize grenade trajectory and teleport reticle.
    /// In simple mode: Always shows trajectory preview (semi-transparent arc).
    /// In complex mode: Only shows when debug mode is enabled (F7).
    /// Teleport bracers: Shows targeting line and player silhouette at target.
    /// </summary>
    public override void _Draw()
    {
        // Draw teleport targeting reticle if aiming (Issue #672)
        if (_teleportAiming && _teleportBracersEquipped)
        {
            DrawTeleportReticle();
        }

        // Determine if we should draw trajectory
        bool isSimpleAiming = _grenadeState == GrenadeState.SimpleAiming;
        bool isComplexAiming = _grenadeState == GrenadeState.Aiming;

        // In simple mode: always show trajectory
        // In complex mode: only show if debug mode is enabled
        if (!isSimpleAiming && !(isComplexAiming && _debugModeEnabled))
        {
            return;
        }

        // Use different colors for simple mode (more subtle) vs debug mode (bright)
        Color colorTrajectory;
        Color colorLanding;
        Color colorRadius;
        float lineWidth;

        if (isSimpleAiming)
        {
            // Semi-transparent colors for simple mode
            colorTrajectory = new Color(1.0f, 1.0f, 1.0f, 0.4f); // White semi-transparent
            colorLanding = new Color(1.0f, 0.8f, 0.2f, 0.6f); // Yellow-orange
            colorRadius = new Color(1.0f, 0.5f, 0.0f, 0.2f); // Effect radius
            lineWidth = 2.0f;
        }
        else
        {
            // Bright colors for debug mode
            colorTrajectory = new Color(1.0f, 0.8f, 0.2f, 0.9f);
            colorLanding = new Color(1.0f, 0.3f, 0.1f, 0.9f);
            colorRadius = new Color(1.0f, 0.5f, 0.0f, 0.3f);
            lineWidth = 3.0f;
        }

        // Calculate throw parameters
        Vector2 currentMousePos = GetGlobalMousePosition();
        Vector2 throwDirection;
        float throwSpeed;
        float landingDistance;
        const float SpawnOffset = 60.0f;

        // Get grenade's actual physics properties for accurate visualization
        // FIX for issue #398: Use actual grenade properties instead of hardcoded values
        float groundFriction = 300.0f; // Default
        float maxThrowSpeed = 850.0f;  // Default
        if (_activeGrenade != null && IsInstanceValid(_activeGrenade))
        {
            if (_activeGrenade.Get("ground_friction").VariantType != Variant.Type.Nil)
            {
                groundFriction = (float)_activeGrenade.Get("ground_friction");
            }
            if (_activeGrenade.Get("max_throw_speed").VariantType != Variant.Type.Nil)
            {
                maxThrowSpeed = (float)_activeGrenade.Get("max_throw_speed");
            }
        }

        if (isSimpleAiming)
        {
            // Simple mode: direction and distance based on cursor position
            Vector2 toTarget = currentMousePos - GlobalPosition;
            throwDirection = toTarget.Length() > 10.0f ? toTarget.Normalized() : new Vector2(1, 0);

            // FIX for issue #398: Account for spawn offset in distance calculation
            // The grenade starts 60 pixels ahead of the player
            Vector2 spawnPos = GlobalPosition + throwDirection * SpawnOffset;
            float throwDistance = (currentMousePos - spawnPos).Length();
            if (throwDistance < 10.0f) throwDistance = 10.0f;

            // Calculate throw speed needed to reach target
            // FIX for issue #615: No compensation factor needed. Root causes were double friction
            // (GDScript + C# both applying) and Godot default linear_damp=0.1. GDScript friction
            // was removed entirely; C# GrenadeTimer is sole friction source. v = sqrt(2*F*d) works.
            float requiredSpeed = Mathf.Sqrt(2.0f * groundFriction * throwDistance);
            throwSpeed = Mathf.Min(requiredSpeed, maxThrowSpeed);

            // Calculate actual landing distance with clamped speed
            landingDistance = (throwSpeed * throwSpeed) / (2.0f * groundFriction);
        }
        else
        {
            // Complex mode: direction based on mouse velocity
            Vector2 releaseVelocity = _currentMouseVelocity;
            float velocityMagnitude = releaseVelocity.Length();
            Vector2 dragVector = currentMousePos - _grenadeDragStart;

            if (velocityMagnitude > 10.0f)
            {
                throwDirection = SnapToOctantDirection(releaseVelocity.Normalized());
            }
            else if (dragVector.Length() > 5.0f)
            {
                throwDirection = SnapToOctantDirection(dragVector.Normalized());
            }
            else
            {
                throwDirection = new Vector2(1, 0);
            }

            // Calculate velocity-based throw speed
            const float GrenadeMass = 0.36f;
            const float MouseVelocityMultiplier = 1.5f;
            const float MinSwingDistance = 180.0f;
            const float MinThrowSpeed = 100.0f;
            const float MaxThrowSpeed = 2500.0f;

            float massRatio = GrenadeMass / 0.4f;
            float adjustedMinSwing = MinSwingDistance * massRatio;
            float transferEfficiency = Mathf.Clamp(_totalSwingDistance / adjustedMinSwing, 0.0f, 1.0f);
            float massMultiplier = 1.0f / Mathf.Sqrt(massRatio);

            throwSpeed = velocityMagnitude * MouseVelocityMultiplier * transferEfficiency * massMultiplier;
            throwSpeed = Mathf.Clamp(throwSpeed, MinThrowSpeed, MaxThrowSpeed);

            if (velocityMagnitude < 10.0f)
            {
                throwSpeed = MinThrowSpeed * 0.5f;
            }

            // FIX for issue #615: No compensation factor needed. Double friction was the root
            // cause. With single C# friction, the formula works correctly.
            landingDistance = (throwSpeed * throwSpeed) / (2.0f * groundFriction);
        }

        // Calculate spawn and landing positions
        Vector2 spawnPosition = GlobalPosition + throwDirection * SpawnOffset;
        Vector2 landingPosition = spawnPosition + throwDirection * landingDistance;

        // Convert to local coordinates for drawing
        Vector2 localStart = ToLocal(spawnPosition);
        Vector2 localEnd = ToLocal(landingPosition);

        // Draw trajectory line with dashes
        DrawTrajectoryLine(localStart, localEnd, colorTrajectory, lineWidth);

        // Draw landing point indicator (circle with X)
        DrawLandingIndicator(localEnd, colorLanding, 12.0f);

        // Draw effect radius circle at landing position
        float effectRadius = GetGrenadeEffectRadius();
        DrawCircleOutline(localEnd, effectRadius, colorRadius, 2.0f);

        // In complex mode, also draw velocity direction arrow
        if (isComplexAiming)
        {
            Vector2 localPlayerCenter = Vector2.Zero;
            Vector2 arrowEnd = localPlayerCenter + throwDirection * 40.0f;
            DrawArrow(localPlayerCenter, arrowEnd, new Color(0.2f, 1.0f, 0.2f, 0.7f), 2.0f);
        }
    }

    /// <summary>
    /// Get the effect radius of the current grenade type.
    /// FIX for Issue #432: Use type-based defaults when GDScript Call() fails in exports.
    /// </summary>
    private float GetGrenadeEffectRadius()
    {
        if (_activeGrenade != null && IsInstanceValid(_activeGrenade))
        {
            // Try to call GDScript method first
            if (_activeGrenade.HasMethod("_get_effect_radius"))
            {
                var result = _activeGrenade.Call("_get_effect_radius");
                if (result.VariantType != Variant.Type.Nil)
                {
                    return (float)result;
                }
            }

            // Try to read effect_radius property directly
            if (_activeGrenade.Get("effect_radius").VariantType != Variant.Type.Nil)
            {
                return (float)_activeGrenade.Get("effect_radius");
            }

            // FIX for Issue #432: Use type-based defaults matching scene files
            // GDScript property access may fail silently in exported builds
            var script = _activeGrenade.GetScript();
            if (script.Obj != null)
            {
                string scriptPath = ((Script)script.Obj).ResourcePath;
                if (scriptPath.Contains("frag_grenade"))
                {
                    return 225.0f;  // FragGrenade.tscn default
                }
            }
        }
        // Default: Flashbang effect radius (FlashbangGrenade.tscn)
        return 400.0f;
    }

    /// <summary>
    /// Draw the teleport targeting reticle with player silhouette at target position (Issue #672).
    /// Shows a dashed line from player to target and a player-shaped outline at the destination.
    /// </summary>
    private void DrawTeleportReticle()
    {
        Vector2 localTarget = ToLocal(_teleportTargetPosition);

        // Colors for the teleport reticle
        Color lineColor = new Color(0.4f, 0.8f, 1.0f, 0.5f);  // Cyan semi-transparent
        Color silhouetteColor;
        if (_teleportCharges > 0)
        {
            silhouetteColor = new Color(0.4f, 0.8f, 1.0f, 0.6f);  // Cyan
        }
        else
        {
            silhouetteColor = new Color(1.0f, 0.3f, 0.3f, 0.4f);  // Red (no charges)
        }

        // Draw dashed line from player to target
        DrawTrajectoryLine(Vector2.Zero, localTarget, lineColor, 2.0f);

        // Draw player silhouette at target position
        // Body circle (matches PlayerCollisionRadius = 16)
        DrawCircleOutline(localTarget, PlayerCollisionRadius, silhouetteColor, 2.5f);

        // Draw body shape inside the circle (simplified player contour)
        // Head (small circle above center)
        Vector2 headOffset = new Vector2(-6, -2);  // Matches Player.tscn Head position
        DrawCircleOutline(localTarget + headOffset, 6.0f, silhouetteColor, 2.0f);

        // Body (rectangle shape)
        Vector2 bodyCenter = localTarget + new Vector2(-4, 0);  // Matches Body position
        float bw = 5.0f, bh = 8.0f;
        DrawLine(bodyCenter + new Vector2(-bw, -bh), bodyCenter + new Vector2(bw, -bh), silhouetteColor, 2.0f);
        DrawLine(bodyCenter + new Vector2(bw, -bh), bodyCenter + new Vector2(bw, bh), silhouetteColor, 2.0f);
        DrawLine(bodyCenter + new Vector2(bw, bh), bodyCenter + new Vector2(-bw, bh), silhouetteColor, 2.0f);
        DrawLine(bodyCenter + new Vector2(-bw, bh), bodyCenter + new Vector2(-bw, -bh), silhouetteColor, 2.0f);

        // Arms (two small lines)
        // Left arm
        DrawLine(localTarget + new Vector2(18, 4), localTarget + new Vector2(24, 8), silhouetteColor, 2.0f);
        // Right arm
        DrawLine(localTarget + new Vector2(-8, 4), localTarget + new Vector2(-2, 8), silhouetteColor, 2.0f);

        // Draw charge count near the target
        // Show remaining charges as small dots around the silhouette
        for (int i = 0; i < MaxTeleportCharges; i++)
        {
            float angle = (float)i / MaxTeleportCharges * Mathf.Tau - Mathf.Pi / 2.0f;
            Vector2 dotPos = localTarget + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * (PlayerCollisionRadius + 10.0f);
            Color dotColor;
            if (i < _teleportCharges)
            {
                dotColor = new Color(0.4f, 1.0f, 0.8f, 0.8f);  // Green-cyan (available)
            }
            else
            {
                dotColor = new Color(0.5f, 0.5f, 0.5f, 0.3f);  // Gray (used)
            }
            DrawCircleOutline(dotPos, 3.0f, dotColor, 2.0f);
        }
    }

    /// <summary>
    /// Draw a circle outline at the specified position.
    /// </summary>
    private void DrawCircleOutline(Vector2 position, float radius, Color color, float width)
    {
        const int segments = 32;
        var points = new List<Vector2>();
        for (int i = 0; i <= segments; i++)
        {
            float angle = (float)i / segments * Mathf.Tau;
            points.Add(position + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * radius);
        }
        for (int i = 0; i < points.Count - 1; i++)
        {
            DrawLine(points[i], points[i + 1], color, width);
        }
    }

    /// <summary>
    /// Draw a dashed trajectory line from start to end.
    /// </summary>
    private void DrawTrajectoryLine(Vector2 start, Vector2 end, Color color, float width)
    {
        Vector2 direction = (end - start).Normalized();
        float totalLength = start.DistanceTo(end);
        const float DashLength = 15.0f;
        const float GapLength = 8.0f;

        float currentPos = 0.0f;
        while (currentPos < totalLength)
        {
            float dashEnd = Mathf.Min(currentPos + DashLength, totalLength);
            Vector2 dashStart = start + direction * currentPos;
            Vector2 dashEndPos = start + direction * dashEnd;
            DrawLine(dashStart, dashEndPos, color, width);
            currentPos = dashEnd + GapLength;
        }
    }

    /// <summary>
    /// Draw a landing indicator (circle with X) at the target position.
    /// </summary>
    private void DrawLandingIndicator(Vector2 position, Color color, float radius)
    {
        // Draw outer circle
        const int CirclePoints = 24;
        Vector2[] circlePoints = new Vector2[CirclePoints + 1];
        for (int i = 0; i <= CirclePoints; i++)
        {
            float angle = i * Mathf.Tau / CirclePoints;
            circlePoints[i] = position + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * radius;
        }
        for (int i = 0; i < CirclePoints; i++)
        {
            DrawLine(circlePoints[i], circlePoints[i + 1], color, 2.0f);
        }

        // Draw X inside
        float xSize = radius * 0.6f;
        DrawLine(position + new Vector2(-xSize, -xSize), position + new Vector2(xSize, xSize), color, 2.0f);
        DrawLine(position + new Vector2(-xSize, xSize), position + new Vector2(xSize, -xSize), color, 2.0f);
    }

    /// <summary>
    /// Draw an arrow from start to end with an arrowhead.
    /// </summary>
    private void DrawArrow(Vector2 start, Vector2 end, Color color, float width)
    {
        // Draw main line
        DrawLine(start, end, color, width);

        // Draw arrowhead
        Vector2 direction = (end - start).Normalized();
        float arrowSize = 8.0f;
        float arrowAngle = Mathf.Pi / 6.0f; // 30 degrees

        Vector2 arrowLeft = end - direction.Rotated(arrowAngle) * arrowSize;
        Vector2 arrowRight = end - direction.Rotated(-arrowAngle) * arrowSize;

        DrawLine(end, arrowLeft, color, width);
        DrawLine(end, arrowRight, color, width);
    }

    #endregion
}
