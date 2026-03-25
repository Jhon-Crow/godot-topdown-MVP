using Godot;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using GodotTopDownTemplate.AbstractClasses;
using GodotTopDownTemplate.Weapons;
using GodotTopdown.Scripts.Projectiles;
using CSharpBullet = GodotTopDownTemplate.Projectiles.Bullet;
using CSharpShotgunPellet = GodotTopDownTemplate.Projectiles.ShotgunPellet;

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
    /// When true, teleport is being aimed via Experimental Sample effect.
    /// HandleTeleportBracersInput must skip its own logic while this is active
    /// to avoid instantly executing the teleport on the next frame (Space not held).
    /// </summary>
    private bool _teleportExperimentalActive = false;

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

    #region Homing Bullets System (Issue #677)

    /// <summary>
    /// Whether homing bullets are equipped (active item selected in armory).
    /// </summary>
    private bool _homingBulletsEquipped = false;

    /// <summary>
    /// Whether the homing effect is currently active (bullets steer toward enemies).
    /// </summary>
    private bool _homingActive = false;

    /// <summary>
    /// Remaining homing charges (2 per battle).
    /// </summary>
    private int _homingCharges = 2;

    /// <summary>
    /// Maximum homing charges per battle.
    /// </summary>
    private const int MaxHomingCharges = 2;

    /// <summary>
    /// Duration of homing effect per activation in seconds.
    /// </summary>
    private const float HomingDuration = 1.2f;

    /// <summary>
    /// Timer tracking remaining homing effect duration.
    /// </summary>
    private float _homingTimer = 0.0f;

    /// <summary>
    /// Path to the homing bullets activation sound.
    /// </summary>
    private const string HomingSoundPath = "res://assets/audio/homing_activation.wav";

    /// <summary>
    /// Path to the homing bullets scanner looping ambient sound (Issue #890).
    /// </summary>
    private const string HomingScannerLoopPath = "res://assets/audio/homing_scanner_loop.wav";

    /// <summary>
    /// AudioStreamPlayer for homing activation sound.
    /// </summary>
    private AudioStreamPlayer? _homingAudioPlayer = null;

    /// <summary>
    /// AudioStreamPlayer for homing scanner looping ambient sound (Issue #890).
    /// Loops while homing bullets item is equipped (always-on ambient scanner).
    /// </summary>
    private AudioStreamPlayer? _homingScannerPlayer = null;

    /// <summary>
    /// Signal emitted when homing charges change.
    /// </summary>
    [Signal]
    public delegate void HomingChargesChangedEventHandler(int current, int maximum);

    /// <summary>
    /// Signal emitted when homing effect activates.
    /// </summary>
    [Signal]
    public delegate void HomingActivatedEventHandler();

    /// <summary>
    /// Signal emitted when homing effect deactivates.
    /// </summary>
    [Signal]
    public delegate void HomingDeactivatedEventHandler();

    // Progress bar state for homing bullets (Issue #974)
    /// <summary>Whether the homing combined progress bar is visible.</summary>
    private bool _homingBarVisible = false;
    /// <summary>Whether the homing charge bar should show briefly after deactivation.</summary>
    private bool _homingChargeBarPending = false;
    /// <summary>Timer for auto-hiding homing charge bar after deactivation (300ms).</summary>
    private float _homingChargeBarHideTimer = 0.0f;
    /// <summary>Duration to show charge bar after deactivation before auto-hiding.</summary>
    private const float HomingChargeBarHideDelay = 0.3f;

    #endregion

    #region BFF Pendant System (Issue #674)

    /// <summary>
    /// Path to the enemy scene used for the BFF companion (spawn actual enemy with aggressive AI).
    /// Issue #674: Instead of a custom companion scene, we reuse the Enemy scene in aggressive state.
    /// </summary>
    private const string BffEnemyScenePath = "res://scenes/objects/Enemy.tscn";

    /// <summary>
    /// Whether the BFF pendant is equipped (active item selected in armory).
    /// </summary>
    private bool _bffPendantEquipped = false;

    /// <summary>
    /// Whether the companion has already been summoned this battle (one charge per battle).
    /// </summary>
    private bool _bffCompanionSummoned = false;

    /// <summary>
    /// Reference to the summoned companion node.
    /// </summary>
    private Node2D? _bffCompanionNode = null;

    #endregion

    #region Invisibility Suit System (Issue #673)

    /// <summary>
    /// Whether the invisibility suit is equipped (active item selected in armory).
    /// </summary>
    private bool _invisibilitySuitEquipped = false;

    /// <summary>
    /// Reference to the GDScript invisibility suit effect node.
    /// </summary>
    private Node? _invisibilitySuitEffect = null;

    /// <summary>
    /// Reference to the GDScript invisibility HUD node.
    /// </summary>
    private Node? _invisibilityHud = null;

    /// <summary>
    /// Maximum charges per battle (matches invisibility_suit_effect.gd MAX_CHARGES).
    /// </summary>
    private const int InvisibilityMaxCharges = 2;

    #endregion

    #region Force Field System (Issue #676)

    /// <summary>
    /// Whether the force field is equipped (active item selected in armory).
    /// </summary>
    private bool _forceFieldEquipped = false;

    /// <summary>
    /// Reference to the GDScript force field effect node.
    /// </summary>
    private Node? _forceFieldEffect = null;

    #endregion

    #region Breaching Charges System (Issue #1043)

    /// <summary>
    /// Whether breaching charges are equipped (active item selected in armory).
    /// </summary>
    private bool _breachingChargesEquipped = false;

    /// <summary>
    /// Reference to the GDScript breaching charges effect node.
    /// </summary>
    private Node? _breachingChargesEffect = null;

    /// <summary>
    /// Whether Space is currently held for placement detection.
    /// </summary>
    private bool _breachingHoldingForPlacement = false;

    #endregion

    #region Loudspeaker System (Issue #959)

    /// <summary>
    /// Whether the loudspeaker is equipped (active item selected in armory).
    /// </summary>
    private bool _loudspeakerEquipped = false;

    /// <summary>
    /// Reference to the GDScript loudspeaker cone visual effect node.
    /// </summary>
    private Node2D? _loudspeakerConeEffect = null;

    /// <summary>
    /// Reference to the GDScript loudspeaker progress tracker.
    /// </summary>
    private Node? _loudspeakerProgress = null;

    /// <summary>
    /// Sprite shown in player's hands while loudspeaker is held after activation.
    /// </summary>
    private Sprite2D? _loudspeakerHandSprite = null;

    /// <summary>
    /// Timer controlling how long the loudspeaker sprite stays visible.
    /// </summary>
    private float _loudspeakerHoldTimer = 0.0f;

    /// <summary>
    /// Duration (seconds) the loudspeaker sprite is shown after activation.
    /// </summary>
    private const float LoudspeakerHoldDuration = 0.6f;

    // Recoil Compensator fields (Issue #1073)
    /// <summary>Whether the recoil compensator is equipped (active item selected in armory).</summary>
    private bool _recoilCompensatorEquipped = false;

    /// <summary>Whether the recoil compensator is currently active (Space held and charge > 0).</summary>
    private bool _recoilCompensatorActive = false;

    /// <summary>Remaining charge in seconds (depletes at 1 s/s while active).</summary>
    private float _recoilCompensatorCharge = 0.0f;

    /// <summary>Maximum charge duration in seconds.</summary>
    private const float RecoilCompensatorMaxCharge = 15.0f;

    /// <summary>
    /// When > 0, the recoil compensator is active via Experimental Sample (does not require Space held).
    /// Counts down each frame and deactivates when it reaches 0.
    /// </summary>
    private float _recoilCompensatorExperimentalTimer = 0.0f;

    // Experimental Sample fields (Issue #1127)
    /// <summary>Whether the experimental sample is equipped (active item selected in armory).</summary>
    private bool _experimentalSampleEquipped = false;

    /// <summary>Remaining charges for this battle (1–5, randomised on level start).</summary>
    private int _experimentalSampleCharges = 0;

    /// <summary>Minimum charges assigned at level start.</summary>
    private const int ExperimentalSampleMinCharges = 1;

    /// <summary>Maximum charges assigned at level start.</summary>
    private const int ExperimentalSampleMaxCharges = 5;

    /// <summary>Whether the experimental sample charge bar should be drawn.</summary>
    private bool _experimentalSampleChargeBarVisible = false;

    /// <summary>Floating item icon popup node (GDScript) spawned on each effect fire.</summary>
    private GodotObject _experimentalSamplePopup = null;

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
            // Check difficulty mode for special health configuration
            var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
            bool isPowerFantasy = difficultyManager != null && (bool)difficultyManager.Call("is_power_fantasy_mode");
            bool isBlackMetal = difficultyManager != null && difficultyManager.HasMethod("is_black_metal_mode") && (bool)difficultyManager.Call("is_black_metal_mode");

            if (isPowerFantasy)
            {
                // Power Fantasy mode: 10 HP (fixed, not random)
                HealthComponent.UseRandomHealth = false;
                HealthComponent.MaxHealth = 10;
                HealthComponent.InitialHealth = 10;
                HealthComponent.InitializeHealth();
                GD.Print($"[Player] {Name}: Power Fantasy mode - spawned with {HealthComponent.CurrentHealth}/{HealthComponent.MaxHealth} HP");
            }
            else if (isBlackMetal)
            {
                // Black Metal mode: 25% less HP (Issue #958)
                // Base range 2-4 HP reduced by 0.75 multiplier -> 1-3 HP
                float hpMult = difficultyManager != null && difficultyManager.HasMethod("get_hp_multiplier")
                    ? (float)difficultyManager.Call("get_hp_multiplier")
                    : 0.75f;
                HealthComponent.UseRandomHealth = true;
                HealthComponent.MinRandomHealth = Mathf.Max(1, (int)(2 * hpMult));
                HealthComponent.MaxRandomHealth = Mathf.Max(1, (int)(4 * hpMult));
                HealthComponent.InitializeHealth();
                GD.Print($"[Player] {Name}: Black Metal mode - spawned with {HealthComponent.CurrentHealth}/{HealthComponent.MaxHealth} HP (25% less)");
                // Also apply 25% speed boost (Issue #958)
                float speedMult = difficultyManager != null && difficultyManager.HasMethod("get_player_speed_multiplier")
                    ? (float)difficultyManager.Call("get_player_speed_multiplier")
                    : 1.25f;
                MaxSpeed *= speedMult;
                GD.Print($"[Player] {Name}: Black Metal mode - speed set to {MaxSpeed} (25% faster)");
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

            // Apply Armored Skin +1 HP bonus if selected (Issue #1045)
            // Must be applied after InitializeHealth() so we add on top of the rolled value
            var activeItemManagerForHp = GetNodeOrNull("/root/ActiveItemManager");
            if (activeItemManagerForHp != null && activeItemManagerForHp.HasMethod("has_armored_skin"))
            {
                bool hasArmoredSkin = (bool)activeItemManagerForHp.Call("has_armored_skin");
                if (hasArmoredSkin)
                {
                    float newMax = HealthComponent.MaxHealth + 1;
                    float newCurrent = HealthComponent.CurrentHealth + 1;
                    HealthComponent.MaxHealth = newMax;
                    HealthComponent.SetHealth(newCurrent);
                    LogToFile($"[Player.ArmoredSkin] +1 HP bonus applied, health now {HealthComponent.CurrentHealth}/{HealthComponent.MaxHealth}");
                }
            }
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
            // Try MakarovPM first (default starting weapon), then AssaultRifle, then AKGL for backward compatibility
            CurrentWeapon = GetNodeOrNull<BaseWeapon>("MakarovPM");
            if (CurrentWeapon == null)
            {
                CurrentWeapon = GetNodeOrNull<BaseWeapon>("AssaultRifle");
            }
            if (CurrentWeapon == null)
            {
                CurrentWeapon = GetNodeOrNull<BaseWeapon>("AKGL");
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

        // Initialize homing bullets if active item manager has them selected (Issue #677)
        InitHomingBullets();

        // Initialize BFF pendant if active item manager has it selected (Issue #674)
        InitBffPendant();

        // Initialize invisibility suit if active item manager has it selected (Issue #673)
        InitInvisibilitySuit();

        // Initialize breaker bullets if active item manager has them selected (Issue #678)
        InitBreakerBullets();

        // Initialize drilling bullets if active item manager has them selected (Issue #751)
        InitDrillingBullets();

        // Initialize combat disposition if active item manager has it selected (Issue #1047)
        InitCombatDisposition();

        // Initialize force field if active item manager has it selected (Issue #676)
        InitForceField();

        // Initialize trajectory glasses if active item manager has them selected (Issue #744)
        InitTrajectoryGlasses();

        // Initialize breaching charges if active item manager has them selected (Issue #1043)
        InitBreachingCharges();

        // Initialize armored skin if active item manager has it selected (Issue #1045)
        InitArmoredSkin();

        // Apply item-specific player visual based on the equipped passive item (Issue #1142)
        ApplyItemVisual();

        // Initialize loudspeaker if active item manager has it selected (Issue #959)
        InitLoudspeaker();

        // Initialize auto-reload if active item manager has it selected (Issue #1067)
        InitAutoReload();

        // Initialize recoil compensator if active item manager has it selected (Issue #1073)
        InitRecoilCompensator();

        // Initialize experimental sample if active item manager has it selected (Issue #1127)
        InitExperimentalSample();

        // Initialize fine motor skills if active item manager has it selected (Issue #1315)
        InitFineMotorSkills();

        // Initialize dash if active item manager has it selected (Issue #1071)
        InitDash();

        // Initialize jammer HUD prohibition sign (always created; visibility toggled at runtime) (Issue #1036)
        InitJammerHud();

        // Connect to ActiveItemManager's active_item_changed signal so that picking up
        // a new active item in roguelike mode (no scene restart) immediately initialises
        // the item's subsystem on the player (Issue #1325).
        ConnectActiveItemChangedSignal();

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
        // Issue #1334 Round 10: Stop all player processing after death.
        // Without this guard, the dead player continues processing input, movement,
        // and shooting on the same frame as death. Weapon Fire() calls on a dead player
        // can cause native crashes (e.g., spawning bullets from freed/invalid state).
        if (!IsAlive)
            return;

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

        // Skip normal movement during dash — DashEffect controls velocity (Issue #1071)
        if (!IsDashActive())
        {
            ApplyMovement(inputDirection, (float)delta);
        }
        else
        {
            // DashEffect sets velocity in its own _physics_process; just slide here
            MoveAndSlide();
        }

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

        // Handle AKGL grenade launcher input (RMB) when AKGL is equipped
        // This takes priority over grenade input since the underbarrel uses RMB for firing
        bool akglGrenadeLauncherConsumedInput = HandleAKGLGrenadeLauncherInput();

        // Handle grenade input first (so it can consume shoot input)
        // Skip if sniper scope or AKGL grenade launcher already consumed the RMB input
        if (!sniperScopeConsumedInput && !akglGrenadeLauncherConsumedInput)
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

        // Handle homing bullets input (press Space to activate for 1 second) (Issue #677)
        HandleHomingBulletsInput((float)delta);

        // Update homing progress bar auto-hide timer (Issue #974)
        UpdateHomingBarTimer((float)delta);

        // Handle BFF pendant input (press Space to summon companion) (Issue #674)
        HandleBffPendantInput();

        // Handle invisibility suit input (press Space to activate) (Issue #673)
        HandleInvisibilitySuitInput();

        // Handle force field input (hold Space to activate) (Issue #676)
        HandleForceFieldInput((float)delta);

        // Handle trajectory glasses input (press Space to activate) (Issue #744)
        HandleTrajectoryGlassesInput();

        // Handle breaching charges input (hold Space near wall to place, press Space to detonate) (Issue #1043)
        HandleBreachingChargesInput();

        // Handle loudspeaker input (press Space to emit sound cone) (Issue #959)
        HandleLoudspeakerInput((float)delta);

        // Handle recoil compensator input (hold Space to eliminate recoil/spread and boost fire rate) (Issue #1073)
        HandleRecoilCompensatorInput((float)delta);

        // Handle experimental sample input (press Space to trigger random effect) (Issue #1127)
        HandleExperimentalSampleInput();

        // Update trajectory glasses progress bar auto-hide timer (Issue #974)
        UpdateTrajectoryBarTimer((float)delta);

        // Handle drilling bullets input (press Space to activate, Issue #751)
        HandleDrillingBulletsInput();

        // Handle fine motor skills input (press Space to instantly reload) (Issue #1315)
        HandleFineMotorSkillsInput();

        // Handle dash input (press Space to dash in movement direction) (Issue #1071)
        HandleDashInput();

        // Update jammer HUD visibility (Issue #1036)
        UpdateJammerHud();
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
        //
        // Issue #821 FIX: Only buffer clicks during fire cooldown, NOT during reload/pump.
        // When reloading or pumping, play empty click sound instead of buffering shot.
        if (!isAutomatic && Input.IsActionJustPressed("shoot"))
        {
            // Check if shotgun needs pumping (Issue #821)
            var shotgun = CurrentWeapon as Shotgun;
            bool shotgunNeedsPump = shotgun != null &&
                shotgun.ActionState != ShotgunActionState.Ready;

            // Check if any reload is in progress (Issue #821)
            bool isReloading = _isReloadingSequence ||
                (CurrentWeapon != null && CurrentWeapon.IsReloading);

            // Check if revolver cylinder is open (Issue #821)
            var revolver = CurrentWeapon as Revolver;
            bool revolverReloading = revolver != null &&
                revolver.ReloadState != RevolverReloadState.NotReloading;

            // Check if shotgun is in reload state (Issue #821)
            bool shotgunReloading = shotgun != null &&
                shotgun.ReloadState != ShotgunReloadState.NotReloading;

            // Check if weapon has no ammo (Issue #835)
            // Clicking on an empty weapon should not buffer a shot for after reload -
            // it should only play an empty click sound. Otherwise the buffered click
            // from an empty weapon fires automatically right after reload completes.
            // Issue #842: Shotgun uses ShellsInTube (CurrentAmmo is always 0 as a
            // placeholder, since the tube magazine is tracked separately).
            bool weaponEmpty;
            if (shotgun != null)
                weaponEmpty = shotgun.ShellsInTube <= 0;
            else
                weaponEmpty = CurrentWeapon.CurrentAmmo <= 0;

            if (isReloading || shotgunNeedsPump || revolverReloading || shotgunReloading || weaponEmpty)
            {
                // Issue #821: Don't buffer shots during reload/pump - play empty click instead
                // Issue #835: Don't buffer shots when weapon is empty
                PlayEmptyClickSound();
                GD.Print($"[Player.FIX#821/#835] Click during reload/pump/empty - playing empty click (isReloading={isReloading}, shotgunNeedsPump={shotgunNeedsPump}, revolverReloading={revolverReloading}, shotgunReloading={shotgunReloading}, weaponEmpty={weaponEmpty})");
            }
            else
            {
                _semiAutoShootBuffered = true;
            }
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
    /// Uses weapon-specific sound to match each weapon's authentic dry-fire click.
    /// Issue #842: Was always playing the M16/pistol sound for all weapons.
    /// </summary>
    private void PlayEmptyClickSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager == null) return;

        if (CurrentWeapon is Shotgun && audioManager.HasMethod("play_shotgun_empty_click"))
            audioManager.Call("play_shotgun_empty_click", GlobalPosition);
        else if (CurrentWeapon is Revolver && audioManager.HasMethod("play_revolver_empty_click"))
            audioManager.Call("play_revolver_empty_click", GlobalPosition);
        else if ((CurrentWeapon is MakarovPM || CurrentWeapon is MiniUzi || CurrentWeapon is SilencedPistol)
            && audioManager.HasMethod("play_pistol_empty_click"))
            audioManager.Call("play_pistol_empty_click", GlobalPosition);
        else if (audioManager.HasMethod("play_empty_click"))
            audioManager.Call("play_empty_click", GlobalPosition);
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
        // Check in order of specificity: SniperRifle, AKGL, MiniUzi (SMG), Shotgun, SilencedPistol, MakarovPM, then default to Rifle
        var sniperRifle = GetNodeOrNull<BaseWeapon>("SniperRifle");
        var akgl = GetNodeOrNull<BaseWeapon>("AKGL");
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
        else if (akgl != null)
        {
            detectedType = WeaponType.Rifle;
            LogToFile("[Player] Detected weapon: AK + GL (Rifle pose)");
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

        // Issue #835: Clear any buffered shot from before/during reload.
        // If player clicked LMB on an empty weapon before reload started, that click
        // should not automatically fire after reload completes.
        _semiAutoShootBuffered = false;

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

        // Set drilling bullet flag if drilling bullets are active for this magazine (Issue #751)
        // Note: direct SpawnBullet is only used when CurrentWeapon == null (no weapon system)
        // so we don't decrement DrillingBulletsRemaining here; BaseWeapon.SpawnBullet handles it.

        // Add bullet to the scene tree
        GetTree().CurrentScene.AddChild(bullet);

        // Enable homing on the bullet if homing effect is active (Issue #677)
        if (_homingActive)
        {
            if (bullet is CSharpBullet csBullet)
            {
                csBullet.EnableHoming();
            }
            else if (bullet.HasMethod("enable_homing"))
            {
                bullet.Call("enable_homing");
            }
        }
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

    /// <summary>
    /// Called when hit by a high-damage projectile with full bullet info (Issue #1453).
    /// This method is invoked by enemy_sniper_component.gd and other sources that call
    /// has_method("on_hit_with_bullet_info") before delivering explicit damage values.
    /// Without this method, those callers fell through to TakeDamage(damage) directly,
    /// bypassing the armored-skin lethal-hit check for sniper rifle shots.
    /// </summary>
    /// <param name="hitDirection">Direction the bullet was traveling.</param>
    /// <param name="caliberData">Caliber resource for effect scaling (can be null).</param>
    /// <param name="hasRicocheted">Whether the bullet had ricocheted before this hit (unused for player).</param>
    /// <param name="hasPenetrated">Whether the bullet had penetrated a wall before this hit (unused for player).</param>
    /// <param name="damage">Explicit damage to apply (default 1).</param>
    /// <param name="isFromPlayer">Unused — hits to the player always come from enemies.</param>
    public void on_hit_with_bullet_info(Vector2 hitDirection, Godot.Resource? caliberData,
        bool hasRicocheted, bool hasPenetrated, float damage = 1.0f, bool isFromPlayer = false)
    {
        _lastHitDirection = hitDirection;
        _lastCaliberData = caliberData;
        TakeDamage(damage);
    }

    /// <inheritdoc/>
    public override void TakeDamage(float amount)
    {
        if (HealthComponent == null || !IsAlive)
        {
            return;
        }

        // Check dash immunity (Issue #1071)
        // Player is immune to all damage during dash
        if (IsDashActive())
        {
            LogToFile("[Player] Hit blocked by dash immunity (C#)");
            return;
        }

        // Check force field protection (Issue #676)
        // Force field makes player invulnerable while active
        if (is_force_field_active())
        {
            LogToFile("[Player] Hit blocked by force field (C#)");
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

        // Armored Skin: spawn glass/crystal shards when at low HP OR when hit would be lethal (Issue #1045, #1453).
        // Trigger when HP is already at/below threshold (≤2) OR when the incoming damage would kill the player
        // at any HP (e.g. sniper rifle deals 50 damage — one-shots from full health must also be intercepted).
        // One-time trigger: deactivate after spawning so it only fires once per life.
        // The triggering projectile's damage is fully absorbed (return early).
        if (_armoredSkinActive && (HealthComponent.CurrentHealth <= 2 || HealthComponent.CurrentHealth - amount <= 0))
        {
            _armoredSkinActive = false;
            _armoredSkinImmune = true;
            SpawnArmoredSkinShards();
            LogToFile("[Player.ArmoredSkin] Triggering hit absorbed — damage ignored (Issue #1453)");
            // Start 0.1s immunity window to absorb remaining calls from multi-hit explosions.
            // Explosion sources (GrenadeTimer, BreakerDetonation) call on_hit_with_info in a
            // loop (up to 99 times) — all calls after the trigger must also be absorbed (Issue #1095).
            GetTree().CreateTimer(0.1f).Timeout += () => _armoredSkinImmune = false;
            // Absorb the triggering hit — no damage applied
            return;
        }

        // Absorb damage while post-trigger immunity is active (Issue #1095).
        // This covers the remaining loop iterations from multi-hit explosion damage.
        if (_armoredSkinImmune)
        {
            LogToFile("[Player.ArmoredSkin] Damage absorbed by post-trigger immunity");
            return;
        }

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

        // Apply combat disposition hit penalty (Issue #1047)
        ApplyCombatDispositionHitPenalty();
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

    /// <summary>
    /// Issue #1334 Round 10: GDScript-compatible is_alive() method.
    /// GDScript code (bullets, enemies) uses has_method("is_alive") to check if a target
    /// is alive before applying damage or physics interactions. The C# IsAlive property
    /// is not accessible via has_method() from GDScript. Without this bridge method,
    /// bullets pass through the is_alive check (returns true by default) and hit dead
    /// players, causing crashes from physics state mutations on freed/invalid nodes.
    /// </summary>
    public bool is_alive() => IsAlive;

    /// <inheritdoc/>
    public override void OnDeath()
    {
        base.OnDeath();
        // Issue #1334 Round 10: Defer collision disabling to avoid modifying physics state
        // during active physics callbacks. Setting CollisionLayer/CollisionMask during
        // body_entered/area_entered callbacks corrupts the physics server's internal collision
        // pair list, causing native segfaults. CallDeferred ensures the changes happen at the
        // end of the frame, after all physics callbacks have completed.
        CallDeferred(MethodName._DisableDeadPlayerCollision);
        GD.Print("Player died!");
    }

    /// <summary>
    /// Issue #1334 Round 10: Deferred method to disable all collision on the dead player.
    /// Called via CallDeferred from OnDeath to avoid modifying physics state during
    /// active physics callbacks (body_entered, area_entered) which causes native crashes.
    /// </summary>
    private void _DisableDeadPlayerCollision()
    {
        CollisionLayer = 0;
        CollisionMask = 0;

        // Disable the HitArea (Area2D) so bullets in flight cannot trigger
        // on_area_entered callbacks on the dead player's hit detection area.
        var hitArea = GetNodeOrNull<Area2D>("HitArea");
        if (hitArea != null)
        {
            hitArea.CollisionLayer = 0;
            hitArea.CollisionMask = 0;
            hitArea.Monitoring = false;
            hitArea.Monitorable = false;
        }

        // Disable the ThreatSphere too so LastChance doesn't process new threats.
        var threatSphere = GetNodeOrNull<Area2D>("ThreatSphere");
        if (threatSphere != null)
        {
            threatSphere.Monitoring = false;
            threatSphere.Monitorable = false;
        }
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

        // Propagate Combat Disposition bonuses to new weapon (Issue #1047)
        // This ensures the penalty persists when the weapon is swapped during a run.
        if (_combatDispositionActive)
        {
            CurrentWeapon.DamageBonus = _combatDispositionDamageBonus;
            CurrentWeapon.FireRateBonus = _combatDispositionFireRateBonus;
            LogToFile($"[Player.CombatDisposition] Propagated bonuses to new weapon {CurrentWeapon.Name}: damage {_combatDispositionDamageBonus:F1}, fire rate {_combatDispositionFireRateBonus:F1}");
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
        if (string.IsNullOrEmpty(selectedWeaponId))
        {
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
            case "ak_gl":
                scenePath = "res://scenes/weapons/csharp/AKGL.tscn";
                weaponNodeName = "AKGL";
                break;
            default:
                LogToFile($"[Player.Weapon] Unknown weapon ID '{selectedWeaponId}', keeping default");
                return;
        }

        LogToFile($"[Player.Weapon] GameManager weapon selection: {selectedWeaponId} ({weaponNodeName})");

        // Guard: if the correct weapon is already equipped, nothing to do.
        // This prevents unnecessary remove/re-add of the scene-placed MakarovPM on _Ready()
        // and avoids a crash when body_entered fires synchronously during physics processing
        // (Issue #1323 regression fix).
        if (CurrentWeapon != null && CurrentWeapon.Name == weaponNodeName)
        {
            LogToFile($"[Player.Weapon] Already equipped {weaponNodeName}, no change needed");
            return;
        }

        // Remove the current weapon (whatever it is) before equipping the new one.
        // Issue #1323: previously only MakarovPM was removed by name, so picking up a
        // new weapon while already holding a non-default weapon left the old weapon node
        // alive as a child, and picking up makarov_pm was a no-op due to an early return.
        if (CurrentWeapon != null)
        {
            var oldWeaponName = CurrentWeapon.Name;
            RemoveChild(CurrentWeapon);
            CurrentWeapon.QueueFree();
            CurrentWeapon = null;
            LogToFile($"[Player.Weapon] Removed current weapon: {oldWeaponName}");
        }

        // Load and instantiate the selected weapon
        var weaponScene = GD.Load<PackedScene>(scenePath);
        if (weaponScene != null)
        {
            var weapon = weaponScene.Instantiate<BaseWeapon>();
            weapon.Name = weaponNodeName;
            AddChild(weapon);
            CurrentWeapon = weapon;
            LogToFile($"[Player.Weapon] Equipped {weaponNodeName} (ammo: {weapon.CurrentAmmo}/{weapon.WeaponData?.MagazineSize ?? 0})");
            // Re-detect arm pose so the player's arms match the new weapon immediately.
            _weaponPoseApplied = false;
            _weaponDetectFrameCount = 0;
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

    #region AKGL Grenade Launcher System

    /// <summary>
    /// Handles AKGL underbarrel grenade launcher input when the AKGL is equipped.
    /// RMB fires the grenade launcher (single shot, no reload).
    /// Returns true if the AKGL grenade launcher consumed the RMB input.
    /// </summary>
    private bool HandleAKGLGrenadeLauncherInput()
    {
        // Only handle when AKGL is the current weapon
        var akgl = CurrentWeapon as AKGL;
        if (akgl == null)
        {
            return false;
        }

        // Handle RMB press to fire the grenade launcher
        if (Input.IsActionJustPressed("grenade_throw"))
        {
            // Only fire if not already in a grenade action and grenade is available
            if (_grenadeState == GrenadeState.Idle && !Input.IsActionPressed("grenade_prepare"))
            {
                if (akgl.GrenadeAvailable)
                {
                    // Calculate fire direction
                    Vector2 direction = (GetGlobalMousePosition() - GlobalPosition).Normalized();
                    akgl.FireGrenadeLauncher(direction);
                    LogToFile("[Player] AKGL grenade launcher fired!");
                    return true;
                }
                else
                {
                    LogToFile("[Player] AKGL grenade launcher empty - no grenade available");
                    // Still consume input to prevent grenade throw when GL is empty
                    return true;
                }
            }
        }

        return false;
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


}
