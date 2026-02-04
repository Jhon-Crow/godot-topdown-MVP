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
/// Reload sequence: RMB drag UP (open bolt) → [MMB hold + RMB drag DOWN]×N (load shells) → RMB drag DOWN (close bolt)
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
    /// Bolt open - ready to load shells with MMB hold + RMB drag DOWN.
    /// Close bolt with RMB drag DOWN (without MMB).
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
/// Reload sequence: RMB drag UP (open bolt) → [MMB hold + RMB drag DOWN]×N (load shells) → RMB drag DOWN (close bolt)
/// Note: After opening bolt, can close immediately with RMB drag DOWN (skips loading).
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
    /// Last fire direction (used to eject casing after pump up).
    /// </summary>
    private Vector2 _lastFireDirection = Vector2.Right;

    /// <summary>
    /// Position where drag started for gesture detection.
    /// </summary>
    private Vector2 _dragStartPosition = Vector2.Zero;

    /// <summary>
    /// Whether a drag gesture is currently active.
    /// </summary>
    private bool _isDragging = false;

    /// <summary>
    /// Whether MMB is currently held (tracked via polling).
    /// </summary>
    private bool _isMiddleMouseHeld = false;

    /// <summary>
    /// Whether MMB is currently held (tracked via event-based _Input).
    /// This is a fallback for when Input.IsMouseButtonPressed() doesn't work.
    /// See Godot issue #72507 for known MMB inconsistencies.
    /// </summary>
    private bool _isMiddleMouseHeldEvent = false;

    /// <summary>
    /// Whether MMB was held at any point during the current drag (for shell loading).
    /// This is needed because users often release MMB and RMB at the same time,
    /// so we need to track if MMB was held during the drag, not just at release.
    ///
    /// ROOT CAUSE FIX (Issue #243): The "only works on second attempt" bug had TWO causes:
    ///
    /// 1. (Initial fix) _isMiddleMouseHeld was updated AFTER HandleDragGestures() in _Process().
    ///    Fixed by updating _isMiddleMouseHeld BEFORE HandleDragGestures() in _Process().
    ///
    /// 2. (Second fix) When already dragging, the MMB tracking was done AFTER calling
    ///    TryProcessMidDragGesture(). This meant if user pressed MMB mid-drag:
    ///    - TryProcessMidDragGesture() checked _wasMiddleMouseHeldDuringDrag (still false)
    ///    - THEN MMB tracking updated _wasMiddleMouseHeldDuringDrag = true (too late!)
    ///    Fixed by moving MMB tracking BEFORE TryProcessMidDragGesture() call.
    /// </summary>
    private bool _wasMiddleMouseHeldDuringDrag = false;

    /// <summary>
    /// Whether a shell was loaded during the current mid-drag gesture.
    /// This prevents loading multiple shells in one drag motion (Issue #266).
    ///
    /// ROOT CAUSE (Issue #266): When TryProcessMidDragGesture loads a shell and resets
    /// _dragStartPosition, it also resets _wasMiddleMouseHeldDuringDrag = anyMMBDetected.
    /// Since MMB is still held, this is true. When RMB is released, ProcessReloadGesture
    /// sees _wasMiddleMouseHeldDuringDrag = true and loads another shell.
    ///
    /// Fix: Track if a shell was loaded during mid-drag, and skip loading on RMB release.
    /// </summary>
    private bool _shellLoadedDuringMidDrag = false;

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
    /// Enable per-frame diagnostic logging during drag.
    /// This logs the raw MMB state every frame to diagnose issue #243.
    /// WARNING: Very verbose! Only enable when actively debugging.
    /// </summary>
    private const bool PerFrameDragLogging = true;

    /// <summary>
    /// Frame counter for diagnostic purposes during drag operations.
    /// Used to track how many frames pass between drag start and release.
    /// </summary>
    private int _dragFrameCount = 0;

    /// <summary>
    /// Stores the last logged MMB state to avoid spamming identical messages.
    /// </summary>
    private bool _lastLoggedMMBState = false;

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

        // CRITICAL: Update MMB state BEFORE HandleDragGestures()!
        // This fixes the "only works on second attempt" bug (Issue #243).
        // The bug was caused by HandleDragGestures() using stale _isMiddleMouseHeld
        // from the previous frame because it was updated after gesture processing.
        UpdateMiddleMouseState();

        // Handle RMB drag gestures for pump-action and reload
        HandleDragGestures();
    }

    /// <summary>
    /// Handles input events directly (event-based input).
    /// This is used as a fallback for MMB detection because Input.IsMouseButtonPressed()
    /// may not work reliably for middle mouse button in some cases (Godot issue #72507).
    /// </summary>
    public override void _Input(InputEvent @event)
    {
        base._Input(@event);

        // Track middle mouse button press/release via events
        if (@event is InputEventMouseButton mouseButton && mouseButton.ButtonIndex == MouseButton.Middle)
        {
            bool wasPressed = _isMiddleMouseHeldEvent;
            _isMiddleMouseHeldEvent = mouseButton.Pressed;

            if (PerFrameDragLogging && wasPressed != _isMiddleMouseHeldEvent)
            {
                LogToFile($"[Shotgun.EVENT] MMB event: pressed={_isMiddleMouseHeldEvent} (was {wasPressed}), isDragging={_isDragging}");
            }

            // If we're dragging and MMB was just pressed, immediately update tracking
            if (_isDragging && _isMiddleMouseHeldEvent)
            {
                _wasMiddleMouseHeldDuringDrag = true;
                LogToFile($"[Shotgun.EVENT] MMB pressed during drag - immediately setting _wasMMBDuringDrag=true");
            }
        }
    }

    /// <summary>
    /// Updates the middle mouse button state.
    /// MUST be called BEFORE HandleDragGestures() to fix timing issue.
    /// </summary>
    private void UpdateMiddleMouseState()
    {
        bool previousState = _isMiddleMouseHeld;
        _isMiddleMouseHeld = Input.IsMouseButtonPressed(MouseButton.Middle);

        // Log state changes for diagnostics
        if (_isDragging && PerFrameDragLogging && _isMiddleMouseHeld != previousState)
        {
            LogToFile($"[Shotgun.DIAG] UpdateMiddleMouseState: MMB state changed {previousState} -> {_isMiddleMouseHeld}");
        }
    }

    /// <summary>
    /// Updates the aim direction based on mouse position.
    /// TACTICAL RELOAD (Issue #437): During reload OR when RMB is held (dragging),
    /// aim direction is locked to allow the player to keep the weapon pointed at
    /// a specific spot (e.g., doorway) while performing RMB drag gestures to reload.
    /// This prevents the barrel from following the mouse during reload operations.
    ///
    /// FIX (Issue #437 feedback): Lock aim as soon as RMB is pressed, not just when
    /// reload state changes. This prevents barrel shift during quick one-motion
    /// reload gestures (drag up then down without releasing RMB).
    /// </summary>
    private void UpdateAimDirection()
    {
        // TACTICAL RELOAD (Issue #437): Don't update aim direction during reload
        // OR when dragging (RMB is held). This ensures the barrel freezes immediately
        // when RMB is pressed, before any state change occurs.
        // The aim direction is "locked" at the moment RMB is first pressed.
        if (ReloadState != ShotgunReloadState.NotReloading || _isDragging)
        {
            // Keep current _aimDirection locked - don't follow mouse
            // Sprite rotation is also not updated (stays pointing at locked direction)
            return;
        }

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
    /// Distance from screen edge (in pixels) at which cursor re-centering is triggered.
    /// Issue #445 v6-v7: When the mouse is within this distance of screen edge during pump action,
    /// the cursor is moved to screen center to allow proper gesture completion.
    /// </summary>
    private const float ScreenEdgeThreshold = 50.0f;

    /// <summary>
    /// Checks if cursor is near screen edge and re-centers it if needed for pump gestures.
    /// Issue #445 v6-v7 FIX: The original problem was that when looking UP, the mouse is at the
    /// screen top (Y≈0) and the user can't physically drag UP (negative Y) because there's
    /// no screen space above. Previous fixes (v2-v5) tried to change gesture direction logic,
    /// which broke the natural feel of the gestures.
    ///
    /// v6 solution: Keep screen-based gestures (like main branch - intuitive UP/DOWN) but
    /// detect when the mouse is at a screen edge during pump actions and automatically
    /// re-center the cursor to give the user room to perform the gesture.
    ///
    /// v7 addition: Also reset drag start position when firing while RMB is held, to enable
    /// continuous pump gestures (hold RMB, fire, pump, fire, pump, etc.).
    /// </summary>
    /// <returns>True if cursor was near edge and moved, false otherwise.</returns>
    private bool CheckAndRecenterCursorIfAtEdge()
    {
        // Only check during pump actions (not during reload or ready states)
        if (ActionState != ShotgunActionState.NeedsPumpUp && ActionState != ShotgunActionState.NeedsPumpDown)
        {
            return false;
        }

        Vector2 viewportSize = GetViewport().GetVisibleRect().Size;
        Vector2 mousePos = GetViewport().GetMousePosition();

        bool nearTopEdge = mousePos.Y < ScreenEdgeThreshold;
        bool nearBottomEdge = mousePos.Y > viewportSize.Y - ScreenEdgeThreshold;
        bool nearLeftEdge = mousePos.X < ScreenEdgeThreshold;
        bool nearRightEdge = mousePos.X > viewportSize.X - ScreenEdgeThreshold;

        // Check if we need to recenter based on current pump state and edge
        bool needsRecenter = false;

        if (ActionState == ShotgunActionState.NeedsPumpUp && nearTopEdge)
        {
            // User needs to drag UP but mouse is at top edge - can't drag up!
            needsRecenter = true;
            LogToFile($"[Shotgun.FIX#445v7] Mouse at top edge (Y={mousePos.Y:F0}), need PumpUp - recentering cursor");
        }
        else if (ActionState == ShotgunActionState.NeedsPumpDown && nearBottomEdge)
        {
            // User needs to drag DOWN but mouse is at bottom edge - can't drag down!
            needsRecenter = true;
            LogToFile($"[Shotgun.FIX#445v7] Mouse at bottom edge (Y={mousePos.Y:F0}), need PumpDown - recentering cursor");
        }

        if (needsRecenter)
        {
            // Move cursor to center of screen
            Vector2 centerPos = viewportSize / 2;
            GetViewport().WarpMouse(centerPos);

            // Update drag start position to the new center
            _dragStartPosition = GetGlobalMousePosition();

            LogToFile($"[Shotgun.FIX#445v7] Cursor recentered to ({centerPos.X:F0}, {centerPos.Y:F0})");
            return true;
        }

        return false;
    }

    /// <summary>
    /// Handles RMB drag gestures for pump-action cycling and reload.
    /// Pump: Drag UP = eject shell, Drag DOWN = chamber round
    /// Reload: Drag UP = open bolt, MMB hold + Drag DOWN = load shell, Drag DOWN (no MMB) = close bolt
    ///
    /// Supports continuous gestures: hold RMB, drag UP (open bolt), then without
    /// releasing RMB, drag DOWN (close bolt) - all in one continuous movement.
    ///
    /// Issue #243 Fix: Uses _wasMiddleMouseHeldDuringDrag to track if MMB was held
    /// at any point during the drag. This fixes timing issues where users release
    /// MMB and RMB simultaneously - the system remembers MMB was held during drag.
    ///
    /// Issue #445 Fix (v6-v7): Uses screen-based gestures (like main branch) for natural feel.
    /// When mouse is at screen edge and can't complete the gesture, the cursor is
    /// automatically re-centered to give room for the gesture. This preserves the
    /// intuitive "drag UP = eject, drag DOWN = chamber" behavior users expect.
    /// v7: Also resets drag start when firing while RMB is held for continuous pump gestures.
    /// </summary>
    private void HandleDragGestures()
    {
        // DIAGNOSTIC: Log raw input state at the very beginning of this method
        // This helps identify if the issue is in Input.IsMouseButtonPressed() itself
        bool rawMMBState = Input.IsMouseButtonPressed(MouseButton.Middle);
        bool rawRMBState = Input.IsMouseButtonPressed(MouseButton.Right);

        // Combine ALL MMB detection methods for maximum reliability (Issue #243 root cause investigation)
        // - _isMiddleMouseHeld: Updated in UpdateMiddleMouseState() via polling
        // - rawMMBState: Direct polling in this method
        // - _isMiddleMouseHeldEvent: Event-based tracking via _Input()
        // This redundancy helps diagnose which method is failing
        bool anyMMBDetected = _isMiddleMouseHeld || rawMMBState || _isMiddleMouseHeldEvent;

        // Check for RMB press (start drag)
        if (rawRMBState)
        {
            if (!_isDragging)
            {
                _dragStartPosition = GetGlobalMousePosition();
                _isDragging = true;
                _dragFrameCount = 0;
                _lastLoggedMMBState = anyMMBDetected;
                // Initialize _wasMiddleMouseHeldDuringDrag based on ANY MMB detection method
                // This handles the case where MMB is pressed at the exact same frame as RMB drag start
                _wasMiddleMouseHeldDuringDrag = anyMMBDetected;

                if (VerboseInputLogging)
                {
                    // Log both ReloadState AND ActionState for full context
                    // Issue #445: Also log drag start position and aim direction for diagnosis
                    LogToFile($"[Shotgun.FIX#243] RMB drag started - MMB: poll={_isMiddleMouseHeld}, raw={rawMMBState}, event={_isMiddleMouseHeldEvent}, any={anyMMBDetected}, ActionState={ActionState}, ReloadState={ReloadState}");
                    LogToFile($"[Shotgun.FIX#445] dragStartPos=({_dragStartPosition.X:F0}, {_dragStartPosition.Y:F0}), aimDir=({_aimDirection.X:F2}, {_aimDirection.Y:F2})");
                }
            }
            else
            {
                // Already dragging - increment frame counter
                _dragFrameCount++;

                // Per-frame diagnostic logging (only when state changes to reduce spam)
                if (PerFrameDragLogging && (anyMMBDetected != _lastLoggedMMBState || _dragFrameCount <= 3))
                {
                    LogToFile($"[Shotgun.DIAG] Frame {_dragFrameCount}: poll={_isMiddleMouseHeld}, raw={rawMMBState}, event={_isMiddleMouseHeldEvent}, any={anyMMBDetected}, wasMMB={_wasMiddleMouseHeldDuringDrag}");
                    _lastLoggedMMBState = anyMMBDetected;
                }

                // CRITICAL FIX (Issue #243 - second root cause): The MMB tracking MUST happen
                // BEFORE TryProcessMidDragGesture() is called. Previously, the tracking was done
                // AFTER the mid-drag processing, so when TryProcessMidDragGesture() checked
                // _wasMiddleMouseHeldDuringDrag, it was using stale data from before the user
                // pressed MMB during the drag.
                //
                // Bug sequence (before fix):
                // 1. User presses RMB (drag starts with MMB=false)
                // 2. User presses MMB while holding RMB
                // 3. TryProcessMidDragGesture() called - checks _wasMiddleMouseHeldDuringDrag (still false!)
                // 4. MMB tracking updates _wasMiddleMouseHeldDuringDrag = true (too late!)
                //
                // Fix: Update MMB tracking first, then call TryProcessMidDragGesture()
                //
                // ADDITIONAL FIX (Issue #243 - third attempt): Use combined detection from ALL methods:
                // - _isMiddleMouseHeld (polling-based)
                // - rawMMBState (direct polling)
                // - _isMiddleMouseHeldEvent (event-based via _Input)
                // This ensures MMB is detected regardless of which method works
                if (anyMMBDetected)
                {
                    if (!_wasMiddleMouseHeldDuringDrag && PerFrameDragLogging)
                    {
                        LogToFile($"[Shotgun.DIAG] Frame {_dragFrameCount}: MMB DETECTED via {(_isMiddleMouseHeld ? "poll" : (_isMiddleMouseHeldEvent ? "event" : "raw"))}! Setting _wasMMBDuringDrag=true");
                    }
                    _wasMiddleMouseHeldDuringDrag = true;
                }

                // Now check for mid-drag gesture completion
                // This enables continuous gestures without releasing RMB
                Vector2 currentPosition = GetGlobalMousePosition();
                Vector2 dragVector = currentPosition - _dragStartPosition;

                // Check if a vertical gesture has been completed mid-drag
                if (TryProcessMidDragGesture(dragVector))
                {
                    // Gesture processed - reset drag start for next gesture
                    _dragStartPosition = currentPosition;
                    // Reset MMB tracking for the new gesture segment
                    _wasMiddleMouseHeldDuringDrag = anyMMBDetected;
                    _dragFrameCount = 0;
                }
            }
        }
        else if (_isDragging)
        {
            // RMB released - evaluate the drag gesture
            Vector2 dragEnd = GetGlobalMousePosition();
            Vector2 dragVector = dragEnd - _dragStartPosition;
            _isDragging = false;

            if (VerboseInputLogging)
            {
                LogToFile($"[Shotgun.FIX#243] RMB released after {_dragFrameCount} frames - wasMMBDuringDrag={_wasMiddleMouseHeldDuringDrag}, current: poll={_isMiddleMouseHeld}, raw={rawMMBState}, event={_isMiddleMouseHeldEvent}");
            }

            ProcessDragGesture(dragVector);

            // Reset flags after processing
            _wasMiddleMouseHeldDuringDrag = false;
            _shellLoadedDuringMidDrag = false;  // Issue #266: Reset mid-drag shell load flag
            _dragFrameCount = 0;
        }
    }

    /// <summary>
    /// Attempts to process a gesture while RMB is still held (mid-drag).
    /// This enables continuous drag-and-drop: hold RMB, drag up, then drag down
    /// all in one fluid motion without releasing RMB.
    ///
    /// Note: In Loading state, mid-drag DOWN is NOT processed immediately.
    /// This gives users time to press MMB for shell loading before the gesture completes.
    /// The actual shell loading vs bolt close decision happens on RMB release.
    ///
    /// Issue #445 Fix (v6): Uses screen-based gestures (like main branch) for natural feel.
    /// - Drag UP (negative Y) = "Pump UP" (eject shell)
    /// - Drag DOWN (positive Y) = "Pump DOWN" (chamber round)
    /// When mouse is at screen edge and can't complete the gesture, the cursor is
    /// automatically re-centered to give room for the gesture.
    /// </summary>
    /// <param name="dragVector">Current drag vector from start position.</param>
    /// <returns>True if a gesture was processed, false otherwise.</returns>
    private bool TryProcessMidDragGesture(Vector2 dragVector)
    {
        // Issue #445 v6: Check if cursor needs to be re-centered due to screen edge
        // This is called before processing the gesture to give the user room to drag
        if (CheckAndRecenterCursorIfAtEdge())
        {
            // Cursor was recentered, drag start position was updated
            // Return false to wait for the user to make the actual gesture
            return false;
        }

        // Check if drag is long enough for a gesture
        if (dragVector.Length() < MinDragDistance)
        {
            return false;
        }

        // Determine if drag is primarily vertical (screen-based)
        bool isVerticalDrag = Mathf.Abs(dragVector.Y) > Mathf.Abs(dragVector.X);
        if (!isVerticalDrag)
        {
            return false; // Only vertical drags are used for shotgun
        }

        bool isDragUp = dragVector.Y < 0;  // Screen-UP (negative Y)
        bool isDragDown = dragVector.Y > 0;  // Screen-DOWN (positive Y)

        // Issue #445 v6: Log for diagnostics
        if (_dragFrameCount % 10 == 0 && VerboseInputLogging)
        {
            LogToFile($"[Shotgun.FIX#445v7] TryProcessMidDragGesture - dragVector=({dragVector.X:F1}, {dragVector.Y:F1}), length={dragVector.Length():F1}, isDragUp={isDragUp}, isDragDown={isDragDown}, ActionState={ActionState}");
        }

        // Determine which gesture would be valid based on current state
        bool gestureProcessed = false;

        // For pump-action cycling - use SCREEN-BASED gestures (Issue #445 v6 - like main branch)
        if (ReloadState == ShotgunReloadState.NotReloading)
        {
            switch (ActionState)
            {
                case ShotgunActionState.NeedsPumpUp:
                    if (isDragUp)
                    {
                        // Mid-drag pump up - eject shell (screen-UP)
                        ActionState = ShotgunActionState.NeedsPumpDown;
                        PlayPumpUpSound();

                        // Spawn casing when pump is pulled back (Issue #285)
                        SpawnCasing(_lastFireDirection, WeaponData?.Caliber);

                        EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                        EmitSignal(SignalName.PumpActionCycled, "up");
                        LogToFile("[Shotgun.FIX#445v7] Mid-drag pump UP - shell ejected, continue dragging DOWN to chamber");
                        gestureProcessed = true;
                    }
                    break;

                case ShotgunActionState.NeedsPumpDown:
                    if (isDragDown)
                    {
                        // Issue #243 (fourth root cause fix): Check for MMB held during mid-drag.
                        // If MMB is held, user wants to load a shell instead of just chambering.
                        bool shouldLoadShellMidDrag = _wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld || _isMiddleMouseHeldEvent;

                        if (shouldLoadShellMidDrag && ShellsInTube < TubeMagazineCapacity)
                        {
                            LogToFile($"[Shotgun.FIX#266] Mid-drag MMB+DOWN during pump cycle: transitioning to reload mode");

                            _lastBoltCloseTime = Time.GetTicksMsec() / 1000.0;

                            // Transition to Loading state (skip the Ready state)
                            // NOTE: Don't play action open sound here - the bolt is already open
                            // from the pump UP action. Playing open sound here was causing
                            // confusion (Issue #266).
                            ReloadState = ShotgunReloadState.Loading;
                            ActionState = ShotgunActionState.Ready;
                            EmitSignal(SignalName.ReloadStateChanged, (int)ReloadState);
                            EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                            EmitSignal(SignalName.ReloadStarted);
                            LogToFile("[Shotgun.FIX#266] Transitioned to Loading state (bolt already open from pump UP)");

                            // Load a shell
                            LoadShell();
                            // Mark that we loaded a shell during mid-drag (Issue #266 fix)
                            _shellLoadedDuringMidDrag = true;

                            LogToFile($"[Shotgun.FIX#266] Mid-drag shell loaded during pump cycle - staying in Loading state");
                            gestureProcessed = true;
                            break;
                        }

                        // Normal mid-drag pump down - chamber round
                        // Record close time for cooldown protection
                        _lastBoltCloseTime = Time.GetTicksMsec() / 1000.0;

                        if (ShellsInTube > 0)
                        {
                            ActionState = ShotgunActionState.Ready;
                            PlayPumpDownSound();
                            EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                            EmitSignal(SignalName.PumpActionCycled, "down");
                            LogToFile($"[Shotgun.FIX#445v7] Mid-drag pump DOWN - chambered, ready to fire");
                        }
                        else
                        {
                            ActionState = ShotgunActionState.Ready;
                            PlayPumpDownSound();
                            EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                            LogToFile($"[Shotgun.FIX#445v7] Mid-drag pump DOWN - tube empty, need to reload");
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

                        // Issue #477 v3 FIX: Skip cooldown check for mid-drag bolt cycling.
                        // The cooldown was added to prevent ACCIDENTAL reopening from mouse
                        // movement after RMB release. But during continuous mid-drag cycling,
                        // the user is deliberately dragging UP to reopen - this is intentional.
                        // We use a shorter cooldown (100ms) for mid-drag to allow rapid cycling
                        // while still preventing physics glitches from too-rapid state changes.
                        const float MidDragCooldownSeconds = 0.1f;
                        bool inMidDragCooldown = timeSinceClose < MidDragCooldownSeconds;

                        if (VerboseInputLogging)
                        {
                            GD.Print($"[Shotgun.FIX#477v3] Mid-drag UP (open bolt) in Ready state: elapsed={timeSinceClose:F3}s, midDragCooldown={MidDragCooldownSeconds}s, inCooldown={inMidDragCooldown}");
                        }

                        if (!inMidDragCooldown)
                        {
                            // Mid-drag start reload - uses shorter cooldown for responsive cycling
                            StartReload();
                            gestureProcessed = true;
                        }
                        else if (VerboseInputLogging)
                        {
                            GD.Print($"[Shotgun.Input] Mid-drag bolt open BLOCKED by cooldown ({timeSinceClose:F3}s < {MidDragCooldownSeconds}s)");
                        }
                    }
                    break;
            }
        }
        else
        {
            // For reload sequence - use SCREEN-BASED gestures (vertical drags)
            switch (ReloadState)
            {
                case ShotgunReloadState.WaitingToOpen:
                    if (isDragUp)
                    {
                        // Mid-drag open bolt
                        ReloadState = ShotgunReloadState.Loading;
                        PlayActionOpenSound();
                        EmitSignal(SignalName.ReloadStateChanged, (int)ReloadState);
                        GD.Print("[Shotgun] Mid-drag bolt opened - use MMB drag DOWN to load shells, then RMB drag DOWN to close");
                        gestureProcessed = true;
                    }
                    break;

                case ShotgunReloadState.Loading:
                    if (isDragDown)
                    {
                        // Issue #477 v3 FIX: Allow mid-drag bolt closing when MMB is NOT held.
                        // This enables continuous bolt cycling (open-close-open-close) during
                        // a single RMB drag, which users expect for tactical reloading.
                        //
                        // Original #243 fix: Waited for RMB release to give user time to press MMB.
                        // New approach: Check MMB NOW and close if not held, otherwise wait.
                        bool shouldLoadShell = _wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld || _isMiddleMouseHeldEvent;

                        if (VerboseInputLogging)
                        {
                            LogToFile($"[Shotgun.FIX#477v3] Mid-drag DOWN in Loading state: shouldLoad={shouldLoadShell}");
                        }

                        if (!shouldLoadShell)
                        {
                            // User NOT holding MMB - they want to close the bolt
                            CompleteReload();
                            gestureProcessed = true;
                            LogToFile("[Shotgun.FIX#477v3] Mid-drag bolt closed (MMB not held)");
                        }
                        else
                        {
                            // User IS holding MMB - they want to load a shell
                            // Wait for RMB release to confirm (original #243 behavior)
                            LogToFile("[Shotgun.FIX#477v3] Mid-drag DOWN with MMB - waiting for RMB release to load shell");
                            return false;
                        }
                    }
                    // Note: isDragUp in Loading state is handled after CompleteReload()
                    // changes state to NotReloading/Ready, which is processed in the
                    // ShotgunActionState.Ready case above.
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
    ///
    /// Issue #445 Fix (v6): Uses screen-based gestures (like main branch) for pump actions.
    /// - Drag UP (negative Y) = eject shell
    /// - Drag DOWN (positive Y) = chamber round
    /// Mouse cursor is re-centered when at screen edge to allow gesture completion.
    /// </summary>
    private void ProcessDragGesture(Vector2 dragVector)
    {
        // Issue #445 v6: Log the final drag vector when RMB is released
        if (VerboseInputLogging)
        {
            LogToFile($"[Shotgun.FIX#445v7] ProcessDragGesture - dragVector=({dragVector.X:F1}, {dragVector.Y:F1}), length={dragVector.Length():F1}, ActionState={ActionState}");
        }

        // Check if drag is long enough
        if (dragVector.Length() < MinDragDistance)
        {
            if (VerboseInputLogging)
            {
                LogToFile($"[Shotgun.FIX#445v7] Drag too short: {dragVector.Length():F1} < {MinDragDistance}");
            }
            return;
        }

        // Determine if drag is primarily vertical (screen-based)
        bool isVerticalDrag = Mathf.Abs(dragVector.Y) > Mathf.Abs(dragVector.X);
        bool isDragUp = dragVector.Y < 0;  // Screen-UP (negative Y)
        bool isDragDown = dragVector.Y > 0;  // Screen-DOWN (positive Y)

        // Handle based on current state (reload takes priority)
        if (ReloadState != ShotgunReloadState.NotReloading)
        {
            // For reload, use screen-based vertical detection
            if (!isVerticalDrag)
            {
                if (VerboseInputLogging)
                {
                    LogToFile($"[Shotgun.FIX#477v2] Reload drag not vertical: absY={Mathf.Abs(dragVector.Y):F1} <= absX={Mathf.Abs(dragVector.X):F1}");
                }

                // Issue #477 Fix: When drag is not vertical enough while in Loading state,
                // close the bolt anyway if the user is not holding MMB.
                // This prevents the bolt from getting stuck in Loading state when the user
                // tries to close it but drags slightly diagonally.
                if (ReloadState == ShotgunReloadState.Loading)
                {
                    bool shouldLoadShell = _wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld;
                    if (!shouldLoadShell)
                    {
                        LogToFile($"[Shotgun.FIX#477v2] Non-vertical drag in Loading state without MMB - closing bolt");
                        CompleteReload();
                    }
                    else
                    {
                        LogToFile($"[Shotgun.FIX#477v2] Non-vertical drag in Loading state WITH MMB - staying in Loading state");
                    }
                }
                return;
            }

            ProcessReloadGesture(isDragUp, isDragDown);
        }
        else
        {
            // For pump actions, use SCREEN-BASED gesture detection (Issue #445 v6 - like main branch)
            if (!isVerticalDrag)
            {
                if (VerboseInputLogging)
                {
                    LogToFile($"[Shotgun.FIX#445v7] Pump drag not vertical: absY={Mathf.Abs(dragVector.Y):F1} <= absX={Mathf.Abs(dragVector.X):F1}");
                }
                return;
            }

            if (VerboseInputLogging)
            {
                LogToFile($"[Shotgun.FIX#445v7] Screen-based pump gesture: isDragUp={isDragUp}, isDragDown={isDragDown}");
            }

            ProcessPumpActionGesture(isDragUp, isDragDown);
        }
    }

    /// <summary>
    /// Processes drag gesture for pump-action cycling.
    /// After firing: Drag UP (eject shell) → Drag DOWN (chamber)
    ///
    /// Issue #445 Fix (v6): Uses screen-based gestures (like main branch).
    /// - isPumpUp = screen-UP drag (negative Y) = eject shell
    /// - isPumpDown = screen-DOWN drag (positive Y) = chamber round
    /// When mouse is at screen edge, cursor is re-centered to allow gesture.
    ///
    /// Issue #243 (fourth root cause): When user holds MMB during pump cycle,
    /// they want to load a shell, not just chamber the next round. The fix adds
    /// MMB detection during NeedsPumpDown state to transition to reload mode.
    /// </summary>
    private void ProcessPumpActionGesture(bool isPumpUp, bool isPumpDown)
    {
        // Check for MMB held during drag (for shell loading during pump cycle)
        bool shouldLoadShell = _wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld;

        switch (ActionState)
        {
            case ShotgunActionState.NeedsPumpUp:
                if (isPumpUp)
                {
                    // Eject spent shell (screen-UP drag)
                    // Issue #445v6: Screen-based gestures like main branch
                    ActionState = ShotgunActionState.NeedsPumpDown;
                    PlayPumpUpSound();

                    // Spawn casing when pump is pulled back (Issue #285)
                    SpawnCasing(_lastFireDirection, WeaponData?.Caliber);

                    EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                    EmitSignal(SignalName.PumpActionCycled, "up");
                    LogToFile("[Shotgun.FIX#445v7] Pump UP - shell ejected, now drag DOWN to chamber");
                }
                break;

            case ShotgunActionState.NeedsPumpDown:
                if (isPumpDown)
                {
                    // Issue #243 (fourth root cause fix): Check for MMB held.
                    // If MMB is held, user wants to load a shell instead of just chambering.
                    // Transition to reload mode and load shell.
                    if (shouldLoadShell && ShellsInTube < TubeMagazineCapacity)
                    {
                        LogToFile($"[Shotgun.FIX#266] MMB+AWAY during pump cycle: transitioning to reload mode (wasMMBDuringDrag={_wasMiddleMouseHeldDuringDrag}, isMMBHeld={_isMiddleMouseHeld})");

                        _lastBoltCloseTime = Time.GetTicksMsec() / 1000.0;

                        // Transition to Loading state (skip the Ready state)
                        // NOTE: Don't play action open sound here - the bolt is already open
                        // from the pump UP action. Playing open sound here was causing
                        // confusion (Issue #266).
                        ReloadState = ShotgunReloadState.Loading;
                        ActionState = ShotgunActionState.Ready;
                        // PlayActionOpenSound(); // REMOVED: Bolt is already open from pump UP
                        EmitSignal(SignalName.ReloadStateChanged, (int)ReloadState);
                        EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                        EmitSignal(SignalName.ReloadStarted);
                        LogToFile("[Shotgun.FIX#266] Transitioned to Loading state (bolt already open from pump)");

                        // Load a shell
                        LoadShell();
                        // Mark that we loaded a shell during mid-drag (Issue #266 fix)
                        _shellLoadedDuringMidDrag = true;

                        // Stay in Loading state for more shells
                        LogToFile($"[Shotgun.FIX#266] Shell loaded during pump cycle - still in Loading state for more shells");
                        return;
                    }

                    // Normal pump down - chamber next round (screen-DOWN drag)
                    // Issue #445v6: Screen-based gestures like main branch
                    // Record close time for cooldown protection
                    _lastBoltCloseTime = Time.GetTicksMsec() / 1000.0;

                    if (ShellsInTube > 0)
                    {
                        ActionState = ShotgunActionState.Ready;
                        PlayPumpDownSound();
                        EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                        EmitSignal(SignalName.PumpActionCycled, "down");
                        LogToFile($"[Shotgun.FIX#445v7] Pump DOWN - chambered, ready to fire");
                    }
                    else
                    {
                        // No shells in tube - go to ready state to allow reload
                        ActionState = ShotgunActionState.Ready;
                        PlayPumpDownSound();
                        EmitSignal(SignalName.ActionStateChanged, (int)ActionState);
                        LogToFile($"[Shotgun.FIX#445v7] Pump DOWN - tube empty, need to reload");
                    }
                }
                break;

            case ShotgunActionState.Ready:
                // If ready and drag UP, might be starting reload (open bolt)
                // Check cooldown to prevent accidental bolt reopening after close
                if (isPumpUp && ShellsInTube < TubeMagazineCapacity)
                {
                    if (!IsInBoltCloseCooldown())
                    {
                        StartReload();
                    }
                    else if (VerboseInputLogging)
                    {
                        LogToFile("[Shotgun.FIX#445v7] Bolt open BLOCKED by cooldown");
                    }
                }
                break;
        }
    }

    /// <summary>
    /// Processes drag gesture for reload sequence.
    /// Reload: RMB drag up (open bolt) → [MMB hold + RMB drag down]×N (load shells) → RMB drag down (close bolt)
    ///
    /// Issue #243 Fix: Uses _wasMiddleMouseHeldDuringDrag to track if MMB was held
    /// during the drag gesture. This ensures shell loading works even if user
    /// releases MMB and RMB at the same time (common timing issue).
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
                    // Use _wasMiddleMouseHeldDuringDrag instead of just _isMiddleMouseHeld
                    // This fixes the timing issue where users release MMB and RMB simultaneously
                    bool shouldLoadShell = _wasMiddleMouseHeldDuringDrag || _isMiddleMouseHeld;

                    if (VerboseInputLogging)
                    {
                        LogToFile($"[Shotgun.FIX#477] RMB release in Loading state: wasMMBDuringDrag={_wasMiddleMouseHeldDuringDrag}, isMMBHeld={_isMiddleMouseHeld}, shellLoadedMidDrag={_shellLoadedDuringMidDrag} => shouldLoadShell={shouldLoadShell}");
                    }

                    // Issue #477 Fix: Check MMB FIRST, then check for mid-drag duplicate.
                    // Previously, the duplicate check was first, which caused bolt closing to be
                    // blocked after loading a shell mid-drag during pump cycle.
                    // The user wants to CLOSE bolt if MMB is not held, regardless of whether
                    // a shell was loaded mid-drag.
                    if (!shouldLoadShell)
                    {
                        // Close bolt without MMB - finish reload
                        LogToFile("[Shotgun.FIX#477] Closing bolt (MMB was not held)");
                        CompleteReload();
                    }
                    else if (_shellLoadedDuringMidDrag)
                    {
                        // Issue #266 Fix: Skip loading another shell if one was already loaded mid-drag.
                        // This prevents multiple shells loading in one drag motion.
                        // Stay in Loading state for more shells (user can do another drag).
                        LogToFile($"[Shotgun.FIX#477] RMB release in Loading state: shell already loaded mid-drag, skipping duplicate load (user can drag again to load more)");
                    }
                    else
                    {
                        // Load a shell (MMB + RMB drag down)
                        LogToFile("[Shotgun.FIX#477] Loading shell (MMB was held during drag)");
                        LoadShell();
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
            LogToFile("[Shotgun.FIX#243] StartReload skipped - already reloading");
            return; // Already reloading
        }

        if (ShellsInTube >= TubeMagazineCapacity)
        {
            LogToFile("[Shotgun.FIX#243] StartReload skipped - tube is already full");
            return; // Tube is full
        }

        // Open bolt directly - the RMB drag UP that triggered this already counts as "open bolt"
        ReloadState = ShotgunReloadState.Loading;
        PlayActionOpenSound();
        EmitSignal(SignalName.ReloadStateChanged, (int)ReloadState);
        EmitSignal(SignalName.ReloadStarted);
        LogToFile($"[Shotgun.FIX#243] Bolt opened for loading - ReloadState=Loading, ShellsInTube={ShellsInTube}/{TubeMagazineCapacity}");
    }

    /// <summary>
    /// Loads a single shell into the tube magazine.
    /// In tutorial mode, shells are infinite (no reserve ammo required).
    /// </summary>
    private void LoadShell()
    {
        LogToFile($"[Shotgun.FIX#243] LoadShell called - ReloadState={ReloadState}, ShellsInTube={ShellsInTube}/{TubeMagazineCapacity}, Tutorial={_isTutorialLevel}, ReserveAmmo={ReserveAmmo}");

        if (ReloadState != ShotgunReloadState.Loading)
        {
            LogToFile("[Shotgun.FIX#243] LoadShell SKIPPED - not in Loading state!");
            return;
        }

        if (ShellsInTube >= TubeMagazineCapacity)
        {
            LogToFile("[Shotgun.FIX#243] LoadShell SKIPPED - tube is full");
            return;
        }

        // In tutorial mode, allow infinite shell loading without reserve ammo
        if (!_isTutorialLevel && ReserveAmmo <= 0)
        {
            LogToFile("[Shotgun.FIX#243] LoadShell SKIPPED - no reserve shells (not tutorial mode)");
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
        LogToFile($"[Shotgun.FIX#243] Shell LOADED - {ShellsInTube}/{TubeMagazineCapacity} shells in tube");
    }

    /// <summary>
    /// Completes the reload sequence by closing the action.
    /// Records the close time to enable cooldown protection against accidental reopening.
    /// </summary>
    private void CompleteReload()
    {
        if (ReloadState == ShotgunReloadState.NotReloading)
        {
            LogToFile("[Shotgun.FIX#243] CompleteReload skipped - not reloading");
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
        LogToFile($"[Shotgun.FIX#243] Reload complete - bolt closed, ready to fire with {ShellsInTube} shells");
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
    ///
    /// Issue #445 v7 FIX: When firing while RMB is held (continuous drag), reset the
    /// drag start position so subsequent pump gestures are calculated correctly.
    /// Without this, the accumulated dragVector from before firing would be used,
    /// causing gesture direction mismatches.
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

        // Store fire direction for casing ejection after pump up
        _lastFireDirection = fireDirection;

        // Determine number of pellets (random between min and max)
        int pelletCount = GD.RandRange(MinPellets, MaxPellets);

        // Get spread angle from weapon data
        float spreadAngle = WeaponData.SpreadAngle;
        float spreadRadians = Mathf.DegToRad(spreadAngle);
        float halfSpread = spreadRadians / 2.0f;

        LogToFile($"[Shotgun.FIX#212] Firing {pelletCount} pellets with {spreadAngle}° spread at pos={GlobalPosition}");

        // Fire all pellets simultaneously with spatial distribution (cloud effect)
        FirePelletsAsCloud(fireDirection, pelletCount, spreadRadians, halfSpread, projectileScene);

        // NOTE: Casing is NOT spawned here for shotgun - it's ejected during pump up action
        // (see ProcessPumpActionGesture() case ShotgunActionState.NeedsPumpUp)

        // Consume shell from tube
        ShellsInTube--;
        EmitSignal(SignalName.ShellCountChanged, ShellsInTube, TubeMagazineCapacity);

        // Set action state - needs manual pump cycling (UP first to eject shell)
        ActionState = ShotgunActionState.NeedsPumpUp;
        EmitSignal(SignalName.ActionStateChanged, (int)ActionState);

        // Issue #445 v7 FIX: Reset drag start position when firing while RMB is held.
        // This enables continuous pump gestures: user can hold RMB, fire with LMB,
        // then drag UP-DOWN to pump, fire again, etc. without releasing RMB.
        // Without this reset, the accumulated dragVector from before firing would
        // cause gesture direction mismatches (e.g., user drags UP but system sees DOWN).
        if (_isDragging)
        {
            _dragStartPosition = GetGlobalMousePosition();
            LogToFile("[Shotgun.FIX#445v7] Reset drag start position after firing (continuous pump mode)");
        }

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
    ///
    /// Issue #212 Fix (v3): Pass pellet index and total count to SpawnPelletWithOffset
    /// so that point-blank pellets can be distributed evenly across the lateral spread
    /// instead of relying on random offsets that might cluster.
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
            SpawnPelletWithOffset(pelletDirection, spawnOffset, projectileScene, i, pelletCount);
        }
    }

    /// <summary>
    /// Enable verbose logging for pellet spawn diagnostics.
    /// Set to true to debug pellet grouping issues.
    /// Issue #212: Temporarily enabled to help diagnose pellet clustering reports.
    /// </summary>
    private const bool VerbosePelletLogging = true;

    /// <summary>
    /// Spawns a pellet projectile with a spatial offset along its direction.
    /// The offset creates the cloud effect where pellets appear at different depths.
    ///
    /// When firing at point-blank (wall detected), uses a combination of:
    /// 1. Minimum forward offset to ensure pellets travel some distance
    /// 2. Lateral (perpendicular) offset to create visual spread even at close range
    /// This prevents all pellets from appearing as "one large pellet".
    ///
    /// Issue #212 Fix (v3): Uses pellet index for deterministic lateral distribution
    /// at point-blank range, ensuring even spread regardless of random offset clustering.
    /// </summary>
    /// <param name="direction">Direction for the pellet to travel.</param>
    /// <param name="extraOffset">Random offset along the direction for cloud effect.</param>
    /// <param name="projectileScene">Scene to instantiate.</param>
    /// <param name="pelletIndex">Index of this pellet (0 to pelletCount-1).</param>
    /// <param name="pelletCount">Total number of pellets being fired.</param>
    private void SpawnPelletWithOffset(Vector2 direction, float extraOffset, PackedScene projectileScene, int pelletIndex, int pelletCount)
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
            // Wall detected at point-blank range
            //
            // Issue #212: At close range, angular spread produces insufficient visual separation.
            // With 15° spread at 10px: only ~1.3px separation (imperceptible).
            //
            // Solution: Add explicit lateral offset perpendicular to fire direction.
            // This ensures pellets spread out visually even at point-blank range.
            //
            // FIX v2 (2026-01-22): Previous fix used Mathf.Max(0, extraOffset) which
            // caused all pellets with negative extraOffset to spawn at exactly the same
            // position (minSpawnOffset). Now we use the full extraOffset range.
            //
            // FIX v3 (2026-01-23): Random extraOffset can still cluster due to RNG.
            // Now use pellet index for DETERMINISTIC lateral distribution, ensuring
            // pellets are always evenly spread across the lateral range.
            // Random extraOffset is still used for forward variation (depth).

            float minSpawnOffset = 15.0f;  // Minimum forward distance from player

            // Calculate perpendicular direction for lateral spread
            Vector2 perpendicular = new Vector2(-direction.Y, direction.X);

            // FIX v3: Use pellet INDEX for deterministic lateral distribution
            // This ensures pellets are always evenly spread across the lateral range
            // regardless of random offset values which might cluster.
            //
            // Lateral range: ±15px (total 30px spread for all pellets)
            // Formula: progress from -1 to +1, then scale by 15px
            float lateralProgress = pelletCount > 1
                ? ((float)pelletIndex / (pelletCount - 1)) * 2.0f - 1.0f  // -1 to +1
                : 0.0f;  // Single pellet goes straight
            float lateralOffset = lateralProgress * 15.0f;  // ±15px lateral spread

            // Add small random jitter (±2px) to prevent perfectly uniform look
            lateralOffset += (float)GD.RandRange(-2.0, 2.0);

            // Forward offset uses absolute value of extraOffset to vary depth
            // This creates the cloud effect (some pellets ahead, some behind)
            float forwardVariation = Mathf.Abs(extraOffset) * 0.3f;  // 0-4.5px extra forward

            spawnPosition = GlobalPosition
                + direction * (minSpawnOffset + forwardVariation)
                + perpendicular * lateralOffset;

            if (VerbosePelletLogging)
            {
                LogToFile($"[Shotgun.FIX#212] Point-blank pellet {pelletIndex + 1}/{pelletCount}: " +
                         $"forward={minSpawnOffset + forwardVariation:F1}px, lateral={lateralOffset:F1}px, " +
                         $"pos={spawnPosition}");
            }
        }
        else
        {
            // Normal case: spawn at offset position plus extra cloud offset
            spawnPosition = GlobalPosition + direction * (BulletSpawnOffset + extraOffset);

            if (VerbosePelletLogging)
            {
                LogToFile($"[Shotgun.FIX#212] Normal pellet {pelletIndex + 1}/{pelletCount}: " +
                         $"extraOffset={extraOffset:F1}, distance={BulletSpawnOffset + extraOffset:F1}px, " +
                         $"pos={spawnPosition}");
            }
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
    /// Gets whether a drag gesture is currently in progress (RMB is held).
    /// TACTICAL RELOAD (Issue #437): Used to lock aim direction as soon as RMB is pressed,
    /// before any state changes occur. This prevents the barrel from shifting during
    /// quick one-motion reload gestures (drag up then down without releasing RMB).
    /// </summary>
    public bool IsDragging => _isDragging;

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
                    ShotgunReloadState.Loading => "MMB + RMB down to load, RMB down to close",
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

    #region Logging

    /// <summary>
    /// Logs a message to the FileLogger (GDScript autoload) for debugging.
    /// This ensures diagnostic messages appear in the user's log file.
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
