using Godot;
using GodotTopDownTemplate.AbstractClasses;

namespace GodotTopDownTemplate.Weapons;

/// <summary>
/// Shotgun action state for pump-action mechanics.
/// After firing: LMB (fire) → RMB drag UP (eject shell) → RMB drag DOWN (chamber)
/// </summary>
public enum ShotgunActionState
{
    /// <summary>
    /// Ready to fire - action closed, shell chambered.
    /// </summary>
    Ready,

    /// <summary>
    /// Just fired - needs RMB drag UP to eject spent shell.
    /// </summary>
    NeedsPumpUp,

    /// <summary>
    /// Pump up complete (shell ejected) - needs RMB drag DOWN to chamber next round.
    /// </summary>
    NeedsPumpDown
}

/// <summary>
/// Shotgun reload state for shell-by-shell loading.
/// Reload sequence: RMB drag UP (open bolt) → [MMB + RMB drag DOWN]×N (load shells) → RMB drag DOWN (close bolt)
/// </summary>
public enum ShotgunReloadState
{
    /// <summary>
    /// Not reloading - normal operation.
    /// </summary>
    NotReloading,

    /// <summary>
    /// Waiting for RMB drag UP to open bolt for loading.
    /// </summary>
    WaitingToOpen,

    /// <summary>
    /// Bolt open - ready to load shells with MMB + RMB drag DOWN.
    /// Can also close immediately with RMB drag DOWN (without MMB).
    /// </summary>
    Loading,

    /// <summary>
    /// Waiting for RMB drag DOWN to close bolt and chamber round.
    /// </summary>
    WaitingToClose
}

/// <summary>
/// Pump-action shotgun with multi-pellet spread.
/// Features manual pump-action cycling and tube magazine (shell-by-shell loading).
/// Fires ShotgunPellet projectiles with limited ricochet (35 degrees max).
/// Pellets fire in a "cloud" pattern with spatial distribution.
///
/// Shooting sequence: LMB (fire) → RMB drag UP (eject shell) → RMB drag DOWN (chamber)
/// Reload sequence: RMB drag UP (open bolt) → [MMB + RMB drag DOWN]×N (load shells) → RMB drag DOWN (close bolt)
/// Note: After opening bolt, can close immediately with RMB drag DOWN (skips loading) if shells present.
/// </summary>
public partial class Shotgun : BaseWeapon
{
    /// <summary>
    /// Minimum number of pellets per shot (inclusive).
    /// </summary>
    [Export]
    public int MinPellets { get; set; } = 6;

    /// <summary>
    /// Maximum number of pellets per shot (inclusive).
    /// </summary>
    [Export]
    public int MaxPellets { get; set; } = 12;

    /// <summary>
    /// Pellet scene to instantiate when firing.
    /// Uses ShotgunPellet which has limited ricochet (35 degrees).
    /// If not set, falls back to BulletScene.
    /// </summary>
    [Export]
    public PackedScene? PelletScene { get; set; }

    /// <summary>
    /// Maximum spatial offset for pellet spawn positions (in pixels).
    /// Creates a "cloud" effect where pellets spawn at slightly different positions
    /// along the aim direction, making some pellets appear ahead of others.
    /// This is calculated relative to the center pellet (bidirectional).
    /// </summary>
    [Export]
    public float MaxSpawnOffset { get; set; } = 15.0f;

    /// <summary>
    /// Tube magazine capacity (number of shells).
    /// </summary>
    [Export]
    public int TubeMagazineCapacity { get; set; } = 8;

    /// <summary>
    /// Minimum drag distance to register a gesture (in pixels).
    /// </summary>
    [Export]
    public float MinDragDistance { get; set; } = 30.0f;

    /// <summary>
    /// Whether this weapon uses a tube magazine (shell-by-shell loading).
    /// When true, the magazine UI should be hidden and replaced with shell count.
    /// </summary>
    public bool UsesTubeMagazine { get; } = true;

    /// <summary>
    /// Current pump-action state.
    /// </summary>
    public ShotgunActionState ActionState { get; private set; } = ShotgunActionState.Ready;

    /// <summary>
    /// Current reload state.
    /// </summary>
    public ShotgunReloadState ReloadState { get; private set; } = ShotgunReloadState.NotReloading;

    /// <summary>
    /// Number of shells currently in the tube magazine.
    /// </summary>
    public int ShellsInTube { get; private set; } = 8;

    /// <summary>
    /// Reference to the Sprite2D node for the shotgun visual.
    /// </summary>
    private Sprite2D? _shotgunSprite;

    /// <summary>
    /// Current aim direction based on mouse position.
    /// </summary>
    private Vector2 _aimDirection = Vector2.Right;

    /// <summary>
    /// Position where drag started for gesture detection.
    /// </summary>
    private Vector2 _dragStartPosition = Vector2.Zero;

    /// <summary>
    /// Whether a drag gesture is currently active.
    /// </summary>
    private bool _isDragging = false;

    /// <summary>
    /// Whether MMB is currently held (for shell loading).
    /// </summary>
    private bool _isMiddleMouseHeld = false;

    /// <summary>
    /// Whether MMB was held at any point during the current drag (for shell loading).
    /// This is needed because users often release MMB and RMB at the same time,
    /// so we need to track if MMB was held during the drag, not just at release.
    /// </summary>
    private bool _wasMiddleMouseHeldDuringDrag = false;

    /// <summary>
    /// Whether we're on the tutorial level (infinite shells).
    /// </summary>
    private bool _isTutorialLevel = false;

    /// <summary>
    /// Enable verbose logging for input timing diagnostics.
    /// Set to true to debug reload input issues.
    /// Default is true temporarily to help diagnose accidental bolt reopening issue.
    /// </summary>
    private const bool VerboseInputLogging = true;

    /// <summary>
    /// Cooldown time (in seconds) after closing bolt before it can be opened again.
    /// This prevents accidental bolt reopening due to mouse movement.
    /// History of adjustments based on user feedback:
    /// - 250ms: Initial value, too short
    /// - 400ms: Still had accidental opens
    /// - 500ms: Still had accidental opens during pump-action sequences
    /// - 750ms: Current value, provides longer protection window
    /// </summary>
    private const float BoltCloseCooldownSeconds = 0.75f;

    /// <summary>
    /// Timestamp when the bolt was last closed (for cooldown protection).
    /// </summary>
    private double _lastBoltCloseTime = 0.0;

    /// <summary>
    /// Signal emitted when action state changes.
    /// </summary>
    [Signal]
    public delegate void ActionStateChangedEventHandler(int newState);

    /// <summary>
    /// Signal emitted when reload state changes.
    /// </summary>
    [Signal]
    public delegate void ReloadStateChangedEventHandler(int newState);

    /// <summary>
    /// Signal emitted when shells in tube changes.
    /// </summary>
    [Signal]
    public delegate void ShellCountChangedEventHandler(int shellCount, int capacity);

    /// <summary>
    /// Signal emitted when the shotgun fires.
    /// </summary>
    [Signal]
    public delegate void ShotgunFiredEventHandler(int pelletCount);

    /// <summary>
    /// Signal emitted when pump action is cycled.
    /// </summary>
    [Signal]
    public delegate void PumpActionCycledEventHandler(string action);

    public override void _Ready()
    {
        base._Ready();

        // Re-initialize reserve shells for shotgun using MaxReserveAmmo from WeaponData
        // The base class initializes MagazineInventory based on StartingMagazineCount,
        // but for the shotgun we want to use MaxReserveAmmo to control reserve shells.
        //
        // IMPORTANT: ReserveAmmo property uses TotalSpareAmmo (sum of spare magazines).
        // So we need 2 magazines: one "current" (unused, just for BaseWeapon compatibility)
        // and one "spare" that holds the actual reserve shells.
        // The shotgun uses ShellsInTube for its tube magazine separately.
        if (WeaponData != null)
        {
            int maxReserve = WeaponData.MaxReserveAmmo;
            // Create 2 magazines:
            // - CurrentMagazine: unused placeholder (capacity = maxReserve but set to 0)
            // - 1 spare magazine: holds the actual reserve shells
            MagazineInventory.Initialize(2, maxReserve, fillAllMagazines: true);
            // Set CurrentMagazine to 0 since we don't use it (tube is separate)
            if (MagazineInventory.CurrentMagazine != null)
            {
                MagazineInventory.CurrentMagazine.CurrentAmmo = 0;
            }
            GD.Print($"[Shotgun] Initialized reserve shells: {ReserveAmmo} (from WeaponData.MaxReserveAmmo={maxReserve})");
        }

        // Get the shotgun sprite for visual representation
        _shotgunSprite = GetNodeOrNull<Sprite2D>("ShotgunSprite");

        if (_shotgunSprite != null)
        {
            GD.Print($"[Shotgun] ShotgunSprite found: visible={_shotgunSprite.Visible}");
        }
        else
        {
            GD.Print("[Shotgun] No ShotgunSprite node (visual model not yet added as per requirements)");
        }

        // Load pellet scene if not set
        if (PelletScene == null)
        {
            PelletScene = GD.Load<PackedScene>("res://scenes/projectiles/csharp/ShotgunPellet.tscn");
            if (PelletScene != null)
            {
                GD.Print("[Shotgun] Loaded ShotgunPellet scene");
            }
            else
            {
                GD.PrintErr("[Shotgun] WARNING: Could not load ShotgunPellet.tscn, will fallback to BulletScene");
            }
        }

        // Detect if we're on the tutorial level (for infinite shells)
        DetectTutorialLevel();

        // Initialize shell count
        ShellsInTube = TubeMagazineCapacity;

        // Emit initial shell count signal using CallDeferred to ensure it happens
        // AFTER the shotgun is added to the scene tree. This is critical because
        // GDScript handlers (like building_level.gd's _on_shell_count_changed) need
        // to find the shotgun via _player.get_node_or_null("Shotgun") to read ReserveAmmo,
        // and this only works after the shotgun is added as a child of the player.
        // Without deferring, the signal fires during _Ready() before add_child() completes,
        // causing reserve ammo to display as 0.
        CallDeferred(MethodName.EmitInitialShellCount);

        GD.Print($"[Shotgun] Ready - Pellets={MinPellets}-{MaxPellets}, Shells={ShellsInTube}/{TubeMagazineCapacity}, Reserve={ReserveAmmo}, Total={ShellsInTube + ReserveAmmo}, CloudOffset={MaxSpawnOffset}px, Tutorial={_isTutorialLevel}");
    }

    /// <summary>
    /// Detects if we're on the tutorial level for infinite shells.
    /// </summary>
    private void DetectTutorialLevel()
    {
        var currentScene = GetTree().CurrentScene;
        if (currentScene == null)
        {
            return;
        }

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

        if (_isTutorialLevel)
        {
            GD.Print("[Shotgun] Tutorial level detected - infinite shells enabled");
        }
    }

    public override void _Process(double delta)
    {
        base._Process(delta);

        // Update aim direction
        UpdateAimDirection();

        // Handle MMB for shell loading during reload
        // IMPORTANT: This must be called BEFORE HandleDragGestures() so that
        // _isMiddleMouseHeld is up-to-date when we check it during drag processing.
        // Previously, this was called AFTER HandleDragGestures(), which caused
        // MMB presses on the same frame as RMB drag start to be missed.
        HandleMiddleMouseButton();

        // Handle RMB drag gestures for pump-action and reload
        HandleDragGestures();
    }

    /// <summary>
    /// Updates the aim direction based on mouse position.
    /// </summary>
    private void UpdateAimDirection()
    {
        Vector2 mousePos = GetGlobalMousePosition();
        Vector2 toMouse = mousePos - GlobalPosition;

        if (toMouse.LengthSquared() > 0.001f)
        {
            _aimDirection = toMouse.Normalized();
        }

        // Update sprite rotation if available
        UpdateShotgunSpriteRotation(_aimDirection);
    }

    /// <summary>
    /// Updates the shotgun sprite rotation to match the aim direction.
    /// </summary>
    private void UpdateShotgunSpriteRotation(Vector2 direction)
    {
        if (_shotgunSprite == null)
        {
            return;
        }

        float angle = direction.Angle();
        _shotgunSprite.Rotation = angle;

        // Flip sprite vertically when aiming left
        bool aimingLeft = Mathf.Abs(angle) > Mathf.Pi / 2;
        _shotgunSprite.FlipV = aimingLeft;
    }

    #region Pump-Action and Reload Gesture Handling

    /// <summary>
    /// Handles RMB drag gestures for pump-action cycling and reload.
    /// Pump: Drag UP = eject shell, Drag DOWN = chamber round
    /// Reload: Drag UP = open bolt, Drag DOWN = load shell (with MMB) or close bolt
    ///
    /// Supports continuous gestures: hold RMB, drag UP (open bolt), then without
    /// releasing RMB, drag DOWN (close bolt) - all in one continuous movement.
    /// </summary>
    private void HandleDragGestures()
    {
        // Check for RMB press (start drag)
        if (Input.IsMouseButtonPressed(MouseButton.Right))
        {
            if (!_isDragging)
            {
                _dragStartPosition = GetGlobalMousePosition();
                _isDragging = true;
                // Initialize _wasMiddleMouseHeldDuringDrag based on CURRENT MMB state
                // This fixes the issue where MMB pressed at the exact same frame as RMB drag start
                // would be missed because we used to reset to false unconditionally
                _wasMiddleMouseHeldDuringDrag = _isMiddleMouseHeld;
            }
            else
            {
                // Already dragging - check for mid-drag gesture completion
                // This enables continuous gestures without releasing RMB
                Vector2 currentPosition = GetGlobalMousePosition();
                Vector2 dragVector = currentPosition - _dragStartPosition;

                // Check if a vertical gesture has been completed mid-drag
                if (TryProcessMidDragGesture(dragVector))
                {
                    // Gesture processed - reset drag start for next gesture
                    _dragStartPosition = currentPosition;
                    // Reset MMB tracking for the new gesture segment
                    _wasMiddleMouseHeldDuringDrag = _isMiddleMouseHeld;
                }
            }

            // Track if MMB is held at any point during the drag
            // This fixes the timing issue where users release both buttons simultaneously
            if (_isMiddleMouseHeld)
            {
                _wasMiddleMouseHeldDuringDrag = true;
            }
        }
        else if (_isDragging)
        {
            // RMB released - evaluate the drag gesture
            Vector2 dragEnd = GetGlobalMousePosition();
            Vector2 dragVector = dragEnd - _dragStartPosition;
            _isDragging = false;

            ProcessDragGesture(dragVector);

            // Reset the flag after processing
            _wasMiddleMouseHeldDuringDrag = false;
        }
    }

    /// <summary>
    /// Attempts to process a gesture while RMB is still held (mid-drag).
    /// This enables continuous drag-and-drop: hold RMB, drag up, then drag down
    /// all in one fluid motion without releasing RMB.
    ///
    /// Note: Shell loading (MMB + drag down) intentionally requires releasing RMB
    /// to preserve the original shell loading behavior. Only bolt open/close
    /// operations are supported mid-drag.
    /// </summary>
    /// <param name="dragVector">Current drag vector from start position.</param>
    /// <returns>True if a gesture was processed, false otherwise.</returns>
    private bool TryProcessMidDragGesture(Vector2 dragVector)
    {
        // Check if drag is long enough for a gesture
        if (dragVector.Length() < MinDragDistance)
        {
            return false;
        }

        // Determine if drag is primarily vertical
        bool isVerticalDrag = Mathf.Abs(dragVector.Y) > Mathf.Abs(dragVector.X);
        if (!isVerticalDrag)
        {
            return false; // Only vertical drags are used for shotgun
        }

        bool isDragUp = dragVector.Y < 0;
        bool isDragDown = dragVector.Y > 0;

        // Determine which gesture would be valid based on current state
        bool gestureProcessed = false;

        // For pump-action cycling
        if (ReloadState == ShotgunReloadState.NotReloading)
        {
            switch (ActionState)
            {
                case ShotgunActionState.NeedsPumpUp:
                    if (isDragUp)
                    {
                        // Mid-drag pump up - eject shell
                        ActionState = ShotgunActionState.NeedsPumpDown;
                        PlayPumpUpSound();
                        EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                        EmitSignal(SignalName.PumpActionCycled, "up");
                        GD.Print("[Shotgun] Mid-drag pump UP - shell ejected, continue dragging DOWN to chamber");
                        gestureProcessed = true;
                    }
                    break;

                case ShotgunActionState.NeedsPumpDown:
                    if (isDragDown)
                    {
                        // Mid-drag pump down - chamber round
                        // Record close time for cooldown protection
                        _lastBoltCloseTime = Time.GetTicksMsec() / 1000.0;

                        if (ShellsInTube > 0)
                        {
                            ActionState = ShotgunActionState.Ready;
                            PlayPumpDownSound();
                            EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                            EmitSignal(SignalName.PumpActionCycled, "down");
                            if (VerboseInputLogging)
                            {
                                GD.Print($"[Shotgun.Input] Mid-drag pump DOWN - chambered at time {_lastBoltCloseTime:F3}s, cooldown ends at {_lastBoltCloseTime + BoltCloseCooldownSeconds:F3}s");
                            }
                            else
                            {
                                GD.Print("[Shotgun] Mid-drag pump DOWN - chambered, ready to fire");
                            }
                        }
                        else
                        {
                            ActionState = ShotgunActionState.Ready;
                            PlayPumpDownSound();
                            EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                            if (VerboseInputLogging)
                            {
                                GD.Print($"[Shotgun.Input] Mid-drag pump DOWN - tube empty at time {_lastBoltCloseTime:F3}s, cooldown ends at {_lastBoltCloseTime + BoltCloseCooldownSeconds:F3}s");
                            }
                            else
                            {
                                GD.Print("[Shotgun] Mid-drag pump DOWN - tube empty, need to reload");
                            }
                        }
                        gestureProcessed = true;
                    }
                    break;

                case ShotgunActionState.Ready:
                    // Check if we should start reload (only if cooldown expired)
                    if (isDragUp && ShellsInTube < TubeMagazineCapacity)
                    {
                        double currentTime = Time.GetTicksMsec() / 1000.0;
                        double timeSinceClose = currentTime - _lastBoltCloseTime;
                        bool inCooldown = timeSinceClose < BoltCloseCooldownSeconds;

                        if (VerboseInputLogging)
                        {
                            GD.Print($"[Shotgun.Input] Mid-drag UP in Ready state: currentTime={currentTime:F3}s, lastClose={_lastBoltCloseTime:F3}s, elapsed={timeSinceClose:F3}s, cooldown={BoltCloseCooldownSeconds}s, inCooldown={inCooldown}");
                        }

                        if (!inCooldown)
                        {
                            // Mid-drag start reload
                            StartReload();
                            gestureProcessed = true;
                        }
                        else if (VerboseInputLogging)
                        {
                            GD.Print($"[Shotgun.Input] Mid-drag bolt open BLOCKED by cooldown ({timeSinceClose:F3}s < {BoltCloseCooldownSeconds}s)");
                        }
                    }
                    break;
            }
        }
        else
        {
            // For reload sequence
            switch (ReloadState)
            {
                case ShotgunReloadState.WaitingToOpen:
                    if (isDragUp)
                    {
                        // Mid-drag open bolt
                        ReloadState = ShotgunReloadState.Loading;
                        PlayActionOpenSound();
                        EmitSignal(SignalName.ReloadStateChanged, (int)ReloadState);
                        GD.Print("[Shotgun] Mid-drag bolt opened - continue dragging DOWN to close (or use MMB to load)");
                        gestureProcessed = true;
                    }
                    break;

                case ShotgunReloadState.Loading:
                    if (isDragDown)
                    {
                        // Mid-drag in loading state - only allow closing bolt, not loading shells
                        // Shell loading should only work with the release-based gesture (old behavior)
                        bool shouldLoadShell = _wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld;

                        if (VerboseInputLogging)
                        {
                            GD.Print($"[Shotgun.Input] Mid-drag DOWN in Loading state: shouldLoad={shouldLoadShell}");
                        }

                        if (shouldLoadShell)
                        {
                            // MMB held - don't process mid-drag, let user release RMB to load shell
                            // This preserves the old shell loading behavior while allowing
                            // continuous bolt open/close gestures
                            return false;
                        }
                        else
                        {
                            CompleteReload();
                        }
                        gestureProcessed = true;
                    }
                    break;

                case ShotgunReloadState.WaitingToClose:
                    if (isDragDown)
                    {
                        CompleteReload();
                        gestureProcessed = true;
                    }
                    break;
            }
        }

        return gestureProcessed;
    }

    /// <summary>
    /// Processes a completed drag gesture based on direction and context.
    /// </summary>
    private void ProcessDragGesture(Vector2 dragVector)
    {
        // Check if drag is long enough
        if (dragVector.Length() < MinDragDistance)
        {
            return;
        }

        // Determine if drag is primarily vertical
        bool isVerticalDrag = Mathf.Abs(dragVector.Y) > Mathf.Abs(dragVector.X);
        if (!isVerticalDrag)
        {
            return; // Only vertical drags are used for shotgun
        }

        bool isDragUp = dragVector.Y < 0;
        bool isDragDown = dragVector.Y > 0;

        // Handle based on current state (reload takes priority)
        if (ReloadState != ShotgunReloadState.NotReloading)
        {
            ProcessReloadGesture(isDragUp, isDragDown);
        }
        else
        {
            ProcessPumpActionGesture(isDragUp, isDragDown);
        }
    }

    /// <summary>
    /// Processes drag gesture for pump-action cycling.
    /// After firing: RMB drag UP (eject shell) → RMB drag DOWN (chamber)
    /// </summary>
    private void ProcessPumpActionGesture(bool isDragUp, bool isDragDown)
    {
        switch (ActionState)
        {
            case ShotgunActionState.NeedsPumpUp:
                if (isDragUp)
                {
                    // Eject spent shell (pull pump back/up)
                    ActionState = ShotgunActionState.NeedsPumpDown;
                    PlayPumpUpSound();
                    EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                    EmitSignal(SignalName.PumpActionCycled, "up");
                    GD.Print("[Shotgun] Pump UP - shell ejected, now pump DOWN to chamber");
                }
                break;

            case ShotgunActionState.NeedsPumpDown:
                if (isDragDown)
                {
                    // Chamber next round (push pump forward/down)
                    // Record close time for cooldown protection
                    _lastBoltCloseTime = Time.GetTicksMsec() / 1000.0;

                    if (ShellsInTube > 0)
                    {
                        ActionState = ShotgunActionState.Ready;
                        PlayPumpDownSound();
                        EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                        EmitSignal(SignalName.PumpActionCycled, "down");
                        if (VerboseInputLogging)
                        {
                            GD.Print($"[Shotgun.Input] Release-based pump DOWN - chambered at time {_lastBoltCloseTime:F3}s, cooldown ends at {_lastBoltCloseTime + BoltCloseCooldownSeconds:F3}s");
                        }
                        else
                        {
                            GD.Print("[Shotgun] Pump DOWN - chambered, ready to fire");
                        }
                    }
                    else
                    {
                        // No shells in tube - go to ready state to allow reload
                        ActionState = ShotgunActionState.Ready;
                        PlayPumpDownSound();
                        EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                        if (VerboseInputLogging)
                        {
                            GD.Print($"[Shotgun.Input] Release-based pump DOWN - tube empty at time {_lastBoltCloseTime:F3}s, cooldown ends at {_lastBoltCloseTime + BoltCloseCooldownSeconds:F3}s");
                        }
                        else
                        {
                            GD.Print("[Shotgun] Pump DOWN - tube empty, need to reload");
                        }
                    }
                }
                break;

            case ShotgunActionState.Ready:
                // If ready and drag UP, might be starting reload (open bolt)
                // Check cooldown to prevent accidental bolt reopening after close
                if (isDragUp && ShellsInTube < TubeMagazineCapacity)
                {
                    if (!IsInBoltCloseCooldown())
                    {
                        StartReload();
                    }
                    else if (VerboseInputLogging)
                    {
                        GD.Print("[Shotgun.Input] Release-based bolt open BLOCKED by cooldown");
                    }
                }
                break;
        }
    }

    /// <summary>
    /// Processes drag gesture for reload sequence.
    /// Reload: RMB drag up (open bolt) → [MMB + RMB drag down]×N (load) → RMB drag down (close bolt)
    /// Note: Can close immediately with RMB drag down (without MMB) if shells are present.
    /// </summary>
    private void ProcessReloadGesture(bool isDragUp, bool isDragDown)
    {
        switch (ReloadState)
        {
            case ShotgunReloadState.WaitingToOpen:
                if (isDragUp)
                {
                    // Open bolt for loading
                    ReloadState = ShotgunReloadState.Loading;
                    PlayActionOpenSound();
                    EmitSignal(SignalName.ReloadStateChanged, (int)ReloadState);
                    GD.Print("[Shotgun] Bolt opened for loading - MMB + RMB drag down to load shells, or RMB drag down to close");
                }
                break;

            case ShotgunReloadState.Loading:
                if (isDragDown)
                {
                    // Use _wasMiddleMouseHeldDuringDrag instead of _isMiddleMouseHeld
                    // This fixes the timing issue where users release MMB and RMB simultaneously
                    bool shouldLoadShell = _wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld;

                    if (VerboseInputLogging)
                    {
                        GD.Print($"[Shotgun.Input] Drag DOWN in Loading state: _wasMMBDuringDrag={_wasMiddleMouseHeldDuringDrag}, _isMMBHeld={_isMiddleMouseHeld}, shouldLoad={shouldLoadShell}");
                    }

                    if (shouldLoadShell)
                    {
                        // Load a shell (MMB + RMB drag down)
                        LoadShell();
                    }
                    else
                    {
                        // Close bolt without MMB - finish reload
                        CompleteReload();
                    }
                }
                break;

            case ShotgunReloadState.WaitingToClose:
                if (isDragDown)
                {
                    // Close bolt
                    CompleteReload();
                }
                break;
        }
    }

    /// <summary>
    /// Handles middle mouse button for shell loading.
    /// </summary>
    private void HandleMiddleMouseButton()
    {
        _isMiddleMouseHeld = Input.IsMouseButtonPressed(MouseButton.Middle);
    }

    #endregion

    #region Reload System

    /// <summary>
    /// Emits the initial shell count signal after the shotgun is added to the scene tree.
    /// This is called via CallDeferred to ensure the signal is emitted after add_child() completes,
    /// allowing GDScript handlers to find the shotgun node and read ReserveAmmo correctly.
    /// </summary>
    private void EmitInitialShellCount()
    {
        EmitSignal(SignalName.ShellCountChanged, ShellsInTube, TubeMagazineCapacity);
        GD.Print($"[Shotgun] Initial ShellCountChanged emitted (deferred): {ShellsInTube}/{TubeMagazineCapacity}, ReserveAmmo={ReserveAmmo}");
    }

    /// <summary>
    /// Starts the shotgun reload sequence by opening the bolt directly.
    /// Called when RMB drag UP is performed while in Ready state.
    /// </summary>
    public void StartReload()
    {
        if (ReloadState != ShotgunReloadState.NotReloading)
        {
            return; // Already reloading
        }

        if (ShellsInTube >= TubeMagazineCapacity)
        {
            GD.Print("[Shotgun] Cannot reload - tube is already full");
            return; // Tube is full
        }

        // Open bolt directly - the RMB drag UP that triggered this already counts as "open bolt"
        ReloadState = ShotgunReloadState.Loading;
        PlayActionOpenSound();
        EmitSignal(SignalName.ReloadStateChanged, (int)ReloadState);
        EmitSignal(SignalName.ReloadStarted);
        GD.Print("[Shotgun] Bolt opened for loading - MMB + RMB drag DOWN to load shells, or RMB drag DOWN to close");
    }

    /// <summary>
    /// Loads a single shell into the tube magazine.
    /// In tutorial mode, shells are infinite (no reserve ammo required).
    /// </summary>
    private void LoadShell()
    {
        GD.Print($"[Shotgun] LoadShell called - ReloadState={ReloadState}, ShellsInTube={ShellsInTube}/{TubeMagazineCapacity}, Tutorial={_isTutorialLevel}, ReserveAmmo={ReserveAmmo}");

        if (ReloadState != ShotgunReloadState.Loading)
        {
            GD.Print("[Shotgun] LoadShell skipped - not in Loading state");
            return;
        }

        if (ShellsInTube >= TubeMagazineCapacity)
        {
            GD.Print("[Shotgun] Tube is full");
            return;
        }

        // In tutorial mode, allow infinite shell loading without reserve ammo
        if (!_isTutorialLevel && ReserveAmmo <= 0)
        {
            GD.Print("[Shotgun] No more reserve shells (not tutorial mode)");
            return;
        }

        // Load one shell
        ShellsInTube++;

        // Consume from reserve (only in non-tutorial mode)
        // Reserve shells are in spare magazines, not CurrentMagazine
        if (!_isTutorialLevel && ReserveAmmo > 0)
        {
            // Find a spare magazine with ammo and consume from it
            foreach (var mag in MagazineInventory.SpareMagazines)
            {
                if (mag.CurrentAmmo > 0)
                {
                    mag.CurrentAmmo--;
                    break;
                }
            }
        }

        PlayShellLoadSound();
        EmitSignal(SignalName.ShellCountChanged, ShellsInTube, TubeMagazineCapacity);
        GD.Print($"[Shotgun] Shell loaded - {ShellsInTube}/{TubeMagazineCapacity} shells in tube");
    }

    /// <summary>
    /// Completes the reload sequence by closing the action.
    /// Records the close time to enable cooldown protection against accidental reopening.
    /// </summary>
    private void CompleteReload()
    {
        if (ReloadState == ShotgunReloadState.NotReloading)
        {
            return;
        }

        ReloadState = ShotgunReloadState.NotReloading;
        ActionState = ShotgunActionState.Ready;

        // Record bolt close time for cooldown protection
        _lastBoltCloseTime = Time.GetTicksMsec() / 1000.0;

        PlayActionCloseSound();
        EmitSignal(SignalName.ReloadStateChanged, (int)ReloadState);
        EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
        EmitSignal(SignalName.ReloadFinished);
        GD.Print($"[Shotgun] Reload complete - ready to fire with {ShellsInTube} shells");
    }

    /// <summary>
    /// Checks if we are within the cooldown period after closing the bolt.
    /// This prevents accidental bolt reopening due to continued mouse movement.
    /// </summary>
    /// <returns>True if cooldown is active and bolt opening should be blocked.</returns>
    private bool IsInBoltCloseCooldown()
    {
        double currentTime = Time.GetTicksMsec() / 1000.0;
        double elapsedSinceClose = currentTime - _lastBoltCloseTime;
        bool inCooldown = elapsedSinceClose < BoltCloseCooldownSeconds;

        if (inCooldown && VerboseInputLogging)
        {
            GD.Print($"[Shotgun.Input] Bolt open blocked by cooldown: {elapsedSinceClose:F3}s < {BoltCloseCooldownSeconds}s");
        }

        return inCooldown;
    }

    /// <summary>
    /// Cancels an in-progress reload.
    /// </summary>
    public void CancelReload()
    {
        if (ReloadState != ShotgunReloadState.NotReloading)
        {
            ReloadState = ShotgunReloadState.NotReloading;
            EmitSignal(SignalName.ReloadStateChanged, (int)ReloadState);
            GD.Print("[Shotgun] Reload cancelled");
        }
    }

    #endregion

    /// <summary>
    /// Fires the shotgun - spawns multiple pellets with spread in a cloud pattern.
    /// After firing, requires manual pump-action cycling:
    /// RMB drag UP (eject shell) → RMB drag DOWN (chamber next round)
    /// </summary>
    /// <param name="direction">Base direction to fire.</param>
    /// <returns>True if the weapon fired successfully.</returns>
    public override bool Fire(Vector2 direction)
    {
        // Check if reloading
        if (ReloadState != ShotgunReloadState.NotReloading)
        {
            GD.Print("[Shotgun] Cannot fire - currently reloading");
            return false;
        }

        // Check if action is ready
        if (ActionState != ShotgunActionState.Ready)
        {
            GD.Print($"[Shotgun] Cannot fire - pump action required: {ActionState}");
            PlayEmptyClickSound();
            return false;
        }

        // Check for empty tube
        if (ShellsInTube <= 0)
        {
            PlayEmptyClickSound();
            GD.Print("[Shotgun] Cannot fire - tube empty, need to reload");
            return false;
        }

        // Check fire rate - use either BulletScene or PelletScene
        PackedScene? projectileScene = PelletScene ?? BulletScene;
        if (WeaponData == null || projectileScene == null)
        {
            return false;
        }

        // Use aim direction
        Vector2 fireDirection = _aimDirection;

        // Determine number of pellets (random between min and max)
        int pelletCount = GD.RandRange(MinPellets, MaxPellets);

        // Get spread angle from weapon data
        float spreadAngle = WeaponData.SpreadAngle;
        float spreadRadians = Mathf.DegToRad(spreadAngle);
        float halfSpread = spreadRadians / 2.0f;

        GD.Print($"[Shotgun] Firing {pelletCount} pellets with {spreadAngle}° spread (cloud pattern)");

        // Fire all pellets simultaneously with spatial distribution (cloud effect)
        FirePelletsAsCloud(fireDirection, pelletCount, spreadRadians, halfSpread, projectileScene);

        // Consume shell from tube
        ShellsInTube--;
        EmitSignal(SignalName.ShellCountChanged, ShellsInTube, TubeMagazineCapacity);

        // Set action state - needs manual pump cycling (UP first to eject shell)
        ActionState = ShotgunActionState.NeedsPumpUp;
        EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
        GD.Print("[Shotgun] Fired! Now RMB drag UP to eject shell");

        // Play shotgun sound
        PlayShotgunSound();

        // Emit gunshot for sound propagation
        EmitGunshotSound();

        // Trigger large screen shake
        TriggerScreenShake(fireDirection);

        // Emit signals
        EmitSignal(SignalName.Fired);
        EmitSignal(SignalName.ShotgunFired, pelletCount);
        EmitSignal(SignalName.AmmoChanged, ShellsInTube, ReserveAmmo);

        return true;
    }

    /// <summary>
    /// Fires all pellets simultaneously with spatial distribution to create a "cloud" pattern.
    /// Pellets spawn with small position offsets along the aim direction,
    /// making some appear ahead of others while maintaining the angular spread.
    /// The offsets are calculated relative to the center pellet (bidirectional).
    /// </summary>
    private void FirePelletsAsCloud(Vector2 fireDirection, int pelletCount, float spreadRadians, float halfSpread, PackedScene projectileScene)
    {
        for (int i = 0; i < pelletCount; i++)
        {
            // Distribute pellets evenly across the spread cone with some randomness
            float baseAngle;
            if (pelletCount > 1)
            {
                // Distribute pellets across the cone
                float progress = (float)i / (pelletCount - 1);
                baseAngle = Mathf.Lerp(-halfSpread, halfSpread, progress);
                // Add small random deviation
                baseAngle += (float)GD.RandRange(-spreadRadians * 0.1, spreadRadians * 0.1);
            }
            else
            {
                // Single pellet goes straight
                baseAngle = 0;
            }

            // Calculate random spatial offset along the fire direction
            // This creates the "cloud" effect where some pellets are slightly ahead/behind
            // Offset is bidirectional (positive = ahead, negative = behind center)
            float spawnOffset = (float)GD.RandRange(-MaxSpawnOffset, MaxSpawnOffset);

            Vector2 pelletDirection = fireDirection.Rotated(baseAngle);
            SpawnPelletWithOffset(pelletDirection, spawnOffset, projectileScene);
        }
    }

    /// <summary>
    /// Spawns a pellet projectile with a spatial offset along its direction.
    /// The offset creates the cloud effect where pellets appear at different depths.
    /// </summary>
    private void SpawnPelletWithOffset(Vector2 direction, float extraOffset, PackedScene projectileScene)
    {
        if (projectileScene == null || WeaponData == null)
        {
            return;
        }

        // Check if the bullet spawn path is blocked by a wall
        var (isBlocked, hitPosition, hitNormal) = CheckBulletSpawnPath(direction);

        Vector2 spawnPosition;
        if (isBlocked)
        {
            // Wall detected at point-blank range - spawn at weapon position
            spawnPosition = GlobalPosition + direction * 2.0f;
        }
        else
        {
            // Normal case: spawn at offset position plus extra cloud offset
            spawnPosition = GlobalPosition + direction * (BulletSpawnOffset + extraOffset);
        }

        var pellet = projectileScene.Instantiate<Node2D>();
        pellet.GlobalPosition = spawnPosition;

        // Set pellet properties
        if (pellet.HasMethod("SetDirection"))
        {
            pellet.Call("SetDirection", direction);
        }
        else
        {
            pellet.Set("Direction", direction);
        }

        // Set pellet speed from weapon data
        pellet.Set("Speed", WeaponData.BulletSpeed);

        // Set shooter ID to prevent self-damage
        var owner = GetParent();
        if (owner != null)
        {
            pellet.Set("ShooterId", owner.GetInstanceId());
        }

        GetTree().CurrentScene.AddChild(pellet);
    }

    #region Audio

    /// <summary>
    /// Plays the shotgun empty click sound.
    /// Uses shotgun-specific empty click for authentic pump-action sound.
    /// </summary>
    private void PlayEmptyClickSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_shotgun_empty_click"))
        {
            audioManager.Call("play_shotgun_empty_click", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the shotgun firing sound.
    /// Randomly selects from 4 shotgun shot variants for variety.
    /// </summary>
    private void PlayShotgunSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_shotgun_shot"))
        {
            audioManager.Call("play_shotgun_shot", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the pump up sound (ejecting shell).
    /// Opens the action to eject the spent shell casing.
    /// </summary>
    private async void PlayPumpUpSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_shotgun_action_open"))
        {
            audioManager.Call("play_shotgun_action_open", GlobalPosition);
        }

        // Shell ejects shortly after action opens
        await ToSignal(GetTree().CreateTimer(0.15), "timeout");
        if (audioManager != null && audioManager.HasMethod("play_shell_shotgun"))
        {
            audioManager.Call("play_shell_shotgun", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the pump down sound (chambering round).
    /// Closes the action to chamber the next shell.
    /// </summary>
    private void PlayPumpDownSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_shotgun_action_close"))
        {
            audioManager.Call("play_shotgun_action_close", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the action open sound (for reload).
    /// Opens the bolt to begin shell loading sequence.
    /// </summary>
    private void PlayActionOpenSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_shotgun_action_open"))
        {
            audioManager.Call("play_shotgun_action_open", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the action close sound (after reload).
    /// Closes the bolt to complete reload sequence and chamber a round.
    /// </summary>
    private void PlayActionCloseSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_shotgun_action_close"))
        {
            audioManager.Call("play_shotgun_action_close", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the shell load sound.
    /// Sound of inserting a shell into the tube magazine.
    /// </summary>
    private void PlayShellLoadSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_shotgun_load_shell"))
        {
            audioManager.Call("play_shotgun_load_shell", GlobalPosition);
        }
    }

    /// <summary>
    /// Emits gunshot sound for enemy detection.
    /// </summary>
    private void EmitGunshotSound()
    {
        var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
        if (soundPropagation != null && soundPropagation.HasMethod("emit_sound"))
        {
            float loudness = WeaponData?.Loudness ?? 1469.0f;
            soundPropagation.Call("emit_sound", 0, GlobalPosition, 0, this, loudness);
        }
    }

    /// <summary>
    /// Triggers large screen shake for shotgun recoil.
    /// </summary>
    private void TriggerScreenShake(Vector2 shootDirection)
    {
        if (WeaponData == null || WeaponData.ScreenShakeIntensity <= 0)
        {
            return;
        }

        var screenShakeManager = GetNodeOrNull("/root/ScreenShakeManager");
        if (screenShakeManager == null || !screenShakeManager.HasMethod("add_shake"))
        {
            return;
        }

        // Large shake intensity for shotgun
        float shakeIntensity = WeaponData.ScreenShakeIntensity;
        float recoveryTime = WeaponData.ScreenShakeMinRecoveryTime;

        screenShakeManager.Call("add_shake", shootDirection, shakeIntensity, recoveryTime);
    }

    #endregion

    #region Public Properties

    /// <summary>
    /// Gets the current aim direction.
    /// </summary>
    public Vector2 AimDirection => _aimDirection;

    /// <summary>
    /// Gets whether the shotgun is ready to fire.
    /// </summary>
    public bool IsReadyToFire => ActionState == ShotgunActionState.Ready &&
                                  ReloadState == ShotgunReloadState.NotReloading &&
                                  ShellsInTube > 0;

    /// <summary>
    /// Gets whether the shotgun needs pump action.
    /// </summary>
    public bool NeedsPumpAction => ActionState != ShotgunActionState.Ready;

    /// <summary>
    /// Gets a human-readable description of the current state.
    /// </summary>
    public string StateDescription
    {
        get
        {
            if (ReloadState != ShotgunReloadState.NotReloading)
            {
                return ReloadState switch
                {
                    ShotgunReloadState.WaitingToOpen => "RMB drag up to open",
                    ShotgunReloadState.Loading => "MMB + RMB drag down to load (or RMB down to close)",
                    ShotgunReloadState.WaitingToClose => "RMB drag down to close",
                    _ => "Reloading..."
                };
            }

            return ActionState switch
            {
                ShotgunActionState.NeedsPumpUp => "RMB drag UP to eject",
                ShotgunActionState.NeedsPumpDown => "RMB drag DOWN to chamber",
                ShotgunActionState.Ready when ShellsInTube <= 0 => "Empty - reload needed",
                ShotgunActionState.Ready => "Ready",
                _ => "Unknown"
            };
        }
    }

    #endregion
}
