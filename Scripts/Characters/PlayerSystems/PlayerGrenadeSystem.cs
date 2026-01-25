using Godot;
using System;
using System.Collections.Generic;

namespace GodotTopDownTemplate.Characters.PlayerSystems;

/// <summary>
/// Component that handles player grenade throwing mechanics (Issue #336).
/// Extracted from Player.cs to reduce file size below 2500 lines.
///
/// Grenade mechanic:
/// Step 1: G + RMB drag right → timer starts (pin pulled)
/// Step 2: Hold G → press+hold RMB → release G → ready to throw (only RMB held)
/// Step 3: Drag and release RMB → throw grenade
/// </summary>
public partial class PlayerGrenadeSystem : Node
{
    /// <summary>
    /// Emitted when a grenade is thrown.
    /// </summary>
    [Signal]
    public delegate void GrenadeThrownEventHandler(RigidBody2D grenade, Vector2 targetPosition);

    /// <summary>
    /// Emitted when grenade count changes.
    /// </summary>
    [Signal]
    public delegate void GrenadeCountChangedEventHandler(int current, int max);

    /// <summary>
    /// Emitted when grenade state changes.
    /// </summary>
    [Signal]
    public delegate void StateChangedEventHandler(GrenadeState newState);

    /// <summary>
    /// Grenade state machine states.
    /// </summary>
    public enum GrenadeState
    {
        Idle,               // No grenade action
        TimerStarted,       // Step 1 complete - grenade timer running
        WaitingForGRelease, // Step 2 in progress - G+RMB held
        Aiming              // Step 2 complete - only RMB held, waiting to throw
    }

    // Configuration
    public PackedScene? GrenadeScene { get; set; }
    public int MaxGrenades { get; set; } = 3;
    public bool IsTutorialLevel { get; set; } = false;

    // State
    private GrenadeState _state = GrenadeState.Idle;
    private int _currentGrenades = 3;
    private RigidBody2D? _activeGrenade = null;
    private Vector2 _dragStart = Vector2.Zero;
    private bool _dragActive = false;
    private CharacterBody2D? _player = null;

    // Throw animation state
    private float _playerRotationBeforeThrow = 0.0f;
    private bool _isThrowRotating = false;
    private float _throwTargetRotation = 0.0f;
    private float _throwRotationRestoreTimer = 0.0f;

    // Constants
    private const float MinDragDistanceForStep1 = 30.0f;
    private const float ThrowRotationDuration = 0.15f;
    private const float GrenadeThrowSpeed = 600.0f;
    private const float GrenadeMinSpeed = 150.0f;
    private const float GrenadeMaxSpeed = 800.0f;

    // Wind-up tracking
    private float _windUpIntensity = 0.0f;
    private const float WindUpMaxIntensity = 1.0f;
    private const float WindUpIncreaseRate = 2.0f;

    // Mouse velocity tracking for throw direction
    private List<Vector2> _mouseVelocityHistory = new();
    private Vector2 _lastMousePosition = Vector2.Zero;
    private const int MouseVelocityHistorySize = 5;

    public override void _Ready()
    {
        _player = GetParent<CharacterBody2D>();
    }

    /// <summary>
    /// Initialize the grenade system.
    /// </summary>
    public void Initialize(int startingGrenades)
    {
        _currentGrenades = startingGrenades;
        _state = GrenadeState.Idle;
        _activeGrenade = null;
        EmitSignal(SignalName.GrenadeCountChanged, _currentGrenades, MaxGrenades);
    }

    /// <summary>
    /// Process grenade input each frame.
    /// </summary>
    public void ProcessInput(double delta)
    {
        if (_player == null) return;

        UpdateMouseVelocity(delta);
        HandleThrowRotationAnimation((float)delta);

        // Handle interrupt during grenade prep
        if (Input.IsActionJustPressed("shoot") && _state != GrenadeState.Idle)
        {
            ResetState();
            return;
        }

        switch (_state)
        {
            case GrenadeState.Idle:
                HandleIdleState();
                break;
            case GrenadeState.TimerStarted:
                HandleTimerStartedState();
                break;
            case GrenadeState.WaitingForGRelease:
                HandleWaitingForGReleaseState();
                break;
            case GrenadeState.Aiming:
                HandleAimingState((float)delta);
                break;
        }
    }

    private void HandleIdleState()
    {
        // Check for grenade initiation (G + RMB)
        if (Input.IsActionPressed("grenade") && Input.IsActionJustPressed("aim"))
        {
            if (_currentGrenades <= 0 && !IsTutorialLevel)
            {
                // Play empty sound
                var audioManager = GetNode<Node>("/root/AudioManager");
                audioManager?.Call("play_empty_click", _player?.GlobalPosition ?? Vector2.Zero);
                return;
            }

            // Start drag tracking
            _dragStart = _player?.GetGlobalMousePosition() ?? Vector2.Zero;
            _dragActive = true;
        }

        // Track drag for step 1
        if (_dragActive && Input.IsActionPressed("grenade") && Input.IsActionPressed("aim"))
        {
            var currentMouse = _player?.GetGlobalMousePosition() ?? Vector2.Zero;
            var dragVector = currentMouse - _dragStart;

            // Check if dragged right far enough
            if (dragVector.X > MinDragDistanceForStep1)
            {
                StartGrenadeTimer();
            }
        }

        // Cancel if released before completing
        if (_dragActive && (!Input.IsActionPressed("grenade") || !Input.IsActionPressed("aim")))
        {
            _dragActive = false;
        }
    }

    private void HandleTimerStartedState()
    {
        // Player is holding G with timer active
        if (!Input.IsActionPressed("grenade"))
        {
            // G released without RMB - cancel
            DropGrenadeAtFeet();
            return;
        }

        // Check for RMB press to advance to next step
        if (Input.IsActionJustPressed("aim"))
        {
            TransitionToState(GrenadeState.WaitingForGRelease);
        }
    }

    private void HandleWaitingForGReleaseState()
    {
        // G + RMB held, waiting for G release
        if (!Input.IsActionPressed("aim"))
        {
            // RMB released before G - go back
            TransitionToState(GrenadeState.TimerStarted);
            return;
        }

        if (!Input.IsActionPressed("grenade"))
        {
            // G released while RMB held - advance to aiming
            TransitionToState(GrenadeState.Aiming);
            _windUpIntensity = 0.0f;
        }
    }

    private void HandleAimingState(float delta)
    {
        // Only RMB held, aiming to throw
        UpdateWindUpIntensity(delta);

        if (!Input.IsActionPressed("aim"))
        {
            // RMB released - throw!
            var throwPosition = _player?.GetGlobalMousePosition() ?? Vector2.Zero;
            ThrowGrenade(throwPosition);
        }
    }

    /// <summary>
    /// Start the grenade timer (step 1 complete).
    /// </summary>
    private void StartGrenadeTimer()
    {
        if (GrenadeScene == null || _player == null) return;

        // Create grenade instance
        _activeGrenade = GrenadeScene.Instantiate<RigidBody2D>();
        _activeGrenade.GlobalPosition = _player.GlobalPosition;

        // Start grenade timer if it has the method
        _activeGrenade.Call("start_timer");

        // Add to scene
        _player.GetTree().CurrentScene.AddChild(_activeGrenade);

        // Consume grenade (unless tutorial)
        if (!IsTutorialLevel)
        {
            _currentGrenades--;
            EmitSignal(SignalName.GrenadeCountChanged, _currentGrenades, MaxGrenades);
        }

        TransitionToState(GrenadeState.TimerStarted);
        _dragActive = false;

        // Store rotation for throw animation
        _playerRotationBeforeThrow = _player.Rotation;
    }

    /// <summary>
    /// Drop the grenade at the player's feet (cancelled throw).
    /// </summary>
    private void DropGrenadeAtFeet()
    {
        if (_activeGrenade == null || _player == null)
        {
            ResetState();
            return;
        }

        // Position at feet
        _activeGrenade.GlobalPosition = _player.GlobalPosition;

        // Give it a small random velocity
        var rng = new RandomNumberGenerator();
        _activeGrenade.LinearVelocity = new Vector2(
            rng.RandfRange(-50, 50),
            rng.RandfRange(-50, 50)
        );

        EmitSignal(SignalName.GrenadeThrown, _activeGrenade, _player.GlobalPosition);
        ResetState();
    }

    /// <summary>
    /// Throw the grenade toward the target.
    /// </summary>
    private void ThrowGrenade(Vector2 targetPosition)
    {
        if (_activeGrenade == null || _player == null)
        {
            ResetState();
            return;
        }

        // Get throw direction from mouse velocity
        var throwDirection = GetThrowDirection();
        if (throwDirection == Vector2.Zero)
        {
            // Fallback to direction toward target
            throwDirection = (targetPosition - _player.GlobalPosition).Normalized();
        }

        // Calculate throw speed based on wind-up intensity
        var throwSpeed = Mathf.Lerp(GrenadeMinSpeed, GrenadeMaxSpeed, _windUpIntensity);

        // Get safe spawn position
        var spawnPos = GetSafeGrenadeSpawnPosition(throwDirection);
        _activeGrenade.GlobalPosition = spawnPos;
        _activeGrenade.LinearVelocity = throwDirection * throwSpeed;

        // Rotate player to face throw direction
        RotatePlayerForThrow(throwDirection);

        EmitSignal(SignalName.GrenadeThrown, _activeGrenade, targetPosition);
        ResetState();
    }

    /// <summary>
    /// Get throw direction from mouse velocity, snapped to 8 directions.
    /// </summary>
    private Vector2 GetThrowDirection()
    {
        if (_mouseVelocityHistory.Count == 0)
            return Vector2.Zero;

        // Average recent velocities
        var avgVelocity = Vector2.Zero;
        foreach (var v in _mouseVelocityHistory)
        {
            avgVelocity += v;
        }
        avgVelocity /= _mouseVelocityHistory.Count;

        if (avgVelocity.LengthSquared() < 100)
            return Vector2.Zero;

        // Snap to 8 cardinal directions
        var angle = avgVelocity.Angle();
        var snappedAngle = Mathf.Round(angle / (Mathf.Pi / 4)) * (Mathf.Pi / 4);
        return Vector2.Right.Rotated(snappedAngle);
    }

    /// <summary>
    /// Get a safe spawn position for the grenade (not inside walls).
    /// </summary>
    private Vector2 GetSafeGrenadeSpawnPosition(Vector2 direction)
    {
        if (_player == null) return Vector2.Zero;

        var spaceState = _player.GetWorld2D().DirectSpaceState;
        var targetPos = _player.GlobalPosition + direction * 50.0f;

        var query = PhysicsRayQueryParameters2D.Create(
            _player.GlobalPosition,
            targetPos,
            2 // Wall collision layer
        );
        query.Exclude = new Godot.Collections.Array<Rid> { _player.GetRid() };

        var result = spaceState.IntersectRay(query);
        if (result.Count > 0)
        {
            // Hit wall - place just before it
            var hitPoint = (Vector2)result["position"];
            return hitPoint - direction * 10.0f;
        }

        return targetPos;
    }

    /// <summary>
    /// Rotate player to face the throw direction.
    /// </summary>
    private void RotatePlayerForThrow(Vector2 direction)
    {
        if (_player == null) return;

        _throwTargetRotation = direction.Angle();
        _player.Rotation = _throwTargetRotation;
        _isThrowRotating = true;
        _throwRotationRestoreTimer = ThrowRotationDuration;
    }

    /// <summary>
    /// Handle throw rotation animation (returning to original rotation).
    /// </summary>
    private void HandleThrowRotationAnimation(float delta)
    {
        if (!_isThrowRotating || _player == null) return;

        _throwRotationRestoreTimer -= delta;
        if (_throwRotationRestoreTimer <= 0)
        {
            _isThrowRotating = false;
        }
    }

    /// <summary>
    /// Update wind-up intensity while aiming.
    /// </summary>
    private void UpdateWindUpIntensity(float delta)
    {
        _windUpIntensity = Mathf.Min(_windUpIntensity + WindUpIncreaseRate * delta, WindUpMaxIntensity);
    }

    /// <summary>
    /// Update mouse velocity tracking.
    /// </summary>
    private void UpdateMouseVelocity(double delta)
    {
        if (_player == null) return;

        var currentPos = _player.GetGlobalMousePosition();
        if (_lastMousePosition != Vector2.Zero && delta > 0)
        {
            var velocity = (currentPos - _lastMousePosition) / (float)delta;
            _mouseVelocityHistory.Add(velocity);

            while (_mouseVelocityHistory.Count > MouseVelocityHistorySize)
            {
                _mouseVelocityHistory.RemoveAt(0);
            }
        }
        _lastMousePosition = currentPos;
    }

    /// <summary>
    /// Transition to a new state.
    /// </summary>
    private void TransitionToState(GrenadeState newState)
    {
        _state = newState;
        EmitSignal(SignalName.StateChanged, (int)newState);
    }

    /// <summary>
    /// Reset to idle state.
    /// </summary>
    public void ResetState()
    {
        _state = GrenadeState.Idle;
        _activeGrenade = null;
        _dragActive = false;
        _windUpIntensity = 0.0f;
        EmitSignal(SignalName.StateChanged, (int)GrenadeState.Idle);
    }

    // --- Public Accessors ---

    public GrenadeState CurrentState => _state;
    public int CurrentGrenades => _currentGrenades;
    public bool IsPreparingGrenade => _state != GrenadeState.Idle;
    public float WindUpIntensity => _windUpIntensity;

    public void AddGrenades(int count)
    {
        _currentGrenades = Mathf.Min(_currentGrenades + count, MaxGrenades);
        EmitSignal(SignalName.GrenadeCountChanged, _currentGrenades, MaxGrenades);
    }

    public void SetGrenades(int count)
    {
        _currentGrenades = Mathf.Clamp(count, 0, MaxGrenades);
        EmitSignal(SignalName.GrenadeCountChanged, _currentGrenades, MaxGrenades);
    }
}
