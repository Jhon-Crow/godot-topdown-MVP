using Godot;
using System;
using GodotTopdown.Scripts.Projectiles;

namespace GodotTopDownTemplate.Characters;

/// <summary>
/// Player partial class: Grenade system and grenade animation methods.
/// Extracted from Player.cs to improve maintainability (Issue #1265).
/// </summary>
public partial class Player
{
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
        else if (scenePath.Contains("Aggression", StringComparison.OrdinalIgnoreCase))
        {
            grenadeType = GrenadeTimer.GrenadeType.AggressionGas;
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
}
