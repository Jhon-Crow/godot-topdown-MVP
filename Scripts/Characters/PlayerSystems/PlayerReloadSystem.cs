using Godot;
using System;

namespace GodotTopDownTemplate.Characters.PlayerSystems;

/// <summary>
/// Component that handles player weapon reload mechanics (Issue #336).
/// Extracted from Player.cs to reduce file size below 2500 lines.
///
/// Uses R-F-R key sequence for instant reload:
/// - Press R: Start reload, play mag-out sound
/// - Press F: Continue reload, play mag-in sound
/// - Press R: Complete reload, chamber round if needed
/// </summary>
public partial class PlayerReloadSystem : Node
{
    /// <summary>
    /// Emitted when reload sequence starts.
    /// </summary>
    [Signal]
    public delegate void ReloadStartedEventHandler();

    /// <summary>
    /// Emitted when reload sequence completes.
    /// </summary>
    [Signal]
    public delegate void ReloadCompletedEventHandler();

    /// <summary>
    /// Emitted when reload is cancelled.
    /// </summary>
    [Signal]
    public delegate void ReloadCancelledEventHandler();

    /// <summary>
    /// Emitted when reload animation phase changes.
    /// </summary>
    [Signal]
    public delegate void AnimPhaseChangedEventHandler(ReloadAnimPhase phase);

    /// <summary>
    /// Reload animation phases.
    /// </summary>
    public enum ReloadAnimPhase
    {
        None,
        MagOut,      // Arm moving to eject magazine
        MagOutHold,  // Holding at mag-out position
        MagIn,       // Arm moving to insert magazine
        MagInHold,   // Holding at mag-in position
        Chamber,     // Chambering round (if needed)
        Complete     // Animation complete
    }

    // State
    private int _sequenceStep = 0;        // 0 = waiting for R, 1 = waiting for F, 2 = waiting for R
    private bool _isReloading = false;
    private int _ammoAtReloadStart = 0;
    private ReloadAnimPhase _animPhase = ReloadAnimPhase.None;
    private float _animTimer = 0.0f;
    private CharacterBody2D? _player = null;

    // Animation timing constants
    private const float MagOutDuration = 0.15f;
    private const float MagOutHoldDuration = 0.1f;
    private const float MagInDuration = 0.15f;
    private const float MagInHoldDuration = 0.1f;
    private const float ChamberDuration = 0.2f;

    // Arm position offsets for animation
    public static readonly Vector2 ArmOffsetNormal = Vector2.Zero;
    public static readonly Vector2 ArmOffsetMagOut = new Vector2(-10, 5);
    public static readonly Vector2 ArmOffsetMagIn = new Vector2(-5, 3);
    public static readonly Vector2 ArmOffsetChamber = new Vector2(5, -2);

    // Arm rotation offsets for animation
    public const float ArmRotationMagOut = 0.3f;
    public const float ArmRotationMagIn = 0.15f;
    public const float ArmRotationChamber = -0.1f;

    public override void _Ready()
    {
        _player = GetParent<CharacterBody2D>();
    }

    /// <summary>
    /// Initialize the reload system.
    /// </summary>
    public void Initialize()
    {
        _sequenceStep = 0;
        _isReloading = false;
        _animPhase = ReloadAnimPhase.None;
        _animTimer = 0.0f;
    }

    /// <summary>
    /// Process reload input each frame.
    /// </summary>
    public void ProcessInput(int currentAmmo, int maxAmmo, int reserveAmmo, Callable onReloadComplete)
    {
        if (_player == null) return;

        // Check for reload input based on current step
        switch (_sequenceStep)
        {
            case 0:
                // Step 0: Waiting for first R press
                if (Input.IsActionJustPressed("reload"))
                {
                    if (currentAmmo >= maxAmmo)
                    {
                        // Already full
                        return;
                    }
                    if (reserveAmmo <= 0)
                    {
                        // No reserve ammo
                        PlayEmptyClick();
                        return;
                    }

                    // Start reload
                    _ammoAtReloadStart = currentAmmo;
                    _sequenceStep = 1;
                    _isReloading = true;
                    StartAnimPhase(ReloadAnimPhase.MagOut);
                    PlayMagOutSound();
                    EmitSignal(SignalName.ReloadStarted);
                }
                break;

            case 1:
                // Step 1: Waiting for F press
                if (Input.IsActionJustPressed("interact"))
                {
                    _sequenceStep = 2;
                    StartAnimPhase(ReloadAnimPhase.MagIn);
                    PlayMagInSound();
                }
                else if (Input.IsActionJustPressed("reload"))
                {
                    // R pressed again - cancel
                    CancelReload();
                }
                break;

            case 2:
                // Step 2: Waiting for second R press
                if (Input.IsActionJustPressed("reload"))
                {
                    // Complete the reload
                    CompleteReload(_ammoAtReloadStart > 0, onReloadComplete);
                }
                else if (Input.IsActionJustPressed("interact"))
                {
                    // F pressed again - cancel
                    CancelReload();
                }
                break;
        }
    }

    /// <summary>
    /// Update reload animation each frame.
    /// </summary>
    public void UpdateAnimation(float delta, out Vector2 armOffset, out float armRotation)
    {
        armOffset = ArmOffsetNormal;
        armRotation = 0.0f;

        if (_animPhase == ReloadAnimPhase.None)
            return;

        _animTimer += delta;

        switch (_animPhase)
        {
            case ReloadAnimPhase.MagOut:
                var magOutProgress = Mathf.Clamp(_animTimer / MagOutDuration, 0.0f, 1.0f);
                armOffset = ArmOffsetNormal.Lerp(ArmOffsetMagOut, magOutProgress);
                armRotation = Mathf.Lerp(0.0f, ArmRotationMagOut, magOutProgress);
                if (_animTimer >= MagOutDuration)
                {
                    StartAnimPhase(ReloadAnimPhase.MagOutHold);
                }
                break;

            case ReloadAnimPhase.MagOutHold:
                armOffset = ArmOffsetMagOut;
                armRotation = ArmRotationMagOut;
                if (_animTimer >= MagOutHoldDuration)
                {
                    // Wait for next input
                }
                break;

            case ReloadAnimPhase.MagIn:
                var magInProgress = Mathf.Clamp(_animTimer / MagInDuration, 0.0f, 1.0f);
                armOffset = ArmOffsetMagOut.Lerp(ArmOffsetMagIn, magInProgress);
                armRotation = Mathf.Lerp(ArmRotationMagOut, ArmRotationMagIn, magInProgress);
                if (_animTimer >= MagInDuration)
                {
                    StartAnimPhase(ReloadAnimPhase.MagInHold);
                }
                break;

            case ReloadAnimPhase.MagInHold:
                armOffset = ArmOffsetMagIn;
                armRotation = ArmRotationMagIn;
                break;

            case ReloadAnimPhase.Chamber:
                var chamberProgress = Mathf.Clamp(_animTimer / ChamberDuration, 0.0f, 1.0f);
                armOffset = ArmOffsetMagIn.Lerp(ArmOffsetChamber, chamberProgress);
                armRotation = Mathf.Lerp(ArmRotationMagIn, ArmRotationChamber, chamberProgress);
                if (_animTimer >= ChamberDuration)
                {
                    StartAnimPhase(ReloadAnimPhase.Complete);
                }
                break;

            case ReloadAnimPhase.Complete:
                // Return to normal
                var completeProgress = Mathf.Clamp(_animTimer / 0.1f, 0.0f, 1.0f);
                armOffset = ArmOffsetChamber.Lerp(ArmOffsetNormal, completeProgress);
                armRotation = Mathf.Lerp(ArmRotationChamber, 0.0f, completeProgress);
                if (_animTimer >= 0.1f)
                {
                    _animPhase = ReloadAnimPhase.None;
                }
                break;
        }
    }

    /// <summary>
    /// Start a reload animation phase.
    /// </summary>
    private void StartAnimPhase(ReloadAnimPhase phase)
    {
        _animPhase = phase;
        _animTimer = 0.0f;
        EmitSignal(SignalName.AnimPhaseChanged, (int)phase);
    }

    /// <summary>
    /// Complete the reload sequence.
    /// </summary>
    private void CompleteReload(bool hadBulletInChamber, Callable onComplete)
    {
        // Play chamber sound if needed
        if (!hadBulletInChamber)
        {
            PlayBoltSound();
            StartAnimPhase(ReloadAnimPhase.Chamber);
        }
        else
        {
            StartAnimPhase(ReloadAnimPhase.Complete);
        }

        _sequenceStep = 0;
        _isReloading = false;

        // Call completion callback
        if (onComplete.IsValid())
        {
            onComplete.Call();
        }

        EmitSignal(SignalName.ReloadCompleted);
    }

    /// <summary>
    /// Cancel the current reload.
    /// </summary>
    public void CancelReload()
    {
        _sequenceStep = 0;
        _isReloading = false;
        _animPhase = ReloadAnimPhase.None;
        _animTimer = 0.0f;
        EmitSignal(SignalName.ReloadCancelled);
    }

    // --- Sound Methods ---

    private void PlayMagOutSound()
    {
        var audioManager = GetNodeOrNull<Node>("/root/AudioManager");
        audioManager?.Call("play_reload_mag_out", _player?.GlobalPosition ?? Vector2.Zero);
    }

    private void PlayMagInSound()
    {
        var audioManager = GetNodeOrNull<Node>("/root/AudioManager");
        audioManager?.Call("play_reload_mag_in", _player?.GlobalPosition ?? Vector2.Zero);
    }

    private void PlayBoltSound()
    {
        var audioManager = GetNodeOrNull<Node>("/root/AudioManager");
        audioManager?.Call("play_m16_bolt", _player?.GlobalPosition ?? Vector2.Zero);
    }

    private void PlayEmptyClick()
    {
        var audioManager = GetNodeOrNull<Node>("/root/AudioManager");
        audioManager?.Call("play_empty_click", _player?.GlobalPosition ?? Vector2.Zero);
    }

    // --- Public Accessors ---

    public bool IsReloading => _isReloading;
    public int SequenceStep => _sequenceStep;
    public ReloadAnimPhase CurrentAnimPhase => _animPhase;
}
