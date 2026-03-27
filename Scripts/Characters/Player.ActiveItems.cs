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
/// Player partial class: Active item methods (flashlight, teleport bracers, homing bullets,
/// BFF pendant, invisibility suit, trajectory glasses, breaker/drilling bullets, combat disposition,
/// force field, auto-reload, breaching charges, armored skin, loudspeaker, recoil compensator,
/// experimental sample, fine motor skills, debug trajectory visualization, and logging).
/// Extracted from Player.cs to improve maintainability (Issue #1265).
/// </summary>
public partial class Player
{
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

        // Issue #1036 / #1115: Block active item use when jammed by a Radio Jammer enemy,
        // and cancel the flashlight immediately if it is on when the player enters jammer range.
        // Use silent check (hold action fires every frame — verbose would flood the log)
        if (IsActiveItemJammedSilent())
        {
            if (_flashlightHasScript)
            {
                _flashlightNode.Call("turn_off");
            }
            else if (_flashlightIsOn)
            {
                _flashlightIsOn = false;
                if (_flashlightPointLight != null)
                {
                    _flashlightPointLight.Visible = false;
                    _flashlightPointLight.Energy = 0.0f;
                }
            }
            if (Input.IsActionJustPressed("flashlight_toggle"))
                LogToFile("[Player.Flashlight] Space blocked by Radio Jammer (Issue #1036)");
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

        // Draw initial charge progress bar (Issue #700)
        QueueRedraw();
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

        // Experimental Sample is managing the teleport aim phase — skip normal input handling
        if (_teleportExperimentalActive)
        {
            // Still update target position so the reticle tracks the cursor
            if (_teleportAiming)
            {
                _teleportTargetPosition = GetSafeTeleportPosition(GlobalPosition, GetGlobalMousePosition());
                QueueRedraw();
            }
            return;
        }

        if (Input.IsActionPressed("flashlight_toggle"))
        {
            // Issue #1036: Block active item use when jammed by a Radio Jammer enemy
            // Use silent check (hold action fires every frame — verbose would flood the log)
            if (IsActiveItemJammedSilent())
            {
                return;
            }

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

        // Issue #723: Reset enemy memory when player teleports - enemies lose track and enter search mode
        ResetAllEnemyMemories("teleport");

        QueueRedraw();
    }

    /// <summary>
    /// Reset memory for all enemies in the scene (Issue #723).
    /// Called when player teleports or becomes invisible, causing enemies to lose track and enter search mode.
    /// </summary>
    /// <param name="reason">The reason for the memory reset (for logging purposes).</param>
    private void ResetAllEnemyMemories(string reason = "teleport")
    {
        var enemies = GetTree().GetNodesInGroup("enemies");
        int resetCount = 0;

        foreach (var node in enemies)
        {
            if (node.HasMethod("reset_memory"))
            {
                node.Call("reset_memory");
                resetCount++;
            }
        }

        if (resetCount > 0)
        {
            LogToFile($"[Player] Reset memory for {resetCount} enemies ({reason} - Issue #723)");
        }
    }

    /// <summary>
    /// Find a safe teleport destination that doesn't place the player inside walls.
    /// The reticle should "skip through" walls — if the cursor is past a wall,
    /// the teleport lands on the far side of the wall, not before it.
    /// Uses multiple raycasts to find clear space beyond obstacles.
    /// The result is always clamped to the navigation mesh to prevent teleporting
    /// outside the map boundary walls (Issue #939).
    /// </summary>
    /// <param name="fromPos">The player's current position.</param>
    /// <param name="cursorPos">The mouse cursor position (intended target).</param>
    /// <returns>A safe teleport destination position within the map bounds.</returns>
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

        Vector2 candidatePos;
        if (directResult.Count == 0)
        {
            // No wall in the way — check if cursor position itself is inside a wall
            candidatePos = EnsureNotInsideWall(spaceState, cursorPos);
        }
        else
        {
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
            candidatePos = fromPos + direction * Mathf.Max(wallDistance - PlayerCollisionRadius - 2.0f, 0.0f);

            for (float dist = probeStart; dist <= totalDistance + step; dist += step)
            {
                float clampedDist = Mathf.Min(dist, totalDistance);
                Vector2 testPos = fromPos + direction * clampedDist;

                // Check if this position is inside a wall using shape query
                if (!IsPositionInsideWall(spaceState, testPos))
                {
                    // Found clear space beyond the wall — verify we can raycast from there
                    // back to the cursor (no additional walls in between)
                    candidatePos = testPos;

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

                    candidatePos = lastGoodPos;
                    break;
                }
            }
        }

        // Clamp the final position to the navigation mesh to prevent teleporting
        // outside the map boundary walls (Issue #939).
        return ClampToNavigationMesh(candidatePos);
    }

    /// <summary>
    /// Clamp a position to the navigation mesh so the player cannot teleport
    /// outside the solid boundary walls surrounding the map (Issue #939).
    /// Uses NavigationServer2D to find the closest valid point on the nav mesh.
    /// </summary>
    /// <param name="position">The candidate teleport position.</param>
    /// <returns>The closest valid position within the navigation mesh.</returns>
    private Vector2 ClampToNavigationMesh(Vector2 position)
    {
        var navMap = GetWorld2D().NavigationMap;
        if (!navMap.IsValid)
        {
            LogToFile("[Player.TeleportBracers] Warning: Could not get NavigationMap for boundary check");
            return position;
        }

        Vector2 closest = NavigationServer2D.MapGetClosestPoint(navMap, position);
        if (!closest.IsEqualApprox(position))
        {
            LogToFile($"[Player.TeleportBracers] Clamped teleport from {position} to {closest} (outside map bounds)");
        }
        return closest;
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

    #region Homing Bullets Methods (Issue #677)

    /// <summary>
    /// Initialize the homing bullets if the ActiveItemManager has them selected.
    /// </summary>
    private void InitHomingBullets()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.Homing] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_homing_bullets"))
        {
            LogToFile("[Player.Homing] ActiveItemManager missing has_homing_bullets method");
            return;
        }

        bool hasHomingBullets = (bool)activeItemManager.Call("has_homing_bullets");
        if (!hasHomingBullets)
        {
            LogToFile("[Player.Homing] No homing bullets selected in ActiveItemManager");
            return;
        }

        _homingBulletsEquipped = true;
        _homingCharges = MaxHomingCharges;
        _homingActive = false;
        _homingTimer = 0.0f;
        SetupHomingAudio();

        LogToFile($"[Player.Homing] Homing bullets equipped, charges: {_homingCharges}/{MaxHomingCharges}");
    }

    /// <summary>
    /// Handle homing bullets input: press Space to activate for 1 second.
    /// When activated, all bullets fired during the activation window steer toward enemies.
    /// Also enables homing on already-airborne player bullets.
    /// </summary>
    private void HandleHomingBulletsInput(float delta)
    {
        if (!_homingBulletsEquipped)
        {
            return;
        }

        // Issue #1115: Cancel homing effect immediately if player enters jammer range while active
        if (_homingActive && IsActiveItemJammedSilent())
        {
            _homingActive = false;
            _homingTimer = 0.0f;
            StopHomingScanner();
            _homingBarVisible = false;
            _homingChargeBarPending = true;
            _homingChargeBarHideTimer = HomingChargeBarHideDelay;
            QueueRedraw();
            EmitSignal(SignalName.HomingDeactivated);
            LogToFile("[Player.Homing] Homing cancelled by Radio Jammer (Issue #1115)");
        }

        // Handle active timer countdown
        if (_homingActive)
        {
            _homingTimer -= delta;
            if (_homingTimer <= 0.0f)
            {
                _homingActive = false;
                _homingTimer = 0.0f;
                StopHomingScanner();
                // Show charge bar briefly after deactivation, then hide (Issue #974)
                _homingBarVisible = false;
                _homingChargeBarPending = true;
                _homingChargeBarHideTimer = HomingChargeBarHideDelay;
                QueueRedraw();
                EmitSignal(SignalName.HomingDeactivated);
                LogToFile($"[Player.Homing] Homing effect expired, charges remaining: {_homingCharges}/{MaxHomingCharges}");
            }
        }

        // Activate on Space press (only if not already active and has charges)
        if (Input.IsActionJustPressed("flashlight_toggle"))
        {
            // Issue #1036: Block active item use when jammed by a Radio Jammer enemy
            if (IsActiveItemJammedVerbose())
            {
                LogToFile("[Player.Homing] Space blocked by Radio Jammer (Issue #1036)");
                return;
            }

            if (_homingCharges > 0 && !_homingActive)
            {
                _homingActive = true;
                _homingTimer = HomingDuration;
                _homingCharges--;
                PlayHomingSound();
                StartHomingScanner();
                // Show combined progress bar (charge pips + timer) on activation (Issue #974)
                _homingBarVisible = true;
                _homingChargeBarPending = false;
                QueueRedraw();
                EmitSignal(SignalName.HomingActivated);
                EmitSignal(SignalName.HomingChargesChanged, _homingCharges, MaxHomingCharges);
                LogToFile($"[Player.Homing] Homing activated! Duration: {HomingDuration}s, charges remaining: {_homingCharges}/{MaxHomingCharges}");

                // Enable homing on all already-airborne player bullets
                EnableHomingOnAirborneBullets();
            }
        }
    }

    /// <summary>
    /// Enable homing on all player bullets currently in the scene.
    /// Called when the player activates homing so that bullets already in flight
    /// also start steering toward enemies.
    /// </summary>
    private void EnableHomingOnAirborneBullets()
    {
        var tree = GetTree();
        if (tree == null)
        {
            return;
        }

        var currentScene = tree.CurrentScene;
        if (currentScene == null)
        {
            return;
        }

        int enabledCount = 0;
        ulong myId = GetInstanceId();

        // Find all Bullet nodes in the scene
        EnableHomingRecursive(currentScene, myId, ref enabledCount);

        if (enabledCount > 0)
        {
            LogToFile($"[Player.Homing] Enabled homing on {enabledCount} airborne bullets");
        }
    }

    /// <summary>
    /// Recursively find Bullet and ShotgunPellet nodes and enable homing on player projectiles.
    /// </summary>
    private void EnableHomingRecursive(Node node, ulong playerId, ref int count)
    {
        // Check if this is a C# Bullet
        if (node is CSharpBullet csBullet)
        {
            if (csBullet.ShooterId == playerId && !csBullet.HomingEnabled)
            {
                csBullet.EnableHoming();
                count++;
            }
        }
        // Check if this is a C# ShotgunPellet (Issue #704)
        else if (node is CSharpShotgunPellet csPellet)
        {
            if (csPellet.ShooterId == playerId && !csPellet.HomingEnabled)
            {
                csPellet.EnableHoming();
                count++;
            }
        }
        // Check if this is a GDScript bullet (has enable_homing method and shooter_id property)
        else if (node is Area2D area && node.HasMethod("enable_homing"))
        {
            var shooterId = node.Get("shooter_id");
            if (shooterId.VariantType != Variant.Type.Nil)
            {
                ulong bulletShooterId = shooterId.AsUInt64();
                if (bulletShooterId == playerId)
                {
                    var homingEnabled = node.Get("homing_enabled");
                    if (homingEnabled.VariantType == Variant.Type.Nil || !(bool)homingEnabled)
                    {
                        node.Call("enable_homing");
                        count++;
                    }
                }
            }
        }

        // Recurse into children
        foreach (var child in node.GetChildren())
        {
            EnableHomingRecursive(child, playerId, ref count);
        }
    }

    /// <summary>
    /// Set up the audio players for homing activation sound and scanner loop (Issue #890).
    /// </summary>
    private void SetupHomingAudio()
    {
        if (ResourceLoader.Exists(HomingSoundPath))
        {
            var stream = GD.Load<AudioStream>(HomingSoundPath);
            if (stream != null)
            {
                _homingAudioPlayer = new AudioStreamPlayer();
                _homingAudioPlayer.Stream = stream;
                _homingAudioPlayer.VolumeDb = -3.0f;
                AddChild(_homingAudioPlayer);
                LogToFile("[Player.Homing] Homing activation sound loaded");
            }
        }
        else
        {
            LogToFile($"[Player.Homing] Homing activation sound not found: {HomingSoundPath}");
        }

        // Set up the looping scanner ambient sound (Issue #890).
        if (ResourceLoader.Exists(HomingScannerLoopPath))
        {
            var scannerStream = GD.Load<AudioStreamWav>(HomingScannerLoopPath);
            if (scannerStream != null)
            {
                scannerStream.LoopMode = AudioStreamWav.LoopModeEnum.Forward;
                // Set loop endpoints so the stream actually loops the full clip.
                // Without LoopEnd, Godot defaults to 0 → loops a zero-length region (silence).
                int bytesPerSample = (scannerStream.Format == AudioStreamWav.FormatEnum.Format16Bits) ? 2 : 1;
                int channels = scannerStream.Stereo ? 2 : 1;
                int totalSamples = scannerStream.Data.Length / (bytesPerSample * channels);
                scannerStream.LoopBegin = 0;
                scannerStream.LoopEnd = totalSamples;
                _homingScannerPlayer = new AudioStreamPlayer();
                _homingScannerPlayer.Stream = scannerStream;
                // 3x quieter than original -18 dB: 20*log10(1/3) ≈ -9.54 dB → -18 - 9.54 ≈ -27.5 dB
                _homingScannerPlayer.VolumeDb = -27.5f;
                AddChild(_homingScannerPlayer);
                // Do NOT play here — scanner starts only when homing is activated (Issue #890).
                LogToFile($"[Player.Homing] Homing scanner loop ready (Issue #890), samples={totalSamples}");
            }
        }
        else
        {
            LogToFile($"[Player.Homing] Homing scanner loop sound not found: {HomingScannerLoopPath}");
        }
    }

    /// <summary>
    /// Play the homing activation sound.
    /// </summary>
    private void PlayHomingSound()
    {
        if (_homingAudioPlayer != null && IsInstanceValid(_homingAudioPlayer))
        {
            _homingAudioPlayer.Play();
        }
    }

    /// <summary>
    /// Start the looping scanner sound. Called when homing is activated (Issue #890).
    /// </summary>
    private void StartHomingScanner()
    {
        if (_homingScannerPlayer != null && IsInstanceValid(_homingScannerPlayer) && !_homingScannerPlayer.Playing)
        {
            _homingScannerPlayer.Play();
            LogToFile("[Player.Homing] Homing scanner loop started (Issue #890)");
        }
    }

    /// <summary>
    /// Stop the looping scanner sound. Called when homing effect expires (Issue #890).
    /// </summary>
    private void StopHomingScanner()
    {
        if (_homingScannerPlayer != null && IsInstanceValid(_homingScannerPlayer) && _homingScannerPlayer.Playing)
        {
            _homingScannerPlayer.Stop();
            LogToFile("[Player.Homing] Homing scanner loop stopped (Issue #890)");
        }
    }

    /// <summary>
    /// Check if homing bullets effect is currently active.
    /// </summary>
    public bool IsHomingActive()
    {
        return _homingActive;
    }

    #endregion

    #region BFF Pendant Methods (Issue #674)

    /// <summary>
    /// Initialize the BFF pendant if the ActiveItemManager has it selected.
    /// </summary>
    private void InitBffPendant()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.BffPendant] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_bff_pendant"))
        {
            LogToFile("[Player.BffPendant] ActiveItemManager missing has_bff_pendant method");
            return;
        }

        bool hasBffPendant = (bool)activeItemManager.Call("has_bff_pendant");
        if (!hasBffPendant)
        {
            LogToFile("[Player.BffPendant] No BFF pendant selected in ActiveItemManager");
            return;
        }

        LogToFile("[Player.BffPendant] BFF pendant is selected, ready to summon companion");

        // Verify enemy scene exists (we spawn an actual enemy as companion)
        if (!ResourceLoader.Exists(BffEnemyScenePath))
        {
            LogToFile($"[Player.BffPendant] WARNING: Enemy scene not found: {BffEnemyScenePath}");
            return;
        }

        _bffPendantEquipped = true;
        _bffCompanionSummoned = false;
        LogToFile("[Player.BffPendant] BFF pendant equipped — press Space to summon companion");
    }

    /// <summary>
    /// Handle BFF pendant input: press Space to summon a companion (one charge per battle).
    /// </summary>
    private void HandleBffPendantInput()
    {
        if (!_bffPendantEquipped)
        {
            return;
        }

        if (_bffCompanionSummoned)
        {
            return;
        }

        if (Input.IsActionJustPressed("flashlight_toggle"))
        {
            // Issue #1036: Block active item use when jammed by a Radio Jammer enemy
            if (IsActiveItemJammedVerbose())
            {
                LogToFile("[Player.BffPendant] Space blocked by Radio Jammer (Issue #1036)");
                return;
            }

            SummonBffCompanion();
        }
    }

    /// <summary>
    /// Summon the BFF companion near the player.
    /// Issue #674: Spawns an actual Enemy in permanent aggressive state.
    /// User feedback: "copy enemy AI but make it aggressive and not treat player as enemy"
    /// </summary>
    private void SummonBffCompanion()
    {
        if (_bffCompanionSummoned)
        {
            return;
        }

        if (!ResourceLoader.Exists(BffEnemyScenePath))
        {
            LogToFile($"[Player.BffPendant] WARNING: Enemy scene not found: {BffEnemyScenePath}");
            return;
        }

        var enemyScene = GD.Load<PackedScene>(BffEnemyScenePath);
        if (enemyScene == null)
        {
            LogToFile("[Player.BffPendant] WARNING: Failed to load enemy scene");
            return;
        }

        var companion = enemyScene.Instantiate<Node2D>();

        // Configure health range to 2-4 HP as per issue requirements (before adding to scene)
        if (companion.HasMethod("set") && companion.Get("min_health").VariantType != Variant.Type.Nil)
        {
            companion.Set("min_health", 2);
            companion.Set("max_health", 4);
        }

        // Issue #926: BFF companion has 50% slower reaction speed than enemies.
        // Multiply all reaction/detection delays by 1.5 (150% of normal = 50% slower).
        const float BffReactionMultiplier = 1.5f;
        companion.Set("detection_delay", 0.2f * BffReactionMultiplier);       // 0.2s * 1.5 = 0.3s
        companion.Set("threat_reaction_delay", 0.2f * BffReactionMultiplier); // 0.2s * 1.5 = 0.3s
        companion.Set("lead_prediction_delay", 0.3f * BffReactionMultiplier); // 0.3s * 1.5 = 0.45s

        // Add to the current scene (not as child of player, so it moves independently)
        var tree = GetTree();
        if (tree?.CurrentScene == null)
        {
            LogToFile("[Player.BffPendant] WARNING: No current scene to add companion to");
            companion.QueueFree();
            return;
        }

        tree.CurrentScene.AddChild(companion);

        // CRITICAL: Remove from "enemies" group so other enemies don't target it
        // and so it doesn't count toward level enemy counter
        companion.RemoveFromGroup("enemies");

        // Add to "bff_companions" group for identification
        companion.AddToGroup("bff_companions");

        // Set companion name for logging
        companion.Name = "BffCompanion";

        // Make companion permanently aggressive (uses AggressionComponent AI to attack enemies)
        if (companion.HasMethod("set_aggressive"))
        {
            companion.Call("set_aggressive", true);
            LogToFile("[Player.BffPendant] Companion set to aggressive state");
        }

        // Apply green-cyan tint to distinguish from regular enemies
        ApplyBffCompanionVisualTint(companion);

        // Find a valid spawn position that is not inside a wall
        var spawnPos = FindValidBffCompanionSpawnPosition();
        companion.GlobalPosition = spawnPos;

        _bffCompanionNode = companion;
        _bffCompanionSummoned = true;

        // Connect companion death signal if it exists
        if (companion.HasSignal("died"))
        {
            companion.Connect("died", Callable.From(OnBffCompanionDied));
        }

        LogToFile($"[Player.BffPendant] Companion spawned at {companion.GlobalPosition} (aggressive enemy)");
    }

    /// <summary>
    /// Apply a green-cyan tint to the companion to distinguish it from regular enemies.
    /// </summary>
    private static void ApplyBffCompanionVisualTint(Node2D companion)
    {
        var model = companion.GetNodeOrNull("EnemyModel");
        if (model == null)
        {
            return;
        }

        var tint = new Color(0.3f, 1.0f, 0.7f, 1.0f);
        foreach (var spriteName in new[] { "Body", "Head", "LeftArm", "RightArm" })
        {
            var sprite = model.GetNodeOrNull(spriteName);
            if (sprite is Sprite2D sprite2D)
            {
                sprite2D.Modulate = tint;
            }
        }
    }

    /// <summary>
    /// Find a valid spawn position for the companion that is not inside a wall.
    /// Tries multiple offsets around the player until a valid position is found.
    /// Issue #674: Prevents companion from spawning inside/behind walls.
    /// </summary>
    private Vector2 FindValidBffCompanionSpawnPosition()
    {
        var spaceState = GetWorld2D().DirectSpaceState;
        if (spaceState == null)
        {
            LogToFile("[Player.BffPendant] WARNING: Physics state unavailable, using default spawn");
            return GlobalPosition + new Vector2(-50, 30);
        }

        const float CompanionRadius = 24.0f;

        float baseRotation = _playerModel?.Rotation ?? 0.0f;
        var offsets = new Vector2[]
        {
            new Vector2(-50, 30).Rotated(baseRotation),
            new Vector2(-60, 0).Rotated(baseRotation),
            new Vector2(-50, -30).Rotated(baseRotation),
            new Vector2(0, 50).Rotated(baseRotation),
            new Vector2(0, -50).Rotated(baseRotation),
            new Vector2(50, 30).Rotated(baseRotation),
            new Vector2(50, -30).Rotated(baseRotation),
            new Vector2(-30, 0).Rotated(baseRotation),
        };

        foreach (var offset in offsets)
        {
            var testPos = GlobalPosition + offset;
            if (IsBffSpawnPositionValid(spaceState, testPos, CompanionRadius))
            {
                LogToFile($"[Player.BffPendant] Found valid spawn at offset {offset}");
                return testPos;
            }
        }

        LogToFile("[Player.BffPendant] WARNING: No valid spawn position found, spawning at player");
        return GlobalPosition;
    }

    /// <summary>
    /// Check if a position is valid for spawning the companion.
    /// Returns true if the position is not inside a wall and has line of sight from player.
    /// </summary>
    private bool IsBffSpawnPositionValid(PhysicsDirectSpaceState2D spaceState, Vector2 pos, float radius)
    {
        // First check: line of sight from player to spawn position
        var losQuery = new PhysicsRayQueryParameters2D
        {
            From = GlobalPosition,
            To = pos,
            CollisionMask = 1  // Walls only (layer 1)
        };
        var losResult = spaceState.IntersectRay(losQuery);
        if (losResult.Count > 0)
        {
            return false; // Wall blocks line of sight
        }

        // Second check: position itself is not inside a wall
        var shapeQuery = new PhysicsShapeQueryParameters2D
        {
            Shape = new CircleShape2D { Radius = radius },
            Transform = new Transform2D(0, pos),
            CollisionMask = 1  // Walls only (layer 1)
        };
        var overlapResult = spaceState.IntersectShape(shapeQuery);
        return overlapResult.Count == 0;
    }

    /// <summary>
    /// Called when the BFF companion dies.
    /// </summary>
    private void OnBffCompanionDied()
    {
        LogToFile("[Player.BffPendant] Companion has been killed");
        _bffCompanionNode = null;
    }

    #endregion

    #region Invisibility Suit Methods (Issue #673)

    /// <summary>
    /// Initialize the invisibility suit if the ActiveItemManager has it selected.
    /// Loads the GDScript effect and HUD nodes and wires up signal callbacks.
    /// </summary>
    private void InitInvisibilitySuit()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.InvisibilitySuit] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_invisibility_suit"))
        {
            LogToFile("[Player.InvisibilitySuit] ActiveItemManager missing has_invisibility_suit method");
            return;
        }

        bool hasInvisibilitySuit = (bool)activeItemManager.Call("has_invisibility_suit");
        if (!hasInvisibilitySuit)
        {
            LogToFile("[Player.InvisibilitySuit] No invisibility suit selected in ActiveItemManager");
            return;
        }

        LogToFile("[Player.InvisibilitySuit] Invisibility suit is selected, initializing...");

        // Load and instantiate the GDScript effect controller
        var effectScript = GD.Load<Script>("res://scripts/effects/invisibility_suit_effect.gd");
        if (effectScript == null)
        {
            LogToFile("[Player.InvisibilitySuit] WARNING: Failed to load invisibility_suit_effect.gd");
            return;
        }

        _invisibilitySuitEffect = new Node();
        _invisibilitySuitEffect.SetScript(effectScript);
        _invisibilitySuitEffect.Name = "InvisibilitySuitEffect";
        AddChild(_invisibilitySuitEffect);

        // Initialize with player reference
        _invisibilitySuitEffect.Call("initialize", this);

        // Connect signals for HUD updates
        _invisibilitySuitEffect.Connect("invisibility_activated", Callable.From<int>(OnInvisibilityActivated));
        _invisibilitySuitEffect.Connect("invisibility_deactivated", Callable.From<int>(OnInvisibilityDeactivated));

        _invisibilitySuitEquipped = true;
        int charges = (int)_invisibilitySuitEffect.Call("get_charges");
        LogToFile($"[Player.InvisibilitySuit] Invisibility suit equipped, charges: {charges}");

        // Load and instantiate the GDScript charge bar (Node2D positioned above player)
        var hudScript = GD.Load<Script>("res://scripts/ui/invisibility_hud.gd");
        if (hudScript != null)
        {
            _invisibilityHud = new Node2D();
            _invisibilityHud.SetScript(hudScript);
            _invisibilityHud.Name = "InvisibilityHUD";
            AddChild(_invisibilityHud);
            _invisibilityHud.Call("initialize", _invisibilitySuitEffect);
            LogToFile("[Player.InvisibilitySuit] Charge bar created");
        }
        else
        {
            LogToFile("[Player.InvisibilitySuit] WARNING: Failed to load invisibility_hud.gd");
        }
    }

    /// <summary>
    /// Handle invisibility suit input: press Space to activate.
    /// Single press activates for full duration (4 seconds), auto-deactivates.
    /// </summary>
    private void HandleInvisibilitySuitInput()
    {
        if (!_invisibilitySuitEquipped || _invisibilitySuitEffect == null)
        {
            return;
        }

        if (!IsInstanceValid(_invisibilitySuitEffect))
        {
            return;
        }

        // Issue #1115: Cancel invisibility immediately if player enters jammer range while active
        if (IsActiveItemJammedSilent())
        {
            bool isActive = (bool)_invisibilitySuitEffect.Get("is_active");
            if (isActive)
            {
                _invisibilitySuitEffect.Call("deactivate");
                LogToFile("[Player.InvisibilitySuit] Invisibility cancelled by Radio Jammer (Issue #1115)");
            }
        }

        if (Input.IsActionJustPressed("flashlight_toggle"))
        {
            // Issue #1036: Block active item use when jammed by a Radio Jammer enemy
            if (IsActiveItemJammedVerbose())
            {
                LogToFile("[Player.InvisibilitySuit] Space blocked by Radio Jammer (Issue #1036)");
                return;
            }

            bool isActive = (bool)_invisibilitySuitEffect.Get("is_active");
            if (!isActive)
            {
                _invisibilitySuitEffect.Call("activate");
            }
        }
    }

    /// <summary>
    /// Check if the player is currently invisible (Issue #673).
    /// Called by enemy AI via duck typing (has_method + call).
    /// </summary>
    public bool is_invisible()
    {
        if (!_invisibilitySuitEquipped || _invisibilitySuitEffect == null)
            return false;
        if (!IsInstanceValid(_invisibilitySuitEffect))
            return false;
        return (bool)_invisibilitySuitEffect.Call("is_invisible");
    }

    /// <summary>
    /// Callback when invisibility activates.
    /// </summary>
    private void OnInvisibilityActivated(int chargesRemaining)
    {
        if (_invisibilityHud != null && IsInstanceValid(_invisibilityHud))
        {
            _invisibilityHud.Call("set_active", true);
            _invisibilityHud.Call("update_charges", chargesRemaining, InvisibilityMaxCharges);
        }

        // Issue #723: Reset enemy memory when player becomes invisible
        // Enemies lose track and enter search mode at last known position
        ResetAllEnemyMemories("invisibility activation");
    }

    /// <summary>
    /// Callback when invisibility deactivates.
    /// </summary>
    private void OnInvisibilityDeactivated(int chargesRemaining)
    {
        if (_invisibilityHud != null && IsInstanceValid(_invisibilityHud))
        {
            _invisibilityHud.Call("set_active", false);
            _invisibilityHud.Call("update_charges", chargesRemaining, InvisibilityMaxCharges);
        }
    }

    #endregion

    #region Trajectory Glasses System (Issue #744)

    /// <summary>
    /// Whether trajectory glasses are equipped (active item selected in armory).
    /// </summary>
    private bool _trajectoryGlassesEquipped = false;

    /// <summary>
    /// Reference to the GDScript trajectory glasses effect node.
    /// </summary>
    private Node? _trajectoryGlassesEffect = null;

    /// <summary>
    /// Reference to the GDScript trajectory glasses HUD node.
    /// </summary>
    private Node? _trajectoryGlassesHud = null;

    // Progress bar state for trajectory glasses (Issue #974)
    /// <summary>Whether the trajectory glasses combined progress bar is visible.</summary>
    private bool _trajectoryBarVisible = false;
    /// <summary>Current charges remaining for trajectory glasses (cached for drawing).</summary>
    private int _trajectoryBarCharges = 0;
    /// <summary>Whether the trajectory charge bar should show briefly after deactivation.</summary>
    private bool _trajectoryChargeBarPending = false;
    /// <summary>Timer for auto-hiding trajectory charge bar after deactivation (300ms).</summary>
    private float _trajectoryChargeBarHideTimer = 0.0f;
    /// <summary>Duration to show charge bar after deactivation before auto-hiding.</summary>
    private const float TrajectoryChargeBarHideDelay = 0.3f;
    /// <summary>Effect duration for trajectory glasses (must match trajectory_glasses_effect.gd).</summary>
    private const float TrajectoryGlassesDuration = 10.0f;
    /// <summary>Max charges for trajectory glasses (must match trajectory_glasses_effect.gd).</summary>
    private const int TrajectoryGlassesMaxCharges = 2;

    /// <summary>
    /// Initialize trajectory glasses if the ActiveItemManager has them selected (Issue #744).
    /// Loads and instantiates the GDScript trajectory_glasses_effect.gd controller.
    /// </summary>
    private void InitTrajectoryGlasses()
    {
        LogToFile("[Player.TrajectoryGlasses] Checking trajectory glasses...");

        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.TrajectoryGlasses] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_trajectory_glasses"))
        {
            LogToFile("[Player.TrajectoryGlasses] ActiveItemManager missing has_trajectory_glasses method");
            return;
        }

        bool hasTrajectoryGlasses = (bool)activeItemManager.Call("has_trajectory_glasses");
        if (!hasTrajectoryGlasses)
        {
            LogToFile("[Player.TrajectoryGlasses] No trajectory glasses selected in ActiveItemManager");
            return;
        }

        LogToFile("[Player.TrajectoryGlasses] Trajectory glasses selected, initializing...");

        // Load and instantiate the GDScript effect controller
        var effectScript = GD.Load<Script>("res://scripts/effects/trajectory_glasses_effect.gd");
        if (effectScript == null)
        {
            LogToFile("[Player.TrajectoryGlasses] WARNING: Failed to load trajectory_glasses_effect.gd");
            return;
        }

        _trajectoryGlassesEffect = new Node();
        _trajectoryGlassesEffect.SetScript(effectScript);
        _trajectoryGlassesEffect.Name = "TrajectoryGlassesEffect";
        AddChild(_trajectoryGlassesEffect);

        // Initialize with player reference
        _trajectoryGlassesEffect.Call("initialize", this);

        // Pass current weapon so ricochet angle is weapon-specific (Issue #744)
        if (CurrentWeapon != null)
        {
            _trajectoryGlassesEffect.Call("set_weapon", CurrentWeapon);
            LogToFile($"[Player.TrajectoryGlasses] Weapon set: {CurrentWeapon.Name}");
        }

        // Connect signals
        _trajectoryGlassesEffect.Connect("trajectory_activated", Callable.From<int>(OnTrajectoryActivated));
        _trajectoryGlassesEffect.Connect("trajectory_deactivated", Callable.From<int>(OnTrajectoryDeactivated));

        _trajectoryGlassesEquipped = true;
        int charges = (int)_trajectoryGlassesEffect.Get("charges");
        LogToFile($"[Player.TrajectoryGlasses] Trajectory glasses equipped, charges: {charges}");

        // Load and instantiate the GDScript HUD
        var hudScript = GD.Load<Script>("res://scripts/ui/trajectory_glasses_hud.gd");
        if (hudScript != null)
        {
            _trajectoryGlassesHud = new Node2D();
            _trajectoryGlassesHud.SetScript(hudScript);
            _trajectoryGlassesHud.Name = "TrajectoryGlassesHUD";
            AddChild(_trajectoryGlassesHud);
            _trajectoryGlassesHud.Call("initialize", _trajectoryGlassesEffect);
            LogToFile("[Player.TrajectoryGlasses] HUD created");
        }
        else
        {
            LogToFile("[Player.TrajectoryGlasses] WARNING: Failed to load trajectory_glasses_hud.gd");
        }
    }

    /// <summary>
    /// Handle trajectory glasses input: press Space to activate (Issue #744).
    /// Single press activates for full duration (10 seconds), auto-deactivates.
    /// </summary>
    private void HandleTrajectoryGlassesInput()
    {
        if (!_trajectoryGlassesEquipped || _trajectoryGlassesEffect == null)
        {
            return;
        }

        if (!IsInstanceValid(_trajectoryGlassesEffect))
        {
            return;
        }

        // Issue #1115: Cancel trajectory glasses immediately if player enters jammer range while active
        if (IsActiveItemJammedSilent())
        {
            bool isActive = (bool)_trajectoryGlassesEffect.Get("is_active");
            if (isActive)
            {
                _trajectoryGlassesEffect.Call("deactivate");
                LogToFile("[Player.TrajectoryGlasses] Trajectory glasses cancelled by Radio Jammer (Issue #1115)");
            }
        }

        if (Input.IsActionJustPressed("flashlight_toggle"))
        {
            // Issue #1036: Block active item use when jammed by a Radio Jammer enemy
            // Use verbose variant so the log records detailed jammer diagnostics on every Space press
            if (IsActiveItemJammedVerbose())
            {
                LogToFile("[Player.TrajectoryGlasses] Space blocked by Radio Jammer (Issue #1036)");
                return;
            }

            bool isActive = (bool)_trajectoryGlassesEffect.Get("is_active");
            if (!isActive)
            {
                // Update weapon reference in case player switched weapons (Issue #744)
                if (CurrentWeapon != null)
                {
                    _trajectoryGlassesEffect.Call("set_weapon", CurrentWeapon);
                }

                int charges = (int)_trajectoryGlassesEffect.Get("charges");
                LogToFile($"[Player.TrajectoryGlasses] Space pressed - activating (charges: {charges})");
                bool activated = (bool)_trajectoryGlassesEffect.Call("activate");
                LogToFile($"[Player.TrajectoryGlasses] Activation result: {activated}");
                QueueRedraw();
            }
        }
    }

    /// <summary>
    /// Called when trajectory glasses activate (Issue #1049).
    /// Shows charge pips via the HUD for 300ms, then auto-hides — no progress bar.
    /// </summary>
    private void OnTrajectoryActivated(int chargesRemaining)
    {
        _trajectoryBarCharges = chargesRemaining;
        // Show HUD charge pips briefly via the GDScript HUD node (Issue #1049)
        if (_trajectoryGlassesHud != null && IsInstanceValid(_trajectoryGlassesHud))
        {
            _trajectoryGlassesHud.Call("update_charges", chargesRemaining, TrajectoryGlassesMaxCharges);
            _trajectoryGlassesHud.Call("set_active", true);
        }
        QueueRedraw();
    }

    /// <summary>
    /// Called when trajectory glasses deactivate (Issue #1049).
    /// Hides the HUD immediately — no lingering charge bar.
    /// </summary>
    private void OnTrajectoryDeactivated(int chargesRemaining)
    {
        _trajectoryBarCharges = chargesRemaining;
        // Hide HUD immediately on deactivation (Issue #1049)
        if (_trajectoryGlassesHud != null && IsInstanceValid(_trajectoryGlassesHud))
        {
            _trajectoryGlassesHud.Call("update_charges", chargesRemaining, TrajectoryGlassesMaxCharges);
            _trajectoryGlassesHud.Call("set_active", false);
        }
        QueueRedraw();
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

    #region Drilling Bullets System (Issue #751)

    /// <summary>
    /// Whether drilling bullets item is equipped.
    /// </summary>
    private bool _drillingBulletsEquipped = false;

    /// <summary>
    /// Whether the single charge has been used this battle.
    /// </summary>
    private bool _drillingBulletsUsed = false;

    /// <summary>
    /// Floating icon popup node shown above the player when drilling bullets are activated (Issue #1319).
    /// Reuses the same experimental_sample_item_popup.gd script for consistent UX.
    /// </summary>
    private GodotObject _drillingBulletsPopup = null;

    /// <summary>
    /// Duration in seconds to display the drilling bullets activation icon (Issue #1319).
    /// </summary>
    private const float DrillingBulletsIconDuration = 0.4f;

    /// <summary>
    /// Initialize drilling bullets if the ActiveItemManager has them selected (Issue #751).
    /// One charge per battle — press Space to apply wall-piercing to current magazine.
    /// </summary>
    private void InitDrillingBullets()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.DrillingBullets] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_drilling_bullets"))
        {
            LogToFile("[Player.DrillingBullets] ActiveItemManager missing has_drilling_bullets method");
            return;
        }

        bool hasDrilling = (bool)activeItemManager.Call("has_drilling_bullets");
        if (!hasDrilling)
        {
            LogToFile("[Player.DrillingBullets] Drilling bullets not selected in ActiveItemManager");
            return;
        }

        _drillingBulletsEquipped = true;
        _drillingBulletsUsed = false;
        LogToFile("[Player.DrillingBullets] Drilling bullets equipped — 1 charge: press Space to apply to current magazine");

        // Spawn floating icon popup child (Issue #1319): reuse experimental_sample_item_popup.gd
        if (_drillingBulletsPopup == null || !IsInstanceValid((GodotObject)_drillingBulletsPopup))
        {
            var popupScript = GD.Load("res://scripts/ui/experimental_sample_item_popup.gd");
            if (popupScript != null)
            {
                var popupNode = new Node2D();
                popupNode.SetScript(popupScript);
                popupNode.Name = "DrillingBulletsIconPopup";
                AddChild(popupNode);
                _drillingBulletsPopup = popupNode;
            }
        }
    }

    /// <summary>
    /// Handle drilling bullets input: press Space to activate once per battle (Issue #751).
    /// Sets DrillingBulletsRemaining on the current weapon to current magazine ammo count.
    /// </summary>
    private void HandleDrillingBulletsInput()
    {
        if (!_drillingBulletsEquipped)
        {
            return;
        }

        if (Input.IsActionJustPressed("flashlight_toggle"))
        {
            if (!_drillingBulletsUsed)
            {
                // Issue #751: Shotgun uses ShellsInTube as its active ammo count;
                // CurrentAmmo is always 0 for the Shotgun (placeholder for reserve shells only).
                // We must check ShellsInTube for the Shotgun, just like Issue #842 does elsewhere.
                int activeAmmo = CurrentWeapon is Shotgun shotgunDrilling
                    ? shotgunDrilling.ShellsInTube
                    : (CurrentWeapon?.CurrentAmmo ?? 0);

                if (CurrentWeapon != null && activeAmmo > 0)
                {
                    _drillingBulletsUsed = true;
                    int magazineAmmo = activeAmmo;
                    CurrentWeapon.DrillingBulletsRemaining = magazineAmmo;
                    LogToFile($"[Player.DrillingBullets] Activated! Magazine has {magazineAmmo} drilling bullets. Charge consumed.");

                    // Show 400ms activation icon above the player (Issue #1319)
                    if (_drillingBulletsPopup != null && IsInstanceValid((GodotObject)_drillingBulletsPopup))
                    {
                        var activeItemMgr = GetNodeOrNull("/root/ActiveItemManager");
                        if (activeItemMgr != null && activeItemMgr.HasMethod("get_active_item_icon_path"))
                        {
                            // DRILLING_BULLETS = 15 in ActiveItemType enum
                            string iconPath = (string)activeItemMgr.Call("get_active_item_icon_path", 15);
                            if (!string.IsNullOrEmpty(iconPath))
                                ((Node2D)_drillingBulletsPopup).Call("show_icon", iconPath, DrillingBulletsIconDuration);
                        }
                    }
                }
                else
                {
                    LogToFile("[Player.DrillingBullets] Cannot activate — no ammo in current magazine");
                }
            }
        }
    }


    /// <summary>
    /// Draw segmented charge bar for Experimental Sample (Issue #1127).
    /// Shows up to 5 charge pips above the player.
    /// </summary>
    private void DrawExperimentalSampleChargeBar()
    {
        const float barWidth = 40.0f;
        const float barHeight = 6.0f;
        const float barYOffset = -38.0f; // slightly higher to avoid overlap with other bars
        const float segmentGap = 2.0f;
        const float borderWidth = 1.0f;

        int segmentCount = ExperimentalSampleMaxCharges;
        int filledCount = _experimentalSampleCharges;

        float totalGaps = segmentGap * (segmentCount - 1);
        float segmentWidth = (barWidth - totalGaps) / segmentCount;
        if (segmentWidth < 2.0f) segmentWidth = 2.0f;

        float startX = -barWidth / 2.0f;
        float percent = segmentCount > 0 ? (float)filledCount / segmentCount : 0.0f;
        Color fillColor;
        if (percent > 0.5f)
            fillColor = new Color(0.5f, 0.3f, 0.9f, 0.85f); // Purple — full/high
        else if (percent > 0.25f)
            fillColor = new Color(0.8f, 0.5f, 0.9f, 0.85f); // Light purple — medium
        else
            fillColor = new Color(0.9f, 0.2f, 0.6f, 0.85f); // Pink/red — low

        Color bgColor = new Color(0.1f, 0.1f, 0.1f, 0.6f);
        Color emptyColor = new Color(0.2f, 0.2f, 0.2f, 0.4f);
        Color borderColor = new Color(0.3f, 0.3f, 0.3f, 0.7f);

        for (int i = 0; i < segmentCount; i++)
        {
            float segX = startX + i * (segmentWidth + segmentGap);
            Rect2 segRect = new Rect2(segX, barYOffset, segmentWidth, barHeight);

            DrawRect(segRect, bgColor);
            if (i < filledCount)
                DrawRect(segRect, fillColor);
            else
                DrawRect(segRect, emptyColor);
            DrawRect(segRect, borderColor, false, borderWidth);
        }
    }

    #endregion

    #region Combat Disposition System (Issue #1047)

    /// <summary>
    /// Whether the Combat Disposition passive item is active.
    /// When active, player damage and fire rate are boosted on start,
    /// and reduced once after the first hit per run.
    /// </summary>
    private bool _combatDispositionActive = false;

    /// <summary>
    /// Whether the hit penalty has already been applied this run.
    /// The penalty is applied only once (on the first hit taken).
    /// </summary>
    private bool _combatDispositionPenaltyApplied = false;

    /// <summary>
    /// Current damage bonus from Combat Disposition.
    /// Starts at +0.77, decreases by 6.0 on first hit taken.
    /// </summary>
    private float _combatDispositionDamageBonus = 0.0f;

    /// <summary>
    /// Current fire rate bonus from Combat Disposition.
    /// Starts at +1.1, decreases by 7.2 on first hit taken.
    /// </summary>
    private float _combatDispositionFireRateBonus = 0.0f;

    /// <summary>
    /// The original MaxSpeed stored before Combat Disposition's speed bonus is applied.
    /// Used to correctly remove/halve the bonus on first hit.
    /// </summary>
    private float _combatDispositionBaseSpeed = 0.0f;

    /// <summary>
    /// The original Friction stored before Combat Disposition's speed bonus is applied (Issue #1583).
    /// Friction is doubled alongside the speed boost to keep the stopping feel proportional (halving drift).
    /// Restored when the hit penalty is applied.
    /// </summary>
    private float _combatDispositionBaseFriction = 0.0f;

    /// <summary>Sword icon shown near the player when the positive effect is active.</summary>
    private Sprite2D? _combatDispositionSwordIcon = null;

    /// <summary>Broken sword icon shown near the player when the negative effect is active.</summary>
    private Sprite2D? _combatDispositionBrokenSwordIcon = null;

    /// <summary>
    /// Initialize Combat Disposition if the ActiveItemManager has it selected (Issue #1047).
    /// Sets the initial damage and fire rate bonuses on the current weapon.
    /// </summary>
    private void InitCombatDisposition()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.CombatDisposition] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_combat_disposition"))
        {
            LogToFile("[Player.CombatDisposition] ActiveItemManager missing has_combat_disposition method");
            return;
        }

        bool hasCombatDisposition = (bool)activeItemManager.Call("has_combat_disposition");
        if (!hasCombatDisposition)
        {
            LogToFile("[Player.CombatDisposition] Combat Disposition not selected in ActiveItemManager");
            return;
        }

        _combatDispositionActive = true;
        _combatDispositionPenaltyApplied = false;
        _combatDispositionDamageBonus = 0.77f;
        _combatDispositionFireRateBonus = 1.1f;

        // Apply bonuses to current weapon
        if (CurrentWeapon != null)
        {
            CurrentWeapon.DamageBonus = _combatDispositionDamageBonus;
            CurrentWeapon.FireRateBonus = _combatDispositionFireRateBonus;
            LogToFile($"[Player.CombatDisposition] Initialized on weapon {CurrentWeapon.Name}: +{_combatDispositionDamageBonus} damage, +{_combatDispositionFireRateBonus} fire rate");
        }

        // Apply movement speed bonus (Issue #1583):
        // Normal difficulties: x2 speed. Black Metal difficulty: x4 speed total.
        // Friction is scaled by the same multiplier to keep stopping feel proportional (halving drift).
        _combatDispositionBaseSpeed = MaxSpeed;
        _combatDispositionBaseFriction = Friction;
        var diffMgr = GetNodeOrNull("/root/DifficultyManager");
        bool isBlackMetal = diffMgr != null && diffMgr.HasMethod("is_black_metal_mode") && (bool)diffMgr.Call("is_black_metal_mode");
        float speedMult = isBlackMetal ? 4.0f : 2.0f;
        MaxSpeed = _combatDispositionBaseSpeed * speedMult;
        Friction = _combatDispositionBaseFriction * speedMult;
        LogToFile($"[Player.CombatDisposition] Speed boost applied ({(isBlackMetal ? "Black Metal x4" : "Normal x2")}): speed {_combatDispositionBaseSpeed} -> {MaxSpeed}, friction {_combatDispositionBaseFriction} -> {Friction}");

        // Show sword icon (positive effect active)
        UpdateCombatDispositionIcons();

        LogToFile($"[Player.CombatDisposition] Active — damage bonus: +{_combatDispositionDamageBonus}, fire rate bonus: +{_combatDispositionFireRateBonus}, max speed: {MaxSpeed}, friction: {Friction}");
    }

    /// <summary>
    /// Called when Combat Disposition is active and the player takes damage.
    /// Applies the damage and fire rate penalty only on the first hit per run.
    /// </summary>
    private void ApplyCombatDispositionHitPenalty()
    {
        if (!_combatDispositionActive)
            return;

        // Penalty is applied only once per run (on the first hit)
        if (_combatDispositionPenaltyApplied)
            return;

        _combatDispositionPenaltyApplied = true;
        _combatDispositionDamageBonus -= 6.0f;
        _combatDispositionFireRateBonus -= 7.2f;

        // Apply updated bonuses to current weapon
        if (CurrentWeapon != null)
        {
            CurrentWeapon.DamageBonus = _combatDispositionDamageBonus;
            CurrentWeapon.FireRateBonus = _combatDispositionFireRateBonus;
        }

        // Halve movement speed penalty (Issue #1583): divide speed by 2 after first hit.
        // Restore friction to base value so stopping feel is proportional to the reduced speed.
        MaxSpeed = _combatDispositionBaseSpeed / 2.0f;
        Friction = _combatDispositionBaseFriction;
        LogToFile($"[Player.CombatDisposition] Speed penalty applied: speed {_combatDispositionBaseSpeed} -> {MaxSpeed} (divided by 2), friction restored to {Friction}");

        // Switch icon to broken sword (negative effect active)
        UpdateCombatDispositionIcons();

        LogToFile($"[Player.CombatDisposition] First hit — penalty applied once: damage bonus: {_combatDispositionDamageBonus:F1}, fire rate bonus: {_combatDispositionFireRateBonus:F1}, max speed: {MaxSpeed:F1}, friction: {Friction:F1}");
    }

    /// <summary>
    /// Creates or updates the sword / broken-sword icons displayed near the player.
    /// Shows the intact sword icon while the positive bonus is active (before first hit),
    /// and the broken sword icon after the penalty has been applied.
    /// </summary>
    private void UpdateCombatDispositionIcons()
    {
        const string SwordIconPath = "res://assets/sprites/weapons/combat_disposition_icon.png";
        const string BrokenSwordIconPath = "res://assets/sprites/weapons/combat_disposition_broken_sword_icon.png";
        // Position slightly above and to the right of the player
        var iconOffset = new Vector2(20, -40);

        // --- Sword icon (positive effect) ---
        if (_combatDispositionSwordIcon == null)
        {
            var tex = GD.Load<Texture2D>(SwordIconPath);
            if (tex != null)
            {
                _combatDispositionSwordIcon = new Sprite2D();
                _combatDispositionSwordIcon.Name = "CombatDispositionSwordIcon";
                _combatDispositionSwordIcon.Texture = tex;
                _combatDispositionSwordIcon.Scale = new Vector2(0.5f, 0.5f);
                _combatDispositionSwordIcon.Position = iconOffset;
                AddChild(_combatDispositionSwordIcon);
            }
            else
            {
                LogToFile($"[Player.CombatDisposition] WARNING: Failed to load sword icon: {SwordIconPath}");
            }
        }

        // --- Broken sword icon (negative effect) ---
        if (_combatDispositionBrokenSwordIcon == null)
        {
            var tex = GD.Load<Texture2D>(BrokenSwordIconPath);
            if (tex != null)
            {
                _combatDispositionBrokenSwordIcon = new Sprite2D();
                _combatDispositionBrokenSwordIcon.Name = "CombatDispositionBrokenSwordIcon";
                _combatDispositionBrokenSwordIcon.Texture = tex;
                _combatDispositionBrokenSwordIcon.Scale = new Vector2(0.5f, 0.5f);
                _combatDispositionBrokenSwordIcon.Position = iconOffset;
                AddChild(_combatDispositionBrokenSwordIcon);
            }
            else
            {
                LogToFile($"[Player.CombatDisposition] WARNING: Failed to load broken sword icon: {BrokenSwordIconPath}");
            }
        }

        // Show/hide based on penalty state
        bool penaltyApplied = _combatDispositionPenaltyApplied;
        if (_combatDispositionSwordIcon != null)
            _combatDispositionSwordIcon.Visible = !penaltyApplied;
        if (_combatDispositionBrokenSwordIcon != null)
            _combatDispositionBrokenSwordIcon.Visible = penaltyApplied;
    }

    #endregion

    #region Force Field System (Issue #676)

    /// <summary>
    /// Initialize the force field if the ActiveItemManager has it selected.
    /// Loads the GDScript effect node and attaches it as a child.
    /// </summary>
    private void InitForceField()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.ForceField] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_force_field"))
        {
            LogToFile("[Player.ForceField] ActiveItemManager missing has_force_field method");
            return;
        }

        bool hasForceField = (bool)activeItemManager.Call("has_force_field");
        if (!hasForceField)
        {
            LogToFile("[Player.ForceField] Force field not selected in ActiveItemManager");
            return;
        }

        LogToFile("[Player.ForceField] Force field is selected, initializing...");

        // Load the GDScript effect scene
        const string ForceFieldScenePath = "res://scenes/effects/ForceFieldEffect.tscn";
        var forceFieldScene = GD.Load<PackedScene>(ForceFieldScenePath);
        if (forceFieldScene == null)
        {
            LogToFile($"[Player.ForceField] WARNING: Failed to load ForceFieldEffect scene: {ForceFieldScenePath}");
            return;
        }

        _forceFieldEffect = forceFieldScene.Instantiate();
        _forceFieldEffect.Name = "ForceFieldEffect";
        AddChild(_forceFieldEffect);
        _forceFieldEquipped = true;

        LogToFile("[Player.ForceField] Force field initialized successfully");
    }

    /// <summary>
    /// Handle force field input: hold Space to activate, release to deactivate.
    /// </summary>
    /// <param name="delta">Physics frame delta time.</param>
    private void HandleForceFieldInput(float delta)
    {
        if (!_forceFieldEquipped || _forceFieldEffect == null)
        {
            return;
        }

        if (!IsInstanceValid(_forceFieldEffect))
        {
            return;
        }

        // Issue #1036 / #1115: Block active item use when jammed by a Radio Jammer enemy,
        // and deactivate the force field immediately if it is active when the player enters jammer range.
        // Use silent check (hold action fires every frame — verbose would flood the log)
        if (IsActiveItemJammedSilent())
        {
            bool isActiveJammed = (bool)_forceFieldEffect.Get("is_active");
            if (isActiveJammed)
            {
                _forceFieldEffect.Call("deactivate");
                LogToFile("[Player.ForceField] Force field cancelled by Radio Jammer (Issue #1115)");
            }
            if (Input.IsActionJustPressed("flashlight_toggle"))
                LogToFile("[Player.ForceField] Space blocked by Radio Jammer (Issue #1036)");
            return;
        }

        // Hold Space to activate, release to deactivate
        if (Input.IsActionPressed("flashlight_toggle"))
        {
            bool isActive = (bool)_forceFieldEffect.Get("is_active");
            if (!isActive)
            {
                _forceFieldEffect.Call("activate");
            }
        }
        else
        {
            bool isActive = (bool)_forceFieldEffect.Get("is_active");
            if (isActive)
            {
                _forceFieldEffect.Call("deactivate");
            }
        }
    }

    /// <summary>
    /// Check if force field is currently protecting the player (Issue #676).
    /// Called by bullet/projectile code via duck typing.
    /// </summary>
    public bool is_force_field_active()
    {
        if (!_forceFieldEquipped || _forceFieldEffect == null)
            return false;
        if (!IsInstanceValid(_forceFieldEffect))
            return false;
        return (bool)_forceFieldEffect.Call("is_protecting");
    }

    #endregion

    #region Auto-Reload System (Issue #1067)

    /// <summary>
    /// The ratio by which the magazine capacity is reduced when auto-reload is active.
    /// Magazine size = floor(original / AutoReloadMagazineDivisor).
    /// </summary>
    private const float AutoReloadMagazineDivisor = 2.1f;

    /// <summary>
    /// Whether the auto-reload passive item is active.
    /// When true, killing an enemy refills the current magazine from reserves.
    /// </summary>
    private bool _autoReloadActive = false;

    /// <summary>
    /// The reduced magazine size used by the auto-reload system (Issue #1067).
    /// Cached after ReduceMagazineSizeForAutoReload() so OnEnemyKilledForAutoReload
    /// uses the actual reduced capacity (not WeaponData.MagazineSize which stays at original).
    /// For the Revolver this equals floor(CylinderSize / 2.1).
    /// </summary>
    private int _autoReloadMagazineSize = 0;

    /// <summary>
    /// Initialize the auto-reload passive item if the ActiveItemManager has it selected (Issue #1067).
    /// Reduces magazine capacity by 2.1x and connects to enemy death signals so that
    /// each kill tops up the current magazine from reserve ammo.
    /// </summary>
    private void InitAutoReload()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.AutoReload] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_auto_reload"))
        {
            LogToFile("[Player.AutoReload] ActiveItemManager missing has_auto_reload method");
            return;
        }

        bool hasAutoReload = (bool)activeItemManager.Call("has_auto_reload");
        if (!hasAutoReload)
        {
            LogToFile("[Player.AutoReload] Auto-reload not selected in ActiveItemManager");
            return;
        }

        _autoReloadActive = true;
        LogToFile("[Player.AutoReload] Auto-reload active — magazine capacity reduced 2.1x, kills refill magazine from reserves");

        // Reduce magazine capacity on the current weapon.
        // NOTE: Level GDScript _Ready() may call ReinitializeMagazines AFTER this runs,
        // resetting the magazine size. ApplyAutoReloadAfterLevelAmmoConfig() is called
        // by level scripts (building_level.gd, labyrinth_level.gd) to reapply the reduction.
        ReduceMagazineSizeForAutoReload();

        // Connect to all existing enemy Died signals
        ConnectAutoReloadToEnemies();
    }

    /// <summary>
    /// Reapplies the auto-reload magazine size reduction after a level script has
    /// reinitialized the weapon's magazines (e.g. building_level.gd applying ammo config).
    /// Called from GDScript level scripts to ensure the reduction persists.
    /// No-op if auto-reload is not active.
    /// </summary>
    public void ApplyAutoReloadAfterLevelAmmoConfig()
    {
        if (!_autoReloadActive)
            return;

        LogToFile("[Player.AutoReload] Re-applying magazine size reduction after level ammo config");
        ReduceMagazineSizeForAutoReload();
    }

    /// <summary>
    /// Reduces the current weapon's magazine size by the auto-reload divisor (2.1x).
    /// The new magazine size is floor(original / 2.1).
    /// Total ammo count is preserved: uses more (smaller) magazines so the player has
    /// the same number of bullets overall. Only the per-magazine capacity is reduced.
    /// Caches the reduced size in _autoReloadMagazineSize for use in OnEnemyKilledForAutoReload.
    /// For the Revolver, uses CylinderSize as the authoritative original size (Issue #1067).
    /// </summary>
    private void ReduceMagazineSizeForAutoReload()
    {
        if (CurrentWeapon == null)
        {
            LogToFile("[Player.AutoReload] No current weapon — skipping magazine size reduction");
            return;
        }

        bool isRevolver = CurrentWeapon.HasMethod("get_cylinder_capacity");

        // For the Revolver, CylinderSize is the authoritative size (not WeaponData.MagazineSize,
        // which may be stale in release builds due to Issue #950).
        int originalSize;
        if (isRevolver)
        {
            // Revolver exposes CylinderCapacity via property — read via Get()
            var cylCap = CurrentWeapon.Get("CylinderSize");
            originalSize = cylCap.AsInt32();
            if (originalSize <= 0 && CurrentWeapon.WeaponData != null)
                originalSize = CurrentWeapon.WeaponData.MagazineSize;
        }
        else if (CurrentWeapon.WeaponData != null)
        {
            originalSize = CurrentWeapon.WeaponData.MagazineSize;
        }
        else
        {
            LogToFile("[Player.AutoReload] No weapon data — skipping magazine size reduction");
            return;
        }

        int reducedSize = Math.Max(1, (int)(originalSize / AutoReloadMagazineDivisor));

        // Cache the reduced size so OnEnemyKilledForAutoReload uses the actual reduced capacity,
        // not WeaponData.MagazineSize which remains at the original unreduced value.
        _autoReloadMagazineSize = reducedSize;

        // Issue #1105: The Shotgun stores its total ammo as ShellsInTube + ReserveAmmo, not as
        // StartingMagazineCount × MagazineSize. Using StartingMagazineCount (= 4, the base default)
        // would compute 4 × 8 = 32 total bullets, far exceeding the actual 8 + 12 = 20 available.
        // This would create ammo from thin air.  Use the weapon's actual current ammo for Shotgun.
        int totalBullets;
        int currentMagazineCount;
        if (CurrentWeapon is Shotgun shotgunForAmmoCalc)
        {
            totalBullets = shotgunForAmmoCalc.ShellsInTube + CurrentWeapon.ReserveAmmo;
            currentMagazineCount = CurrentWeapon.StartingMagazineCount; // used only for log
        }
        else
        {
            // Preserve total ammo: calculate how many smaller magazines equal the original total.
            // E.g. 4 magazines of 30 = 120 bullets → ceil(120 / 14) = 9 magazines of 14 = 126 bullets.
            // This ensures the player is NOT penalized in total ammo count.
            currentMagazineCount = CurrentWeapon.StartingMagazineCount;
            totalBullets = currentMagazineCount * originalSize;
        }
        int newMagazineCount = Math.Max(1, (int)Math.Ceiling((double)totalBullets / reducedSize));

        LogToFile($"[Player.AutoReload] Reducing magazine size: {originalSize} -> {reducedSize}, magazines: {currentMagazineCount} -> {newMagazineCount} (total bullets preserved: {totalBullets})");

        // Reinitialize magazines with the reduced size and adjusted count.
        CurrentWeapon.ReinitializeMagazines(newMagazineCount, reducedSize);

        // For the Revolver: update CylinderSize so the cylinder HUD and _chamberOccupied
        // reflect the new reduced capacity. The revolver has a dedicated method for this.
        if (isRevolver)
        {
            CurrentWeapon.Set("CylinderSize", reducedSize);
            // Call ReinitializeCylinder on the revolver to rebuild _chamberOccupied
            // with the new size (just setting CylinderSize doesn't resize the array).
            if (CurrentWeapon.HasMethod("ReinitializeCylinder"))
            {
                CurrentWeapon.Call("ReinitializeCylinder");
            }
            LogToFile($"[Player.AutoReload] Revolver CylinderSize updated to {reducedSize}, cylinder reinitialized");
        }

        // Issue #1105: For the Shotgun, also reduce TubeMagazineCapacity and trim ShellsInTube.
        // ReinitializeMagazines only affects the MagazineInventory (reserve shells); the tube
        // is tracked separately via ShellsInTube/TubeMagazineCapacity. Without this update,
        // the kill handler compares ShellsInTube=8 against magazineCapacity=3 and always
        // concludes "tube already full", never triggering the auto-reload refill.
        if (CurrentWeapon is Shotgun shotgunForAutoReload)
        {
            shotgunForAutoReload.SetAutoReloadTubeCapacity(reducedSize);
            LogToFile($"[Player.AutoReload] Shotgun TubeMagazineCapacity updated to {reducedSize}");
        }
    }

    /// <summary>
    /// Scans the scene for enemies and connects to their Died signal so that each
    /// kill triggers a magazine refill.
    /// </summary>
    private void ConnectAutoReloadToEnemies()
    {
        // Enemies are parented under Environment/Enemies in level scenes.
        // We search from the current scene root for all nodes in the "enemies" group.
        var tree = GetTree();
        if (tree == null)
        {
            LogToFile("[Player.AutoReload] No scene tree available — cannot connect to enemy signals");
            return;
        }

        var enemies = tree.GetNodesInGroup("enemies");
        int connected = 0;
        foreach (Node enemy in enemies)
        {
            if (enemy.HasSignal("died"))
            {
                // Avoid double-connecting if already connected
                if (!enemy.IsConnected("died", Callable.From(OnEnemyKilledForAutoReload)))
                {
                    enemy.Connect("died", Callable.From(OnEnemyKilledForAutoReload));
                    connected++;
                }
            }
        }

        LogToFile($"[Player.AutoReload] Connected to {connected} enemies' died signals");
    }

    /// <summary>
    /// Called when an enemy dies while auto-reload is active.
    /// Refills the current magazine from reserve ammo (up to magazine capacity).
    /// </summary>
    private void OnEnemyKilledForAutoReload()
    {
        if (!_autoReloadActive || CurrentWeapon == null)
        {
            return;
        }

        // Use the cached reduced magazine size — NOT WeaponData.MagazineSize which is the
        // original unreduced value and would cause the magazine to overflow its actual capacity.
        int magazineCapacity = _autoReloadMagazineSize;
        if (magazineCapacity <= 0)
        {
            LogToFile("[Player.AutoReload] Kill — reduced magazine size not cached, skipping refill");
            return;
        }

        // Issue #1105: Shotgun uses ShellsInTube as its active ammo count; CurrentAmmo is
        // always 0 (an unused placeholder in its MagazineInventory). Use the dedicated
        // AutoRefillTube() method to top up the tube from the reserve.
        if (CurrentWeapon is Shotgun shotgun)
        {
            int shellsInTube = shotgun.ShellsInTube;
            int needed = magazineCapacity - shellsInTube;
            if (needed <= 0)
            {
                LogToFile($"[Player.AutoReload] Kill — shotgun tube already full ({shellsInTube}/{magazineCapacity}), no refill needed");
                return;
            }
            if (shotgun.ReserveAmmo <= 0)
            {
                LogToFile("[Player.AutoReload] Kill — no reserve shells left to refill shotgun tube");
                return;
            }
            int shellsToAdd = Math.Min(needed, shotgun.ReserveAmmo);
            int added = shotgun.AutoRefillTube(shellsToAdd);
            LogToFile($"[Player.AutoReload] Kill — refilled {added} shells ({shellsInTube} -> {shotgun.ShellsInTube}/{magazineCapacity}), reserve: {shotgun.ReserveAmmo}");
            return;
        }

        int currentAmmo = CurrentWeapon.CurrentAmmo;
        int ammoNeeded = magazineCapacity - currentAmmo;

        if (ammoNeeded <= 0)
        {
            LogToFile("[Player.AutoReload] Kill — magazine already full, no refill needed");
            return;
        }

        int reserve = CurrentWeapon.ReserveAmmo;
        if (reserve <= 0)
        {
            LogToFile("[Player.AutoReload] Kill — no reserve ammo left to refill");
            return;
        }

        // Transfer exactly as many bullets as needed (capped by available reserve) from
        // reserve magazines into the current magazine. This is a pure transfer: the amount
        // added to the current magazine equals the amount removed from the reserve, so total
        // ammo is conserved (no ammo is created or destroyed).
        int toAdd = Math.Min(ammoNeeded, reserve);
        CurrentWeapon.CurrentAmmo = currentAmmo + toAdd;
        // Remove the transferred rounds from the reserve magazines.
        CurrentWeapon.ConsumeReserveAmmo(toAdd);

        // For the Revolver: rebuild _chamberOccupied to reflect the newly loaded rounds
        // and emit CylinderStateChanged so the HUD repaints.
        // Setting CurrentAmmo only updates the magazine inventory; the revolver's per-chamber
        // tracking array (_chamberOccupied) must be rebuilt via ReinitializeCylinder.
        if (CurrentWeapon.HasSignal("CylinderStateChanged"))
        {
            if (CurrentWeapon.HasMethod("ReinitializeCylinder"))
            {
                CurrentWeapon.Call("ReinitializeCylinder");
            }
            CurrentWeapon.EmitSignal("CylinderStateChanged");
        }

        LogToFile($"[Player.AutoReload] Kill — refilled {toAdd} rounds ({currentAmmo} -> {CurrentWeapon.CurrentAmmo}/{magazineCapacity}), reserve: {CurrentWeapon.ReserveAmmo}");
    }

    #endregion

    #region Breaching Charges Methods (Issue #1043)

    /// <summary>
    /// Initialize breaching charges if the ActiveItemManager has them selected (Issue #1043).
    /// Loads and instantiates the GDScript breaching_charges_effect.gd controller.
    /// </summary>
    private void InitBreachingCharges()
    {
        LogToFile("[Player.BreachingCharges] Checking breaching charges...");
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.BreachingCharges] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_breaching_charges"))
        {
            LogToFile("[Player.BreachingCharges] ActiveItemManager missing has_breaching_charges method");
            return;
        }

        bool hasBreachingCharges = (bool)activeItemManager.Call("has_breaching_charges");
        if (!hasBreachingCharges)
        {
            LogToFile("[Player.BreachingCharges] No breaching charges selected in ActiveItemManager");
            return;
        }

        LogToFile("[Player.BreachingCharges] Breaching charges selected, initializing...");

        // Load and instantiate the GDScript effect controller
        var effectScript = GD.Load<Script>("res://scripts/effects/breaching_charges_effect.gd");
        if (effectScript == null)
        {
            LogToFile("[Player.BreachingCharges] WARNING: Failed to load breaching_charges_effect.gd");
            return;
        }

        _breachingChargesEffect = new Node();
        _breachingChargesEffect.SetScript(effectScript);
        _breachingChargesEffect.Name = "BreachingChargesEffect";
        AddChild(_breachingChargesEffect);

        // Initialize with player reference
        _breachingChargesEffect.Call("initialize", this);

        _breachingChargesEquipped = true;
        int charges = (int)_breachingChargesEffect.Call("get_charges");
        LogToFile($"[Player.BreachingCharges] Breaching charges equipped, charges: {charges}");
    }

    /// <summary>
    /// Handle breaching charges input:
    /// - Hold Space near a wall and release → place a charge
    /// - Press Space when a charge is placed → detonate
    /// </summary>
    private void HandleBreachingChargesInput()
    {
        if (!_breachingChargesEquipped || _breachingChargesEffect == null)
        {
            return;
        }

        if (!IsInstanceValid(_breachingChargesEffect))
        {
            return;
        }

        // If a charge is placed, press Space to detonate
        bool hasPlacedCharge = (bool)_breachingChargesEffect.Get("has_placed_charge");
        if (hasPlacedCharge)
        {
            if (Input.IsActionJustPressed("flashlight_toggle"))
            {
                // Issue #1036: Block active item use when jammed by a Radio Jammer enemy
                if (IsActiveItemJammedVerbose())
                {
                    LogToFile("[Player.BreachingCharges] Space blocked by Radio Jammer (Issue #1036)");
                    return;
                }

                bool detonated = (bool)_breachingChargesEffect.Call("detonate");
                if (detonated)
                {
                    LogToFile("[Player.BreachingCharges] Charge detonated");
                }
            }
            return;
        }

        // No charge placed yet: hold Space near a wall, release to place
        if (Input.IsActionJustReleased("flashlight_toggle") && _breachingHoldingForPlacement)
        {
            _breachingHoldingForPlacement = false;
            // Notify effect: no longer holding (hides in-hand sprite)
            _breachingChargesEffect.Call("set_holding_for_placement", false);
            bool placed = (bool)_breachingChargesEffect.Call("try_place_charge");
            if (placed)
            {
                LogToFile("[Player.BreachingCharges] Charge placed");
            }
        }
        else if (Input.IsActionPressed("flashlight_toggle"))
        {
            // Issue #1036: Block active item use when jammed by a Radio Jammer enemy
            // Use silent check (hold action fires every frame — verbose would flood the log)
            if (IsActiveItemJammedSilent())
            {
                return;
            }

            int charges = (int)_breachingChargesEffect.Call("get_charges");
            if (charges > 0 && !_breachingHoldingForPlacement)
            {
                _breachingHoldingForPlacement = true;
                // Notify effect: started holding (shows in-hand sprite)
                _breachingChargesEffect.Call("set_holding_for_placement", true);
            }
        }
        else if (Input.IsActionJustReleased("flashlight_toggle"))
        {
            if (_breachingHoldingForPlacement)
            {
                _breachingHoldingForPlacement = false;
                // Notify effect: released without placing (hides in-hand sprite)
                _breachingChargesEffect.Call("set_holding_for_placement", false);
            }
        }
    }

    #endregion

    #region Armored Skin System (Issue #1045)

    /// <summary>
    /// Whether armored skin is active (passive item, Issue #1045).
    /// When true, 20 glass/crystal shards will be spawned when player is at ≤2 HP and hit.
    /// </summary>
    private bool _armoredSkinActive = false;

    /// <summary>
    /// Overlay sprites added by ApplyArmoredSkinVisual (Issue #1142).
    /// Stored so they can be freed when the armor shatters.
    /// </summary>
    private readonly System.Collections.Generic.List<Sprite2D> _armoredSkinOverlays = new();

    /// <summary>
    /// Whether armored skin post-trigger immunity is active (Issue #1095).
    /// Set to true when shards are spawned; cleared after 0.1 seconds.
    /// Absorbs all subsequent damage calls from the same multi-hit explosion event
    /// (e.g., GrenadeTimer calls on_hit_with_info 99 times in a loop — only the first
    /// triggers shards, but all remaining calls must also be absorbed).
    /// </summary>
    private bool _armoredSkinImmune = false;

    /// <summary>
    /// Path to the ArmoredSkinShard scene.
    /// </summary>
    private const string ArmoredSkinShardScenePath = "res://scenes/projectiles/ArmoredSkinShard.tscn";

    /// <summary>
    /// Number of shards to spawn on trigger.
    /// </summary>
    private const int ArmoredSkinShardCount = 20;

    /// <summary>
    /// Initialize armored skin if the ActiveItemManager has it selected (Issue #1045).
    /// Armored skin is a passive item — no special nodes needed,
    /// just a flag that triggers shard spawning at low HP.
    /// </summary>
    private void InitArmoredSkin()
    {
        LogToFile("[Player.ArmoredSkin] Checking armored skin...");

        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.ArmoredSkin] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_armored_skin"))
        {
            LogToFile("[Player.ArmoredSkin] ActiveItemManager missing has_armored_skin method");
            return;
        }

        bool hasArmoredSkin = (bool)activeItemManager.Call("has_armored_skin");
        if (!hasArmoredSkin)
        {
            LogToFile("[Player.ArmoredSkin] No armored skin selected in ActiveItemManager");
            return;
        }

        _armoredSkinActive = true;
        LogToFile("[Player.ArmoredSkin] Armored skin active — shards will spawn when HP ≤2 and hit");
    }

    /// <summary>
    /// Apply a passive visual effect to the player based on the currently equipped active item (Issue #1142).
    /// This is the single entry point for all item-specific player visuals.
    /// Add a new case here when a future item needs a visual effect.
    /// Called once from Ready() after all Init*() functions have run.
    /// </summary>
    private void ApplyItemVisual()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            return;
        }

        int itemType = (int)activeItemManager.Get("current_active_item");

        // Check for ARMORED_SKIN — crystal/glass armor overlay (Issue #1142).
        if (activeItemManager.HasMethod("has_armored_skin") && (bool)activeItemManager.Call("has_armored_skin"))
        {
            ApplyArmoredSkinVisual();
        }

        LogToFile($"[Player.ItemVisual] Visual applied for item type: {itemType}");
    }

    /// <summary>
    /// Apply crystal armor overlay sprites on top of each player body part (Issue #1142).
    /// Like The Binding of Isaac — a semi-transparent blue crystal overlay is added as a
    /// child of each base sprite so it automatically follows all movements, flips, and
    /// animations. Alpha is kept low so the player is clearly visible underneath.
    /// </summary>
    private void ApplyArmoredSkinVisual()
    {
        if (_playerModel == null)
        {
            LogToFile("[Player.ArmoredSkin] WARNING: _playerModel is null, skipping visual");
            return;
        }

        // Map each body-part Sprite2D name to its crystal overlay texture path.
        var overlayMap = new System.Collections.Generic.Dictionary<string, string>
        {
            { "Body",     "res://assets/sprites/characters/player/armored_skin/armored_skin_body.png" },
            { "Head",     "res://assets/sprites/characters/player/armored_skin/armored_skin_head.png" },
            { "LeftArm",  "res://assets/sprites/characters/player/armored_skin/armored_skin_left_arm.png" },
            { "RightArm", "res://assets/sprites/characters/player/armored_skin/armored_skin_right_arm.png" },
            { "Armband",  "res://assets/sprites/characters/player/armored_skin/armored_skin_armband.png" },
        };

        // 40% opacity — crystal armor is clearly visible while the player sprite underneath remains readable.
        var overlayColor = new Color(1f, 1f, 1f, 0.4f);

        int addedCount = 0;
        foreach (var child in _playerModel.GetChildren())
        {
            if (child is not Sprite2D baseSprite)
                continue;

            string partName = baseSprite.Name;
            if (!overlayMap.TryGetValue(partName, out string? overlayPath))
                continue;

            if (!ResourceLoader.Exists(overlayPath))
            {
                LogToFile($"[Player.ArmoredSkin] WARNING: Overlay texture not found: {overlayPath}");
                continue;
            }

            var texture = GD.Load<Texture2D>(overlayPath);
            if (texture == null)
            {
                LogToFile($"[Player.ArmoredSkin] WARNING: Failed to load overlay texture: {overlayPath}");
                continue;
            }

            // Parent the overlay directly to the base sprite so it inherits all transforms
            // (position, rotation, flip, scale) — the overlay moves exactly with the body part.
            var overlay = new Sprite2D();
            overlay.Name = $"{partName}ArmorOverlay";
            overlay.Texture = texture;
            overlay.Position = Vector2.Zero;
            overlay.Offset = Vector2.Zero;
            overlay.ZIndex = 1;
            overlay.Modulate = overlayColor;

            baseSprite.AddChild(overlay);
            _armoredSkinOverlays.Add(overlay);
            addedCount++;
        }

        LogToFile($"[Player.ArmoredSkin] Crystal armor overlays added: {addedCount} sprites");
    }

    /// <summary>
    /// Remove all crystal armor overlay sprites (Issue #1142).
    /// Called when the armor shatters so the visual matches the gameplay state.
    /// </summary>
    private void RemoveArmoredSkinVisual()
    {
        foreach (var overlay in _armoredSkinOverlays)
        {
            if (IsInstanceValid(overlay))
                overlay.QueueFree();
        }
        _armoredSkinOverlays.Clear();
        LogToFile("[Player.ArmoredSkin] Crystal armor overlays removed");
    }

    /// <summary>
    /// Spawn 20 glass/crystal shards in all directions from the player position (Issue #1045).
    /// Called when armored skin is active and player is at ≤2 HP while being hit.
    /// </summary>
    private void SpawnArmoredSkinShards()
    {
        if (!ResourceLoader.Exists(ArmoredSkinShardScenePath))
        {
            LogToFile($"[Player.ArmoredSkin] WARNING: Shard scene not found: {ArmoredSkinShardScenePath}");
            return;
        }

        var shardScene = GD.Load<PackedScene>(ArmoredSkinShardScenePath);
        if (shardScene == null)
        {
            LogToFile("[Player.ArmoredSkin] WARNING: Failed to load shard scene");
            return;
        }

        var parent = GetParent();
        if (parent == null)
        {
            return;
        }

        // Remove the crystal overlay sprites so the visual matches the gameplay state.
        RemoveArmoredSkinVisual();

        LogToFile($"[Player.ArmoredSkin] Spawning {ArmoredSkinShardCount} glass shards (HP: {HealthComponent?.CurrentHealth ?? 0})");

        for (int i = 0; i < ArmoredSkinShardCount; i++)
        {
            var shard = shardScene.Instantiate<Node2D>();

            // Set direction and source_id before add_child so _ready() uses the correct values
            float baseAngle = ((float)i / ArmoredSkinShardCount) * Mathf.Tau;
            float angleDeviation = (float)GD.RandRange(-Mathf.Pi / ArmoredSkinShardCount, Mathf.Pi / ArmoredSkinShardCount);
            float angle = baseAngle + angleDeviation;
            shard.Set("direction", new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)).Normalized());
            shard.Set("source_id", GetInstanceId());

            parent.AddChild(shard);
            shard.GlobalPosition = GlobalPosition;
        }
    }

    #endregion

    #region Loudspeaker Methods (Issue #959)

    /// <summary>
    /// Initialize the loudspeaker if the ActiveItemManager has it selected (Issue #959).
    /// Loads and instantiates the GDScript loudspeaker_progress and loudspeaker_cone_effect controllers.
    /// </summary>
    private void InitLoudspeaker()
    {
        LogToFile("[Player.Loudspeaker] Checking loudspeaker...");
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.Loudspeaker] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_loudspeaker"))
        {
            LogToFile("[Player.Loudspeaker] ActiveItemManager missing has_loudspeaker method");
            return;
        }

        bool hasLoudspeaker = (bool)activeItemManager.Call("has_loudspeaker");
        if (!hasLoudspeaker)
        {
            LogToFile("[Player.Loudspeaker] No loudspeaker selected in ActiveItemManager");
            return;
        }

        LogToFile("[Player.Loudspeaker] Loudspeaker selected, initializing...");

        // Use the singleton LoudspeakerProgress from ActiveItemManager so progress persists
        // across scene reloads and respawns (Issue #959 — Bug 1 fix for C# path).
        var progressNode = activeItemManager.Get("loudspeaker_progress").AsGodotObject() as Node;
        if (progressNode == null)
        {
            LogToFile("[Player.Loudspeaker] WARNING: loudspeaker_progress singleton not found in ActiveItemManager");
            return;
        }
        _loudspeakerProgress = progressNode;

        // Load and instantiate the cone visual effect
        var coneScript = GD.Load<Script>("res://scripts/effects/loudspeaker_cone_effect.gd");
        if (coneScript == null)
        {
            LogToFile("[Player.Loudspeaker] WARNING: Failed to load loudspeaker_cone_effect.gd");
            return;
        }

        _loudspeakerConeEffect = new Node2D();
        _loudspeakerConeEffect.SetScript(coneScript);
        _loudspeakerConeEffect.Name = "LoudspeakerConeEffect";
        _loudspeakerConeEffect.ZIndex = 1;
        AddChild(_loudspeakerConeEffect);
        _loudspeakerConeEffect.Call("initialize", this);

        _loudspeakerEquipped = true;

        // Reset per-run state (charges/cooldown/all_charges_used) on respawn.
        // Do NOT call reset_for_new_level here — used_this_level must persist across
        // deaths on the same map so the 100%/1-enemy first-use mechanic fires only once
        // per level visit (Issue #959 — Bug 6 fix for C# path).
        _loudspeakerProgress.Call("reset_for_respawn");

        // Create in-hand sprite shown during activation
        const string LoudspeakerTexturePath = "res://assets/sprites/weapons/loudspeaker_icon.png";
        if (ResourceLoader.Exists(LoudspeakerTexturePath))
        {
            _loudspeakerHandSprite = new Sprite2D();
            _loudspeakerHandSprite.Texture = GD.Load<Texture2D>(LoudspeakerTexturePath);
            _loudspeakerHandSprite.Name = "LoudspeakerHandSprite";
            _loudspeakerHandSprite.Visible = false;
            _loudspeakerHandSprite.Scale = new Vector2(0.6f, 0.6f);
            _loudspeakerHandSprite.Position = new Vector2(10, 0);
            _loudspeakerHandSprite.ZIndex = 2;

            if (_weaponMount != null)
                _weaponMount.AddChild(_loudspeakerHandSprite);
            else
                AddChild(_loudspeakerHandSprite);
        }

        int maxCharges = (int)_loudspeakerProgress.Call("get_max_charges");
        int currentCharges = (int)_loudspeakerProgress.Get("charges_remaining");
        int currentLevel = (int)_loudspeakerProgress.Get("current_level");
        float effectChancePct = (float)_loudspeakerProgress.Call("get_effect_chance") * 100.0f;
        bool usedThisLevelLog = (bool)_loudspeakerProgress.Get("used_this_level");
        bool allChargesUsedLog = (bool)_loudspeakerProgress.Get("all_charges_used_this_level");
        LogToFile($"[Player.Loudspeaker] Loudspeaker equipped, level: {currentLevel}, charges: {currentCharges}/{(maxCharges != -1 ? maxCharges.ToString() : "unlimited")}, effect: {effectChancePct:F0}%, used_this_level: {usedThisLevelLog}, all_charges_used: {allChargesUsedLog}");

        // Apply level start states for levels 6 and 7 (Issue #959)
        bool shouldStartWithPacifists = (bool)_loudspeakerProgress.Call("should_start_with_pacifists");
        bool isVictoryState = (bool)_loudspeakerProgress.Call("is_victory_state");
        if (shouldStartWithPacifists || isVictoryState)
            CallDeferred(MethodName.ApplyLoudspeakerLevelStartState);
    }

    /// <summary>
    /// Apply loudspeaker level start state for levels 6 and 7 (Issue #959).
    /// Level 6: 50% of enemies start as pacifists; 1 random enemy is immune.
    /// Level 7: ALL enemies start as pacifists; show victory message.
    /// Called deferred from InitLoudspeaker so all enemy nodes are ready.
    /// </summary>
    private void ApplyLoudspeakerLevelStartState()
    {
        if (_loudspeakerProgress == null)
            return;

        var enemies = GetTree().GetNodesInGroup("enemies");
        if (enemies.Count == 0)
            return;

        bool isVictoryState = (bool)_loudspeakerProgress.Call("is_victory_state");
        if (isVictoryState)
        {
            // Level 7: ALL enemies become pacifists
            LogToFile("[Player.Loudspeaker] Level 7 victory state — all enemies start as pacifists!");
            foreach (var enemy in enemies)
            {
                if (enemy is Node enemyNode && enemyNode.HasMethod("apply_pacifism") && enemyNode.HasMethod("is_alive"))
                {
                    bool isAlive = (bool)enemyNode.Call("is_alive");
                    if (isAlive)
                        enemyNode.Call("apply_pacifism", 0.0f);
                }
            }
            ShowLoudspeakerVictoryMessage();
            return;
        }

        bool shouldStartWithPacifists = (bool)_loudspeakerProgress.Call("should_start_with_pacifists");
        if (!shouldStartWithPacifists)
            return;

        // Level 6: 50% enemies start as pacifists; designate 1 as immune
        var aliveEnemies = new Godot.Collections.Array<Node>();
        foreach (var enemy in enemies)
        {
            if (enemy is Node enemyNode && enemyNode.HasMethod("is_alive"))
            {
                bool isAlive = (bool)enemyNode.Call("is_alive");
                if (isAlive)
                    aliveEnemies.Add(enemyNode);
            }
        }

        // Pick 1 random immune enemy first (before pacifying others)
        bool hasImmuneEnemy = (bool)_loudspeakerProgress.Call("has_immune_enemy");
        if (aliveEnemies.Count > 0 && hasImmuneEnemy)
        {
            int immuneIdx = GD.RandRange(0, aliveEnemies.Count - 1);
            var immuneEnemy = aliveEnemies[immuneIdx];
            if (immuneEnemy.HasMethod("set_immune_to_pacifism"))
            {
                immuneEnemy.Call("set_immune_to_pacifism", true);
                var posStr = immuneEnemy is Node2D n2d ? n2d.GlobalPosition.ToString() : "?";
                LogToFile($"[Player.Loudspeaker] Level 6: enemy at {posStr} is immune to pacifism");
            }
            aliveEnemies.RemoveAt(immuneIdx);
        }

        // Pacify 50% of remaining enemies
        aliveEnemies.Shuffle();
        int pacifyCount = (int)(aliveEnemies.Count * 0.5f);
        int pacified = 0;
        for (int i = 0; i < pacifyCount; i++)
        {
            var enemy = aliveEnemies[i];
            if (enemy.HasMethod("apply_pacifism"))
            {
                enemy.Call("apply_pacifism", 0.0f);
                pacified++;
            }
        }
        LogToFile($"[Player.Loudspeaker] Level 6: {pacified}/{aliveEnemies.Count + 1} enemies start as pacifists");
    }

    /// <summary>
    /// Show the victory message for Level 7 (all enemies defeated via pacifism) (Issue #959).
    /// </summary>
    private void ShowLoudspeakerVictoryMessage()
    {
        var canvas = new CanvasLayer();
        canvas.Name = "LoudspeakerVictoryCanvas";
        canvas.Layer = 100;
        AddChild(canvas);

        // Victory message label
        var label = new Label();
        label.Text = "Нам нечего делить по этому мы не будем стрелять друг в друга.";
        label.AddThemeFontSizeOverride("font_size", 36);
        label.HorizontalAlignment = HorizontalAlignment.Center;
        label.VerticalAlignment = VerticalAlignment.Center;
        label.AutowrapMode = TextServer.AutowrapMode.WordSmart;
        label.SetAnchor(Side.Left, 0.0f);
        label.SetAnchor(Side.Right, 1.0f);
        label.SetAnchor(Side.Top, 0.3f);
        label.SetAnchor(Side.Bottom, 0.7f);
        canvas.AddChild(label);

        // "Click to continue" hint
        var hint = new Label();
        hint.Text = "[ нажмите, чтобы продолжить ]";
        hint.AddThemeFontSizeOverride("font_size", 18);
        hint.AddThemeColorOverride("font_color", new Color(0.8f, 0.8f, 0.8f, 0.8f));
        hint.HorizontalAlignment = HorizontalAlignment.Center;
        hint.VerticalAlignment = VerticalAlignment.Center;
        hint.SetAnchor(Side.Left, 0.0f);
        hint.SetAnchor(Side.Right, 1.0f);
        hint.SetAnchor(Side.Top, 0.65f);
        hint.SetAnchor(Side.Bottom, 0.75f);
        canvas.AddChild(hint);

        // Invisible click-catcher panel
        var panel = new ColorRect();
        panel.Color = new Color(0, 0, 0, 0);
        panel.SetAnchor(Side.Left, 0.0f);
        panel.SetAnchor(Side.Right, 1.0f);
        panel.SetAnchor(Side.Top, 0.0f);
        panel.SetAnchor(Side.Bottom, 1.0f);
        panel.MouseFilter = Control.MouseFilterEnum.Stop;
        panel.GuiInput += (InputEvent ev) =>
        {
            if (ev is InputEventMouseButton mb && mb.Pressed)
                ShowLoudspeakerEndScreen(canvas);
        };
        canvas.AddChild(panel);

        LogToFile("[Player.Loudspeaker] Victory message shown (Level 7)");
    }

    /// <summary>
    /// Show end screen after player clicks on victory message (Issue #959).
    /// </summary>
    private void ShowLoudspeakerEndScreen(CanvasLayer victoryCanvas)
    {
        // Remove victory screen
        if (Godot.GodotObject.IsInstanceValid(victoryCanvas))
            victoryCanvas.QueueFree();

        // Create end screen canvas
        var canvas = new CanvasLayer();
        canvas.Name = "LoudspeakerEndCanvas";
        canvas.Layer = 101;
        AddChild(canvas);

        // Black background
        var bg = new ColorRect();
        bg.Color = new Color(0, 0, 0, 1);
        bg.SetAnchor(Side.Left, 0.0f);
        bg.SetAnchor(Side.Right, 1.0f);
        bg.SetAnchor(Side.Top, 0.0f);
        bg.SetAnchor(Side.Bottom, 1.0f);
        canvas.AddChild(bg);

        // "Конец" title
        var title = new Label();
        title.Text = "Конец";
        title.AddThemeFontSizeOverride("font_size", 72);
        title.AddThemeColorOverride("font_color", new Color(1, 1, 1, 1));
        title.HorizontalAlignment = HorizontalAlignment.Center;
        title.VerticalAlignment = VerticalAlignment.Center;
        title.SetAnchor(Side.Left, 0.0f);
        title.SetAnchor(Side.Right, 1.0f);
        title.SetAnchor(Side.Top, 0.2f);
        title.SetAnchor(Side.Bottom, 0.45f);
        canvas.AddChild(title);

        // Thank you message
        var thanks = new Label();
        thanks.Text = "Спасибо за игру!";
        thanks.AddThemeFontSizeOverride("font_size", 32);
        thanks.AddThemeColorOverride("font_color", new Color(0.85f, 0.85f, 0.85f, 1));
        thanks.HorizontalAlignment = HorizontalAlignment.Center;
        thanks.VerticalAlignment = VerticalAlignment.Center;
        thanks.SetAnchor(Side.Left, 0.0f);
        thanks.SetAnchor(Side.Right, 1.0f);
        thanks.SetAnchor(Side.Top, 0.5f);
        thanks.SetAnchor(Side.Bottom, 0.7f);
        canvas.AddChild(thanks);

        LogToFile("[Player.Loudspeaker] End screen shown (Level 7)");
    }

    /// <summary>
    /// Handle loudspeaker input and hold-timer each frame (Issue #959).
    /// Press Space to emit a sound cone that pacifies nearby enemies.
    /// </summary>
    private void HandleLoudspeakerInput(float delta)
    {
        if (!_loudspeakerEquipped || _loudspeakerProgress == null)
            return;

        // Update cooldown timer every frame
        _loudspeakerProgress.Call("update", (double)delta);

        // Update in-hand sprite hold timer
        if (_loudspeakerHoldTimer > 0.0f)
        {
            _loudspeakerHoldTimer -= delta;
            if (_loudspeakerHoldTimer <= 0.0f)
            {
                _loudspeakerHoldTimer = 0.0f;
                // Restore weapon visibility and hide loudspeaker sprite
                if (_weaponMount != null)
                {
                    foreach (Node child in _weaponMount.GetChildren())
                    {
                        if (child != _loudspeakerHandSprite && child is CanvasItem canvasItem)
                            canvasItem.Visible = true;
                    }
                }
                if (_loudspeakerHandSprite != null && IsInstanceValid(_loudspeakerHandSprite))
                    _loudspeakerHandSprite.Visible = false;
            }
        }

        if (!Input.IsActionJustPressed("flashlight_toggle"))
            return;

        // Issue #1036: Block active item use when jammed by a Radio Jammer enemy
        if (IsActiveItemJammedVerbose())
        {
            LogToFile("[Player.Loudspeaker] Space blocked by Radio Jammer (Issue #1036)");
            return;
        }

        bool canActivate = (bool)_loudspeakerProgress.Call("can_activate");
        if (!canActivate)
        {
            LogToFile("[Player.Loudspeaker] Cannot activate: no charges or cooldown active");
            return;
        }

        // Determine if this is the first use before consuming the charge
        bool usedThisLevel = (bool)_loudspeakerProgress.Get("used_this_level");
        bool isFirstUse = !usedThisLevel;

        // Consume charge / start cooldown
        _loudspeakerProgress.Call("use");

        // Get aim direction (toward mouse cursor)
        Vector2 aimDir = LoudspeakerGetAimDirection();

        // Show loudspeaker in player's hands: hide weapon, show loudspeaker sprite
        if (_loudspeakerHandSprite != null && IsInstanceValid(_loudspeakerHandSprite))
        {
            _loudspeakerHandSprite.Visible = true;
            if (_weaponMount != null)
            {
                foreach (Node child in _weaponMount.GetChildren())
                {
                    if (child != _loudspeakerHandSprite && child is CanvasItem canvasItem)
                        canvasItem.Visible = false;
                }
            }
            _loudspeakerHoldTimer = LoudspeakerHoldDuration;
        }

        // Show the cone visual effect
        if (_loudspeakerConeEffect != null && IsInstanceValid(_loudspeakerConeEffect))
            _loudspeakerConeEffect.Call("play", aimDir);

        // Effect chance: first use at level 1 is always 100% with max 1 enemy pacified.
        // At level 2+ the regular chance applies even on first use (Issue #959 — Bug 4/5 fix).
        int currentLevelForEffect = (int)_loudspeakerProgress.Get("current_level");
        bool isLevel1FirstUse = isFirstUse && currentLevelForEffect == 1;
        float effectChance = isLevel1FirstUse ? 1.0f : (float)_loudspeakerProgress.Call("get_effect_chance");
        int maxPacify = isLevel1FirstUse ? 1 : int.MaxValue;

        // Notify all enemies on the map that a loud sound was made
        LoudspeakerAlertAllEnemies();

        // Apply pacifism effect to enemies in the cone sector
        float hostilityChance = (float)_loudspeakerProgress.Call("get_hostility_chance");
        LoudspeakerApplyEffect(aimDir, effectChance, hostilityChance, maxPacify);

        int maxCharges = (int)_loudspeakerProgress.Call("get_max_charges");
        int currentCharges = (int)_loudspeakerProgress.Get("charges_remaining");
        LogToFile($"[Player.Loudspeaker] Activated! Direction: {aimDir}, Effect chance: {effectChance * 100.0f:F0}%, Charges: {currentCharges}/{(maxCharges != -1 ? maxCharges.ToString() : "∞")}");
    }

    /// <summary>
    /// Returns the current aim direction (toward mouse cursor).
    /// </summary>
    private Vector2 LoudspeakerGetAimDirection()
    {
        var mousePos = GetGlobalMousePosition();
        var diff = mousePos - GlobalPosition;
        if (diff.Length() > 1.0f)
            return diff.Normalized();
        if (Velocity.Length() > 1.0f)
            return Velocity.Normalized();
        return Vector2.Right;
    }

    /// <summary>
    /// Alert all enemies on the map that the loudspeaker was used (Issue #959).
    /// Per spec: all enemies on the whole map hear the player when this item is used.
    /// </summary>
    private void LoudspeakerAlertAllEnemies()
    {
        var enemies = GetTree().GetNodesInGroup("enemies");
        int alerted = 0;
        foreach (var enemy in enemies)
        {
            if (enemy.HasMethod("alert_from_loudspeaker"))
            {
                enemy.Call("alert_from_loudspeaker", GlobalPosition);
                alerted++;
            }
            else if (enemy.HasMethod("alert"))
            {
                enemy.Call("alert", GlobalPosition);
                alerted++;
            }
        }
        LogToFile($"[Player.Loudspeaker] Alerted {alerted} enemies");
    }

    /// <summary>
    /// Apply the loudspeaker pacifism effect to enemies in the cone sector (Issue #959, Stage 5).
    /// Rules: 50° half-angle cone, line-of-sight check, cover-within-500px exception,
    /// only unattacked enemies, effect_chance roll, hostility_chance roll per enemy.
    /// </summary>
    private void LoudspeakerApplyEffect(Vector2 direction, float effectChance, float hostilityChance, int maxPacify = int.MaxValue)
    {
        const float ConeHalfAngle = 0.872664625997f; // 50 degrees in radians
        const float CoverMaxDistance = 500.0f;
        const int WallMask = 4; // Physics layer for walls

        var enemies = GetTree().GetNodesInGroup("enemies");
        int pacifiedCount = 0;
        var spaceState = GetWorld2D().DirectSpaceState;

        foreach (var enemy in enemies)
        {
            if (pacifiedCount >= maxPacify)
                break;

            if (!enemy.HasMethod("apply_pacifism"))
                continue;
            if (!enemy.HasMethod("is_alive") || !(bool)enemy.Call("is_alive"))
                continue;
            if (enemy.HasMethod("is_pacifist") && (bool)enemy.Call("is_pacifist"))
                continue; // Already pacifist
            if (enemy.HasMethod("was_attacked_by_player") && (bool)enemy.Call("was_attacked_by_player"))
                continue; // Only unattacked enemies can be pacified

            var enemyNode2D = (Node2D)enemy;
            var toEnemy = enemyNode2D.GlobalPosition - GlobalPosition;
            float dist = toEnemy.Length();
            if (dist < 0.1f)
                continue;

            // Check cone angle
            float angleToEnemy = Math.Abs(direction.AngleTo(toEnemy.Normalized()));
            if (angleToEnemy > ConeHalfAngle)
                continue;

            // Line-of-sight check (raycast to enemy)
            var ray = PhysicsRayQueryParameters2D.Create(GlobalPosition, enemyNode2D.GlobalPosition, WallMask);
            ray.Exclude = new Godot.Collections.Array<Rid> { GetRid() };
            var result = spaceState.IntersectRay(ray);
            bool behindWall = result.Count > 0;

            // If behind a wall, skip — unless within 500px (cover rule)
            if (behindWall && dist > CoverMaxDistance)
                continue;

            // Roll effect chance
            if (GD.Randf() > effectChance)
                continue;

            // Apply pacifism
            if ((bool)enemy.Call("apply_pacifism", hostilityChance))
            {
                pacifiedCount++;
                LogToFile($"[Player.Loudspeaker] Pacified enemy at {enemyNode2D.GlobalPosition} (dist={dist:F0}, cover={behindWall})");
            }
        }

        LogToFile($"[Player.Loudspeaker] Effect applied: {pacifiedCount}/{enemies.Count} enemies pacified");
    }

    #endregion

    #region Recoil Compensator System (Issue #1073)

    /// <summary>
    /// Initialize the recoil compensator if the ActiveItemManager has it selected (Issue #1073).
    /// </summary>
    private void InitRecoilCompensator()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.RecoilCompensator] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_recoil_compensator"))
        {
            LogToFile("[Player.RecoilCompensator] ActiveItemManager missing has_recoil_compensator method");
            return;
        }

        bool hasCompensator = (bool)activeItemManager.Call("has_recoil_compensator");
        if (!hasCompensator)
        {
            LogToFile("[Player.RecoilCompensator] Recoil compensator not selected in ActiveItemManager");
            return;
        }

        _recoilCompensatorEquipped = true;
        _recoilCompensatorCharge = RecoilCompensatorMaxCharge;
        _recoilCompensatorActive = false;

        LogToFile($"[Player.RecoilCompensator] Recoil compensator initialized, charge: {_recoilCompensatorCharge:F1} s");
    }

    /// <summary>
    /// Handle recoil compensator input: hold Space to activate, release to deactivate.
    /// While active: eliminates weapon spread and screen shake, boosts fire rate by 10%.
    /// Charge depletes at 1 s/s while active; deactivates automatically when empty.
    /// </summary>
    private void HandleRecoilCompensatorInput(float delta)
    {
        if (!_recoilCompensatorEquipped)
        {
            // Tick the experimental-sample timer even when not normally equipped
            if (_recoilCompensatorExperimentalTimer > 0.0f)
            {
                _recoilCompensatorExperimentalTimer -= delta;
                if (_recoilCompensatorExperimentalTimer <= 0.0f)
                {
                    _recoilCompensatorExperimentalTimer = 0.0f;
                    _recoilCompensatorActive = false;
                    _recoilCompensatorEquipped = false;
                    _recoilCompensatorCharge = 0.0f;
                    QueueRedraw();
                    LogToFile("[Player.RecoilCompensator] Experimental effect expired");
                }
            }
            return;
        }

        // Fire rate boost: accelerate weapon fire timer by 10% while active
        if (_recoilCompensatorActive && CurrentWeapon != null)
        {
            CurrentWeapon.AccelerateFireTimer(delta * 0.1f);
        }

        // If active via experimental sample, tick that timer (ignores hold-key requirement)
        if (_recoilCompensatorExperimentalTimer > 0.0f)
        {
            _recoilCompensatorExperimentalTimer -= delta;
            if (_recoilCompensatorExperimentalTimer <= 0.0f)
            {
                _recoilCompensatorExperimentalTimer = 0.0f;
                _recoilCompensatorActive = false;
                _recoilCompensatorCharge = 0.0f;
                QueueRedraw();
                LogToFile("[Player.RecoilCompensator] Experimental effect expired");
            }
            else
            {
                // Keep active for fire-rate boost; don't consume the normal charge
                if (_recoilCompensatorActive && CurrentWeapon != null)
                    CurrentWeapon.AccelerateFireTimer(delta * 0.1f);
            }
            return;
        }

        if (Input.IsActionPressed("flashlight_toggle") && _recoilCompensatorCharge > 0.0f)
        {
            // Issue #1036: Block active item use when jammed by a Radio Jammer enemy
            // Use silent check (hold action fires every frame — verbose would flood the log)
            if (IsActiveItemJammedSilent())
            {
                if (_recoilCompensatorActive)
                {
                    _recoilCompensatorActive = false;
                    QueueRedraw();
                }
                return;
            }

            // Activate: deplete charge
            if (!_recoilCompensatorActive)
            {
                _recoilCompensatorActive = true;
                LogToFile($"[Player.RecoilCompensator] Activated, charge: {_recoilCompensatorCharge:F2} s");
                QueueRedraw();
            }

            _recoilCompensatorCharge -= delta;
            if (_recoilCompensatorCharge <= 0.0f)
            {
                _recoilCompensatorCharge = 0.0f;
                _recoilCompensatorActive = false;
                LogToFile("[Player.RecoilCompensator] Charge depleted, deactivating");
            }

            QueueRedraw();
        }
        else
        {
            if (_recoilCompensatorActive)
            {
                _recoilCompensatorActive = false;
                LogToFile($"[Player.RecoilCompensator] Deactivated, charge: {_recoilCompensatorCharge:F2} s");
                QueueRedraw();
            }
        }
    }

    /// <summary>
    /// Returns true when the recoil compensator is equipped and currently active (Space held, charge > 0).
    /// Called by weapon scripts to suppress spread and screen shake.
    /// </summary>
    public bool IsRecoilCompensatorActive()
    {
        return _recoilCompensatorEquipped && _recoilCompensatorActive;
    }

    /// <summary>
    /// Draw a continuous timer bar above the player showing remaining compensator charge.
    /// Shown while active and while charge < max (i.e., after first use).
    /// </summary>
    private void DrawRecoilCompensatorBar()
    {
        const float barWidth = 40.0f;
        const float barHeight = 4.0f;
        const float barYOffset = -30.0f;
        const float borderWidth = 1.0f;

        float fillRatio = Mathf.Clamp(_recoilCompensatorCharge / RecoilCompensatorMaxCharge, 0.0f, 1.0f);

        Color bgColor = new Color(0.1f, 0.1f, 0.1f, 0.6f);
        Color borderColor = new Color(0.3f, 0.3f, 0.3f, 0.7f);
        // Active: orange/amber; inactive (charge remaining): dim version
        Color fillColor = _recoilCompensatorActive
            ? new Color(1.0f, 0.6f, 0.0f, 0.95f)
            : new Color(0.6f, 0.4f, 0.0f, 0.6f);

        Rect2 bgRect = new Rect2(-barWidth / 2.0f, barYOffset, barWidth, barHeight);
        DrawRect(bgRect, bgColor);

        if (fillRatio > 0.0f)
        {
            Rect2 fillRect = new Rect2(-barWidth / 2.0f, barYOffset, barWidth * fillRatio, barHeight);
            DrawRect(fillRect, fillColor);
        }

        DrawRect(bgRect, borderColor, false, borderWidth);
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

    // ============================================================================
    // Active Item Pickup Reinitialisation — Issue #1325
    // ============================================================================

    /// <summary>
    /// Connect to ActiveItemManager's active_item_changed signal so that when the player
    /// picks up a new active item in roguelike mode (no scene restart), the player's
    /// item subsystem is immediately initialised (Issue #1325).
    /// </summary>
    private void ConnectActiveItemChangedSignal()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.ItemPickup] ActiveItemManager not found — cannot connect active_item_changed");
            return;
        }

        if (!activeItemManager.HasSignal("active_item_changed"))
        {
            LogToFile("[Player.ItemPickup] ActiveItemManager missing active_item_changed signal");
            return;
        }

        activeItemManager.Connect("active_item_changed", Callable.From<long>(OnActiveItemPickedUp));
        LogToFile("[Player.ItemPickup] Connected to ActiveItemManager.active_item_changed");
    }

    /// <summary>
    /// De-equip all active item subsystems so that only the newly picked-up item is active.
    /// Resets equipped flags and frees child nodes created by Init* methods.
    /// Called before InitX() in OnActiveItemPickedUp to prevent dual-equip when the player
    /// swaps items at the roguelike pedestal (Issue #1325).
    /// </summary>
    private void DeequipAllActiveItems()
    {
        LogToFile("[Player.ItemPickup] De-equipping all active item subsystems before re-init");

        // Flashlight
        if (_flashlightNode != null && IsInstanceValid(_flashlightNode))
            _flashlightNode.QueueFree();
        _flashlightNode = null;
        _flashlightEquipped = false;

        // Homing bullets
        _homingBulletsEquipped = false;
        _homingActive = false;
        _homingTimer = 0.0f;

        // Teleport bracers
        _teleportBracersEquipped = false;
        _teleportAiming = false;

        // BFF pendant — companion remains in scene; just disable new summons
        _bffPendantEquipped = false;

        // Invisibility suit
        if (_invisibilitySuitEffect != null && IsInstanceValid(_invisibilitySuitEffect))
            _invisibilitySuitEffect.QueueFree();
        _invisibilitySuitEffect = null;
        _invisibilitySuitEquipped = false;

        // Breaker bullets (passive flag)
        _breakerBulletsActive = false;

        // Force field
        if (_forceFieldEffect != null && IsInstanceValid(_forceFieldEffect))
            _forceFieldEffect.QueueFree();
        _forceFieldEffect = null;
        _forceFieldEquipped = false;

        // Trajectory glasses
        if (_trajectoryGlassesEffect != null && IsInstanceValid(_trajectoryGlassesEffect))
            _trajectoryGlassesEffect.QueueFree();
        _trajectoryGlassesEffect = null;
        if (_trajectoryGlassesHud != null && IsInstanceValid(_trajectoryGlassesHud))
            _trajectoryGlassesHud.QueueFree();
        _trajectoryGlassesHud = null;
        _trajectoryGlassesEquipped = false;

        // Loudspeaker
        if (_loudspeakerConeEffect != null && IsInstanceValid(_loudspeakerConeEffect))
            _loudspeakerConeEffect.QueueFree();
        _loudspeakerConeEffect = null;
        if (_loudspeakerHandSprite != null && IsInstanceValid(_loudspeakerHandSprite))
            _loudspeakerHandSprite.QueueFree();
        _loudspeakerHandSprite = null;
        _loudspeakerProgress = null;
        _loudspeakerHoldTimer = 0.0f;
        _loudspeakerEquipped = false;

        // Breaching charges
        if (_breachingChargesEffect != null && IsInstanceValid(_breachingChargesEffect))
            _breachingChargesEffect.QueueFree();
        _breachingChargesEffect = null;
        _breachingChargesEquipped = false;

        // Drilling bullets
        if (_drillingBulletsPopup != null && IsInstanceValid((GodotObject)_drillingBulletsPopup))
            ((Node)_drillingBulletsPopup).QueueFree();
        _drillingBulletsPopup = null;
        _drillingBulletsEquipped = false;
        _drillingBulletsUsed = false;

        // Recoil compensator
        _recoilCompensatorEquipped = false;
        _recoilCompensatorActive = false;
        _recoilCompensatorCharge = 0.0f;

        // Experimental sample
        if (_experimentalSamplePopup != null && IsInstanceValid((GodotObject)_experimentalSamplePopup))
            ((Node)_experimentalSamplePopup).QueueFree();
        _experimentalSamplePopup = null;
        _experimentalSampleEquipped = false;
        _experimentalSampleCharges = 0;

        // Combat disposition (passive)
        _combatDispositionActive = false;

        // Auto-reload (passive)
        _autoReloadActive = false;

        // Fine motor skills
        _fineMotorSkillsEquipped = false;
        _fineMotorSkillsActive = false;

        // Dash (Issue #1071)
        if (_dashEffect != null && IsInstanceValid(_dashEffect))
            _dashEffect.QueueFree();
        _dashEffect = null;
        _dashEquipped = false;

        LogToFile("[Player.ItemPickup] All active item subsystems de-equipped");
    }

    /// <summary>
    /// Called when a new active item is selected (e.g. picked up in roguelike mode).
    /// Initialises the corresponding item subsystem on the player without a scene restart.
    /// Passive items (BREAKER_BULLETS, LASER_SIGHT, EXTENDED_MAGAZINE, ARMORED_SKIN,
    /// AUTO_RELOAD, COMBAT_DISPOSITION) are handled by their own passive init paths.
    /// </summary>
    /// <param name="itemType">The ActiveItemType enum value of the newly selected item.</param>
    private void OnActiveItemPickedUp(long itemType)
    {
        LogToFile($"[Player.ItemPickup] active_item_changed received: type={itemType}");
        // De-equip the previous active item before initialising the new one
        // to prevent dual-equip when the player swaps items at the pedestal.
        DeequipAllActiveItems();
        // Map ActiveItemType enum values to Init functions.
        // Values mirror ActiveItemManager.ActiveItemType in active_item_manager.gd.
        switch (itemType)
        {
            case 1:  // FLASHLIGHT
                InitFlashlight();
                break;
            case 2:  // HOMING_BULLETS
                InitHomingBullets();
                break;
            case 3:  // TELEPORT_BRACERS
                InitTeleportBracers();
                break;
            case 4:  // BFF_PENDANT
                InitBffPendant();
                break;
            case 5:  // INVISIBILITY_SUIT
                InitInvisibilitySuit();
                break;
            case 6:  // BREAKER_BULLETS (passive)
                InitBreakerBullets();
                break;
            case 7:  // FORCE_FIELD
                InitForceField();
                break;
            case 8:  // TRAJECTORY_GLASSES
                InitTrajectoryGlasses();
                break;
            case 11: // LOUDSPEAKER
                InitLoudspeaker();
                break;
            case 12: // BREACHING_CHARGES
                InitBreachingCharges();
                break;
            case 13: // ARMORED_SKIN (passive)
                InitArmoredSkin();
                ApplyItemVisual();
                break;
            case 14: // AUTO_RELOAD (passive)
                InitAutoReload();
                break;
            case 15: // DRILLING_BULLETS
                InitDrillingBullets();
                break;
            case 16: // RECOIL_COMPENSATOR
                InitRecoilCompensator();
                break;
            case 17: // COMBAT_DISPOSITION (passive)
                InitCombatDisposition();
                break;
            case 18: // EXPERIMENTAL_SAMPLE
                InitExperimentalSample();
                break;
            case 19: // FINE_MOTOR_SKILLS
                InitFineMotorSkills();
                break;
            case 20: // DASH (Issue #1071)
                InitDash();
                break;
            default:
                // NONE (0), LASER_SIGHT (9), EXTENDED_MAGAZINE (10): no player-side init needed
                LogToFile($"[Player.ItemPickup] No player-side init required for item type {itemType}");
                break;
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
        // Draw recoil compensator timer bar (Issue #1073)
        if (_recoilCompensatorEquipped && (_recoilCompensatorActive || _recoilCompensatorCharge < RecoilCompensatorMaxCharge))
        {
            DrawRecoilCompensatorBar();
        }

        // Draw homing bullets progress bar (Issue #974)
        if (_homingBulletsEquipped)
        {
            if (_homingBarVisible)
            {
                // Show combined bar (charge pips + timer) while active
                DrawHomingCombinedBar();
            }
            else if (_homingChargeBarPending)
            {
                // Show charge-only bar briefly after deactivation
                DrawHomingChargeBar();
            }
        }

        // Trajectory glasses progress bar removed (Issue #1049).
        // Charge pips are shown by TrajectoryGlassesHUD for 300ms, then auto-hide.
        // The trajectory ray blinks during the last 2 seconds as a low-time warning.

        // Draw experimental sample charge bar (Issue #1127)
        if (_experimentalSampleEquipped && _experimentalSampleChargeBarVisible)
        {
            DrawExperimentalSampleChargeBar();
        }


        // Draw teleport targeting reticle if aiming (Issue #672)
        // Note: Charge count is displayed on the reticle itself (Issue #972)
        if (_teleportAiming && _teleportBracersEquipped)
        {
            DrawTeleportReticle();
        }

        // Draw trajectory glasses laser (Issue #744)
        DrawTrajectoryGlasses();

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
    /// Draw combined charge pips + timer bar for homing bullets (Issue #974).
    /// Layout: charge pips on top (showing remaining uses), timer bar below (depleting over activation).
    /// </summary>
    private void DrawHomingCombinedBar()
    {
        const float barWidth = 40.0f;
        const float barYOffset = -30.0f;
        const float segmentGap = 2.0f;
        const float borderWidth = 1.0f;
        const float pipHeight = 4.0f;
        const float combinedGap = 2.0f;
        const float timerBarHeight = 3.0f;

        int chargeMax = MaxHomingCharges;
        int chargeValue = _homingCharges;
        float timerValue = _homingTimer;
        float timerMax = HomingDuration;

        if (chargeMax <= 0)
            return;

        float pipY = barYOffset;
        float timerY = barYOffset + pipHeight + combinedGap;

        // Draw charge pips
        float totalGaps = segmentGap * (chargeMax - 1);
        float pipWidth = (barWidth - totalGaps) / chargeMax;
        if (pipWidth < 2.0f) pipWidth = 2.0f;

        float startX = -barWidth / 2.0f;
        float chargePercent = (float)chargeValue / chargeMax;
        Color pipFillColor;
        if (chargePercent > 0.5f)
            pipFillColor = new Color(0.2f, 0.8f, 0.4f, 0.85f);
        else if (chargePercent > 0.25f)
            pipFillColor = new Color(0.9f, 0.7f, 0.1f, 0.85f);
        else
            pipFillColor = new Color(0.9f, 0.2f, 0.2f, 0.85f);

        Color bgColor = new Color(0.1f, 0.1f, 0.1f, 0.6f);
        Color emptyColor = new Color(0.2f, 0.2f, 0.2f, 0.4f);
        Color borderColor = new Color(0.3f, 0.3f, 0.3f, 0.7f);
        Color timerFillColor = new Color(0.0f, 0.9f, 0.7f, 0.9f);

        for (int i = 0; i < chargeMax; i++)
        {
            float segX = startX + i * (pipWidth + segmentGap);
            Rect2 pipRect = new Rect2(segX, pipY, pipWidth, pipHeight);

            DrawRect(pipRect, bgColor);
            if (i < chargeValue)
                DrawRect(pipRect, pipFillColor);
            else
                DrawRect(pipRect, emptyColor);
            DrawRect(pipRect, borderColor, false, borderWidth);
        }

        // Draw timer bar below pips
        Rect2 timerRect = new Rect2(-barWidth / 2.0f, timerY, barWidth, timerBarHeight);
        DrawRect(timerRect, bgColor);
        if (timerMax > 0.0f && timerValue > 0.0f)
        {
            float fillRatio = Mathf.Clamp(timerValue / timerMax, 0.0f, 1.0f);
            Rect2 fillRect = new Rect2(-barWidth / 2.0f, timerY, barWidth * fillRatio, timerBarHeight);
            DrawRect(fillRect, timerFillColor);
        }
        DrawRect(timerRect, borderColor, false, borderWidth);
    }

    /// <summary>
    /// Draw segmented charge bar for homing bullets (shown briefly after deactivation, Issue #974).
    /// </summary>
    private void DrawHomingChargeBar()
    {
        const float barWidth = 40.0f;
        const float barHeight = 6.0f;
        const float barYOffset = -30.0f;
        const float segmentGap = 2.0f;
        const float borderWidth = 1.0f;

        int segmentCount = MaxHomingCharges;
        int filledCount = _homingCharges;

        float totalGaps = segmentGap * (segmentCount - 1);
        float segmentWidth = (barWidth - totalGaps) / segmentCount;
        if (segmentWidth < 2.0f) segmentWidth = 2.0f;

        float startX = -barWidth / 2.0f;
        float percent = (float)filledCount / segmentCount;
        Color fillColor;
        if (percent > 0.5f)
            fillColor = new Color(0.2f, 0.8f, 0.4f, 0.85f);
        else if (percent > 0.25f)
            fillColor = new Color(0.9f, 0.7f, 0.1f, 0.85f);
        else
            fillColor = new Color(0.9f, 0.2f, 0.2f, 0.85f);

        Color bgColor = new Color(0.1f, 0.1f, 0.1f, 0.6f);
        Color emptyColor = new Color(0.2f, 0.2f, 0.2f, 0.4f);
        Color borderColor = new Color(0.3f, 0.3f, 0.3f, 0.7f);

        for (int i = 0; i < segmentCount; i++)
        {
            float segX = startX + i * (segmentWidth + segmentGap);
            Rect2 segRect = new Rect2(segX, barYOffset, segmentWidth, barHeight);

            DrawRect(segRect, bgColor);
            if (i < filledCount)
                DrawRect(segRect, fillColor);
            else
                DrawRect(segRect, emptyColor);
            DrawRect(segRect, borderColor, false, borderWidth);
        }
    }

    /// <summary>
    /// Draw combined charge pips + timer bar for trajectory glasses (Issue #974).
    /// Layout: charge pips on top (showing remaining uses), timer bar below (depleting over activation).
    /// </summary>
    private void DrawTrajectoryGlassesCombinedBar()
    {
        const float barWidth = 40.0f;
        const float barYOffset = -30.0f;
        const float segmentGap = 2.0f;
        const float borderWidth = 1.0f;
        const float pipHeight = 4.0f;
        const float combinedGap = 2.0f;
        const float timerBarHeight = 3.0f;

        int chargeMax = TrajectoryGlassesMaxCharges;
        int chargeValue = _trajectoryBarCharges;
        float timerValue = 0.0f;
        float timerMax = TrajectoryGlassesDuration;

        // Get live timer from effect if available
        if (_trajectoryGlassesEffect != null && IsInstanceValid(_trajectoryGlassesEffect))
        {
            timerValue = (float)_trajectoryGlassesEffect.Call("get_remaining_time");
        }

        if (chargeMax <= 0)
            return;

        float pipY = barYOffset;
        float timerY = barYOffset + pipHeight + combinedGap;

        float totalGaps = segmentGap * (chargeMax - 1);
        float pipWidth = (barWidth - totalGaps) / chargeMax;
        if (pipWidth < 2.0f) pipWidth = 2.0f;

        float startX = -barWidth / 2.0f;
        float chargePercent = (float)chargeValue / chargeMax;
        Color pipFillColor;
        if (chargePercent > 0.5f)
            pipFillColor = new Color(0.2f, 0.8f, 0.4f, 0.85f);
        else if (chargePercent > 0.25f)
            pipFillColor = new Color(0.9f, 0.7f, 0.1f, 0.85f);
        else
            pipFillColor = new Color(0.9f, 0.2f, 0.2f, 0.85f);

        Color bgColor = new Color(0.1f, 0.1f, 0.1f, 0.6f);
        Color emptyColor = new Color(0.2f, 0.2f, 0.2f, 0.4f);
        Color borderColor = new Color(0.3f, 0.3f, 0.3f, 0.7f);
        Color timerFillColor = new Color(0.0f, 0.9f, 0.7f, 0.9f);

        for (int i = 0; i < chargeMax; i++)
        {
            float segX = startX + i * (pipWidth + segmentGap);
            Rect2 pipRect = new Rect2(segX, pipY, pipWidth, pipHeight);

            DrawRect(pipRect, bgColor);
            if (i < chargeValue)
                DrawRect(pipRect, pipFillColor);
            else
                DrawRect(pipRect, emptyColor);
            DrawRect(pipRect, borderColor, false, borderWidth);
        }

        // Draw timer bar below pips
        Rect2 timerRect = new Rect2(-barWidth / 2.0f, timerY, barWidth, timerBarHeight);
        DrawRect(timerRect, bgColor);
        if (timerMax > 0.0f && timerValue > 0.0f)
        {
            float fillRatio = Mathf.Clamp(timerValue / timerMax, 0.0f, 1.0f);
            Rect2 fillRect = new Rect2(-barWidth / 2.0f, timerY, barWidth * fillRatio, timerBarHeight);
            DrawRect(fillRect, timerFillColor);
        }
        DrawRect(timerRect, borderColor, false, borderWidth);
    }

    /// <summary>
    /// Draw segmented charge bar for trajectory glasses (shown briefly after deactivation, Issue #974).
    /// </summary>
    private void DrawTrajectoryGlassesChargeBar()
    {
        const float barWidth = 40.0f;
        const float barHeight = 6.0f;
        const float barYOffset = -30.0f;
        const float segmentGap = 2.0f;
        const float borderWidth = 1.0f;

        int segmentCount = TrajectoryGlassesMaxCharges;
        int filledCount = _trajectoryBarCharges;

        float totalGaps = segmentGap * (segmentCount - 1);
        float segmentWidth = (barWidth - totalGaps) / segmentCount;
        if (segmentWidth < 2.0f) segmentWidth = 2.0f;

        float startX = -barWidth / 2.0f;
        float percent = (float)filledCount / segmentCount;
        Color fillColor;
        if (percent > 0.5f)
            fillColor = new Color(0.2f, 0.8f, 0.4f, 0.85f);
        else if (percent > 0.25f)
            fillColor = new Color(0.9f, 0.7f, 0.1f, 0.85f);
        else
            fillColor = new Color(0.9f, 0.2f, 0.2f, 0.85f);

        Color bgColor = new Color(0.1f, 0.1f, 0.1f, 0.6f);
        Color emptyColor = new Color(0.2f, 0.2f, 0.2f, 0.4f);
        Color borderColor = new Color(0.3f, 0.3f, 0.3f, 0.7f);

        for (int i = 0; i < segmentCount; i++)
        {
            float segX = startX + i * (segmentWidth + segmentGap);
            Rect2 segRect = new Rect2(segX, barYOffset, segmentWidth, barHeight);

            DrawRect(segRect, bgColor);
            if (i < filledCount)
                DrawRect(segRect, fillColor);
            else
                DrawRect(segRect, emptyColor);
            DrawRect(segRect, borderColor, false, borderWidth);
        }
    }

    /// <summary>
    /// Update homing progress bar auto-hide timer (Issue #974).
    /// Hides the charge bar 300ms after homing deactivation.
    /// </summary>
    private void UpdateHomingBarTimer(float delta)
    {
        if (_homingChargeBarPending)
        {
            _homingChargeBarHideTimer -= delta;
            if (_homingChargeBarHideTimer <= 0.0f)
            {
                _homingChargeBarPending = false;
                QueueRedraw();
            }
        }

        // While homing is active, keep redrawing to update the timer bar
        if (_homingBarVisible)
        {
            QueueRedraw();
        }
    }

    /// <summary>
    /// Update trajectory glasses progress bar auto-hide timer (Issue #974).
    /// Hides the charge bar 300ms after trajectory deactivation.
    /// </summary>
    private void UpdateTrajectoryBarTimer(float delta)
    {
        // Trajectory glasses progress bar removed (Issue #1049).
        // The HUD node (trajectory_glasses_hud.gd) handles its own 300ms auto-hide timer.
        // No redraw loop needed here anymore.
        _ = delta; // suppress unused-parameter warning
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

    /// <summary>
    /// Draw trajectory glasses laser lines in local player coordinates (Issue #744).
    /// Uses the same _draw() approach as grenade trajectory: reads local-coordinate points
    /// stored by trajectory_glasses_effect.gd and draws them here in Player's _Draw().
    /// </summary>
    private void DrawTrajectoryGlasses()
    {
        if (!_trajectoryGlassesEquipped || _trajectoryGlassesEffect == null)
        {
            return;
        }

        if (!IsInstanceValid(_trajectoryGlassesEffect))
        {
            return;
        }

        bool isActive = (bool)_trajectoryGlassesEffect.Get("is_active");
        if (!isActive)
        {
            return;
        }

        // Skip drawing during the "off" phase of the blink cycle (Issue #1085).
        bool rayVisible = (bool)_trajectoryGlassesEffect.Get("trajectory_ray_visible");
        if (!rayVisible)
        {
            return;
        }

        // Read trajectory points (in local player coordinates) from the GDScript effect
        var pointsVariant = _trajectoryGlassesEffect.Get("trajectory_local_points");
        if (pointsVariant.VariantType == Variant.Type.Nil)
        {
            return;
        }

        var pointsArray = pointsVariant.AsGodotArray();
        if (pointsArray.Count < 2)
        {
            return;
        }

        // Read the index where the invalid (red) terminal segment starts.
        // -1 means all segments are valid (green).
        var invalidIdxVariant = _trajectoryGlassesEffect.Get("trajectory_invalid_start_index");
        int invalidStartIndex = invalidIdxVariant.VariantType != Variant.Type.Nil
            ? invalidIdxVariant.AsInt32()
            : -1;

        Color validColor = new Color(0.0f, 1.0f, 0.0f, 0.8f);   // Green
        Color invalidColor = new Color(1.0f, 0.0f, 0.0f, 0.8f); // Red

        // Determine up to which index valid (green) segments run.
        // If invalidStartIndex == -1: all segments are green (0..Count-2).
        // If invalidStartIndex >= 1: green segments are 0..invalidStartIndex-2,
        //   and segment (invalidStartIndex-1) -> (invalidStartIndex) is red.
        int lastValidSegmentEnd = invalidStartIndex >= 1 ? invalidStartIndex - 1 : pointsArray.Count - 1;

        // Draw glow for valid segments
        for (int i = 0; i < lastValidSegmentEnd; i++)
        {
            Color glowValid = new Color(0.0f, 1.0f, 0.0f, 0.3f);
            DrawLine(pointsArray[i].As<Vector2>(), pointsArray[i + 1].As<Vector2>(), glowValid, 6.0f);
        }

        // Draw glow for terminal invalid segment (if any)
        if (invalidStartIndex >= 1 && invalidStartIndex < pointsArray.Count)
        {
            Color glowInvalid = new Color(1.0f, 0.0f, 0.0f, 0.3f);
            DrawLine(pointsArray[invalidStartIndex - 1].As<Vector2>(), pointsArray[invalidStartIndex].As<Vector2>(), glowInvalid, 6.0f);
        }

        // Draw main laser for valid segments (green)
        for (int i = 0; i < lastValidSegmentEnd; i++)
        {
            DrawLine(pointsArray[i].As<Vector2>(), pointsArray[i + 1].As<Vector2>(), validColor, 2.0f);
        }

        // Draw main laser for terminal invalid segment (red)
        if (invalidStartIndex >= 1 && invalidStartIndex < pointsArray.Count)
        {
            DrawLine(pointsArray[invalidStartIndex - 1].As<Vector2>(), pointsArray[invalidStartIndex].As<Vector2>(), invalidColor, 2.0f);
        }

        // Draw dot at start (bullet spawn point)
        DrawCircle(pointsArray[0].As<Vector2>(), 3.0f, validColor);

        // Draw small diamonds at valid bounce points (not at the terminal red point)
        int lastDiamond = invalidStartIndex >= 1 ? invalidStartIndex - 1 : pointsArray.Count - 1;
        for (int i = 1; i < lastDiamond; i++)
        {
            float s = 4.0f;
            Vector2 p = pointsArray[i].As<Vector2>();
            DrawLine(p + new Vector2(0, -s), p + new Vector2(s, 0), validColor, 2.0f);
            DrawLine(p + new Vector2(s, 0), p + new Vector2(0, s), validColor, 2.0f);
            DrawLine(p + new Vector2(0, s), p + new Vector2(-s, 0), validColor, 2.0f);
            DrawLine(p + new Vector2(-s, 0), p + new Vector2(0, -s), validColor, 2.0f);
        }
    }

    #endregion

    // =========================================================================
    // Radio Jammer HUD (Issue #1036)
    // =========================================================================

    /// <summary>Reference to the GDScript JammerHUD node shown above the player.</summary>
    private Node2D _jammerHud = null;

    /// <summary>
    /// Initialize the jammer HUD prohibition-sign icon.
    /// Always created; visibility is toggled each physics frame.
    /// </summary>
    private void InitJammerHud()
    {
        var jammerHudScript = GD.Load<Script>("res://scripts/ui/jammer_hud.gd");
        if (jammerHudScript == null)
        {
            LogToFile("[Player.Jammer] WARNING: Failed to load jammer_hud.gd");
            return;
        }

        _jammerHud = new Node2D();
        _jammerHud.SetScript(jammerHudScript);
        _jammerHud.Name = "JammerHUD";
        AddChild(_jammerHud);
        LogToFile("[Player.Jammer] JammerHUD initialized");
    }

    /// <summary>
    /// Show the jammer HUD only when the player is jammed AND has an active item equipped.
    /// Called every physics frame.
    /// </summary>
    private void UpdateJammerHud()
    {
        if (_jammerHud == null || !IsInstanceValid(_jammerHud))
            return;

        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
            return;

        bool isJammed = (bool)activeItemManager.Call("is_active_item_jammed");
        int currentItem = (int)activeItemManager.Get("current_active_item");
        bool hasItem = currentItem != 0; // 0 = ActiveItemType.NONE
        _jammerHud.Call("set_jammed_visible", isJammed && hasItem);
    }

    /// <summary>
    /// Check whether active items are currently jammed by a Radio Jammer enemy.
    /// Calls is_active_item_jammed_verbose() on the GDScript autoload so that
    /// detailed diagnostics are logged whenever Space is pressed (Issue #1036).
    /// Use only for single-press actions (not hold); for hold-based actions use IsActiveItemJammedSilent().
    /// </summary>
    private bool IsActiveItemJammedVerbose()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
            return false;
        return (bool)activeItemManager.Call("is_active_item_jammed_verbose");
    }

    /// <summary>
    /// Check whether active items are currently jammed, without verbose logging.
    /// Used for hold-based input actions (Space held) to avoid log flooding (Issue #1036).
    /// </summary>
    private bool IsActiveItemJammedSilent()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
            return false;
        return (bool)activeItemManager.Call("is_active_item_jammed");
    }

    #region Experimental Sample (Issue #1127)

    /// <summary>
    /// Initialize the experimental sample if it is the selected active item.
    /// Randomises charge count (1–5) at the start of each level.
    /// </summary>
    private void InitExperimentalSample()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.ExperimentalSample] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_experimental_sample"))
        {
            LogToFile("[Player.ExperimentalSample] ActiveItemManager missing has_experimental_sample method");
            return;
        }

        bool hasExperimentalSample = (bool)activeItemManager.Call("has_experimental_sample");
        if (!hasExperimentalSample)
        {
            LogToFile("[Player.ExperimentalSample] Experimental sample not selected");
            return;
        }

        _experimentalSampleEquipped = true;
        var rng = new RandomNumberGenerator();
        rng.Randomize();
        _experimentalSampleCharges = rng.RandiRange(ExperimentalSampleMinCharges, ExperimentalSampleMaxCharges);

        LogToFile($"[Player.ExperimentalSample] Equipped, charges this run: {_experimentalSampleCharges}");

        // Show charge bar
        _experimentalSampleChargeBarVisible = true;
        QueueRedraw();

        // Spawn floating icon popup child (GDScript node)
        if (_experimentalSamplePopup == null || !IsInstanceValid((GodotObject)_experimentalSamplePopup))
        {
            var popupScript = GD.Load("res://scripts/ui/experimental_sample_item_popup.gd");
            if (popupScript != null)
            {
                var popupNode = new Node2D();
                popupNode.SetScript(popupScript);
                popupNode.Name = "ExperimentalSampleItemPopup";
                AddChild(popupNode);
                _experimentalSamplePopup = popupNode;
            }
        }
    }

    /// <summary>
    /// Handle experimental sample input: press Space to trigger a random active item effect.
    /// The randomly chosen effect can be ANY item type 1–17, even items the player has not unlocked.
    /// </summary>
    private void HandleExperimentalSampleInput()
    {
        if (!_experimentalSampleEquipped)
            return;

        if (!Input.IsActionJustPressed("flashlight_toggle"))
            return;

        // Issue #1036: Block active item use when jammed by a Radio Jammer enemy
        if (IsActiveItemJammedVerbose())
        {
            LogToFile("[Player.ExperimentalSample] Space blocked by Radio Jammer (Issue #1036)");
            return;
        }

        if (_experimentalSampleCharges <= 0)
        {
            LogToFile("[Player.ExperimentalSample] No charges remaining");
            return;
        }

        _experimentalSampleCharges -= 1;

        // Update charge bar
        _experimentalSampleChargeBarVisible = true;
        QueueRedraw();

        // Active-only item pool (Issue #1127): passive items are excluded.
        // Passive items excluded: 6=BREAKER_BULLETS, 9=LASER_SIGHT, 10=EXTENDED_MAGAZINE,
        //   13=ARMORED_SKIN, 14=AUTO_RELOAD, 17=COMBAT_DISPOSITION
        // Active items kept: 1=FLASHLIGHT, 2=HOMING_BULLETS, 3=TELEPORT_BRACERS,
        //   4=BFF_PENDANT, 5=INVISIBILITY_SUIT, 7=FORCE_FIELD, 8=TRAJECTORY_GLASSES,
        //   11=LOUDSPEAKER, 12=BREACHING_CHARGES, 15=DRILLING_BULLETS, 16=RECOIL_COMPENSATOR
        // Homing (2): 5 tickets (~5%); BFF (4): 2 tickets (~2%); all others: 10 tickets each.
        int[] activeTypes = { 1, 2, 3, 4, 5, 7, 8, 11, 12, 15, 16 };
        var poolList = new System.Collections.Generic.List<int>();
        foreach (int t in activeTypes)
        {
            int tickets = t == 4 ? 2 : (t == 2 ? 5 : 10);
            for (int k = 0; k < tickets; k++)
                poolList.Add(t);
        }
        int[] weightedPool = poolList.ToArray();

        var rng = new RandomNumberGenerator();
        rng.Randomize();
        int firedType = weightedPool[rng.RandiRange(0, weightedPool.Length - 1)];
        LogToFile($"[Player.ExperimentalSample] Charges remaining: {_experimentalSampleCharges} — triggering random effect for type {firedType}");
        float iconDuration = TriggerExperimentalSampleEffect(firedType);

        // Show floating icon popup for the triggered item (Issue #1127)
        if (_experimentalSamplePopup != null && IsInstanceValid((GodotObject)_experimentalSamplePopup))
        {
            var activeItemMgr = GetNodeOrNull("/root/ActiveItemManager");
            if (activeItemMgr != null && activeItemMgr.HasMethod("get_active_item_icon_path"))
            {
                string iconPath = (string)activeItemMgr.Call("get_active_item_icon_path", firedType);
                if (!string.IsNullOrEmpty(iconPath))
                    ((Node2D)_experimentalSamplePopup).Call("show_icon", iconPath, iconDuration);
            }
        }
    }

    /// <summary>
    /// Trigger the on-press effect of any active item type chosen by the experimental sample.
    /// Every item type always fires — no re-rolling.
    /// Returns the effect duration in seconds (used to keep the icon popup visible).
    /// </summary>
    private float TriggerExperimentalSampleEffect(int itemType)
    {
        LogToFile($"[Player.ExperimentalSample] Executing effect for type {itemType}");

        switch (itemType)
        {
            case 1: // FLASHLIGHT — activate for 4 seconds (Issue #1127)
            {
                const float FlashlightEffectDuration = 1.8f;
                Node2D? flashNode = _flashlightNode;
                if (flashNode == null || !IsInstanceValid(flashNode))
                {
                    // Spawn a temporary flashlight node attached to PlayerModel
                    var flashScene = GD.Load<PackedScene>(FlashlightScenePath);
                    if (flashScene != null && _playerModel != null)
                    {
                        flashNode = flashScene.Instantiate<Node2D>();
                        flashNode.Name = "FlashlightEffectTemp";
                        _playerModel.AddChild(flashNode);
                        flashNode.Position = new Vector2(BulletSpawnOffset, 0);
                        LogToFile("[Player.ExperimentalSample] Flashlight: temporary node created");
                    }
                }
                if (flashNode != null && IsInstanceValid(flashNode))
                {
                    if (flashNode.HasMethod("turn_on"))
                        flashNode.Call("turn_on");
                    var flashRef = flashNode;
                    GetTree().CreateTimer(FlashlightEffectDuration).Timeout += () =>
                    {
                        if (IsInstanceValid(flashRef) && flashRef.HasMethod("turn_off"))
                            flashRef.Call("turn_off");
                    };
                    LogToFile($"[Player.ExperimentalSample] Flashlight activated for {FlashlightEffectDuration}s");
                    return FlashlightEffectDuration;
                }
                LogToFile("[Player.ExperimentalSample] Flashlight: node unavailable, homing fallback");
                if (!_homingActive) { _homingActive = true; _homingTimer = HomingDuration; PlayHomingSound(); StartHomingScanner(); EmitSignal(SignalName.HomingActivated); }
                return HomingDuration;
            }

            case 2: // HOMING_BULLETS — activate homing for one burst
                _homingActive = true;
                _homingTimer = HomingDuration;
                PlayHomingSound();
                StartHomingScanner();
                EmitSignal(SignalName.HomingActivated);
                LogToFile($"[Player.ExperimentalSample] Homing effect triggered for {HomingDuration:F1}s");
                return HomingDuration;

            case 3: // TELEPORT_BRACERS — show crosshair for 2s then teleport (Issue #1127)
            {
                const float TeleportAimDuration = 1.8f;
                // Borrow teleport bracers aim state; _teleportExperimentalActive prevents
                // HandleTeleportBracersInput from firing the teleport on the next frame.
                bool wasEquipped = _teleportBracersEquipped;
                _teleportBracersEquipped = true;
                _teleportAiming = true;
                _teleportExperimentalActive = true;
                _teleportTargetPosition = GetSafeTeleportPosition(GlobalPosition, GetGlobalMousePosition());
                QueueRedraw();
                LogToFile($"[Player.ExperimentalSample] Teleport bracers: aiming for {TeleportAimDuration}s");
                GetTree().CreateTimer(TeleportAimDuration).Timeout += () =>
                {
                    if (!IsInstanceValid(this)) return;
                    _teleportExperimentalActive = false;
                    _teleportAiming = false;
                    _teleportBracersEquipped = wasEquipped;
                    Vector2 oldPos = GlobalPosition;
                    GlobalPosition = _teleportTargetPosition;
                    ResetAllEnemyMemories("experimental sample teleport");
                    QueueRedraw();
                    LogToFile($"[Player.ExperimentalSample] Teleport bracers: teleported from {oldPos} to {_teleportTargetPosition}");
                };
                return TeleportAimDuration;
            }

            case 4: // BFF_PENDANT — summon companion (always fire, even if already summoned — re-summon)
                SummonBffCompanion();
                LogToFile("[Player.ExperimentalSample] BFF companion summoned via experimental sample");
                return 3.0f;

            case 5: // INVISIBILITY_SUIT — activate (init temp instance if not equipped)
            {
                Node? effectNode = _invisibilitySuitEffect;
                if (effectNode == null || !IsInstanceValid(effectNode))
                {
                    // Temporarily init invisibility effect for this activation
                    var effectScript = GD.Load<Script>("res://scripts/effects/invisibility_suit_effect.gd");
                    if (effectScript != null)
                    {
                        effectNode = new Node();
                        effectNode.SetScript(effectScript);
                        effectNode.Name = "InvisibilitySuitEffectTemp";
                        AddChild(effectNode);
                        effectNode.Call("initialize", this);
                        LogToFile("[Player.ExperimentalSample] Invisibility suit: temporary effect node created");
                    }
                }
                if (effectNode != null && IsInstanceValid(effectNode))
                {
                    effectNode.Call("activate");
                    LogToFile("[Player.ExperimentalSample] Invisibility suit activated via experimental sample");
                    // Duration from invisibility effect or default 3s
                    float dur = effectNode.HasMethod("get_duration") ? (float)effectNode.Call("get_duration") : 3.0f;
                    return dur;
                }
                // Fallback: homing burst
                if (!_homingActive) { _homingActive = true; _homingTimer = HomingDuration; PlayHomingSound(); StartHomingScanner(); EmitSignal(SignalName.HomingActivated); }
                LogToFile("[Player.ExperimentalSample] Invisibility suit fallback: homing burst");
                return HomingDuration;
            }

            case 6: // BREAKER_BULLETS — passive bullet modifier; apply homing burst as visible effect
                if (!_homingActive)
                {
                    _homingActive = true;
                    _homingTimer = HomingDuration;
                    PlayHomingSound();
                    StartHomingScanner();
                    EmitSignal(SignalName.HomingActivated);
                }
                LogToFile("[Player.ExperimentalSample] Breaker bullets effect: homing burst triggered");
                return HomingDuration;

            case 7: // FORCE_FIELD — activate for 4 seconds (Issue #1127)
            {
                const float ForceFieldEffectDuration = 1.8f;
                Node? ffNode = _forceFieldEffect;
                if (ffNode == null || !IsInstanceValid(ffNode))
                {
                    // Spawn a temporary force field node
                    const string ForceFieldScenePath2 = "res://scenes/effects/ForceFieldEffect.tscn";
                    var ffScene = GD.Load<PackedScene>(ForceFieldScenePath2);
                    if (ffScene != null)
                    {
                        ffNode = ffScene.Instantiate();
                        ffNode.Name = "ForceFieldEffectTemp";
                        AddChild(ffNode);
                        LogToFile("[Player.ExperimentalSample] Force field: temporary node created");
                    }
                }
                if (ffNode != null && IsInstanceValid(ffNode))
                {
                    bool ffActive = (bool)ffNode.Get("is_active");
                    if (!ffActive)
                        ffNode.Call("activate");
                    var ffRef = ffNode;
                    GetTree().CreateTimer(ForceFieldEffectDuration).Timeout += () =>
                    {
                        if (IsInstanceValid(ffRef))
                        {
                            bool stillActive = (bool)ffRef.Get("is_active");
                            if (stillActive)
                                ffRef.Call("deactivate");
                        }
                    };
                    LogToFile($"[Player.ExperimentalSample] Force field activated for {ForceFieldEffectDuration}s");
                    return ForceFieldEffectDuration;
                }
                LogToFile("[Player.ExperimentalSample] Force field: node unavailable, homing fallback");
                if (!_homingActive) { _homingActive = true; _homingTimer = HomingDuration; PlayHomingSound(); StartHomingScanner(); EmitSignal(SignalName.HomingActivated); }
                return HomingDuration;
            }

            case 8: // TRAJECTORY_GLASSES — activate (init temp instance if not equipped, wire into draw path)
            {
                // If not currently equipped, create a full temporary node and store it in
                // _trajectoryGlassesEffect / _trajectoryGlassesEquipped so that _Draw() renders the lines.
                bool tempCreated = false;
                if (_trajectoryGlassesEffect == null || !IsInstanceValid(_trajectoryGlassesEffect))
                {
                    var effectScript = GD.Load<Script>("res://scripts/effects/trajectory_glasses_effect.gd");
                    if (effectScript != null)
                    {
                        var tempNode = new Node();
                        tempNode.SetScript(effectScript);
                        tempNode.Name = "TrajectoryGlassesEffectTemp";
                        AddChild(tempNode);
                        tempNode.Call("initialize", this);
                        if (CurrentWeapon != null)
                            tempNode.Call("set_weapon", CurrentWeapon);
                        // Wire into draw path
                        _trajectoryGlassesEffect = tempNode;
                        _trajectoryGlassesEquipped = true;
                        tempCreated = true;
                        LogToFile("[Player.ExperimentalSample] Trajectory glasses: temporary effect node created and wired");
                        // Also create HUD so charge pips are shown
                        var hudScript = GD.Load<Script>("res://scripts/ui/trajectory_glasses_hud.gd");
                        if (hudScript != null)
                        {
                            var hudNode = new Node2D();
                            hudNode.SetScript(hudScript);
                            hudNode.Name = "TrajectoryGlassesHUDTemp";
                            AddChild(hudNode);
                            hudNode.Call("initialize", _trajectoryGlassesEffect);
                            _trajectoryGlassesHud = hudNode;
                        }
                    }
                }
                if (_trajectoryGlassesEffect != null && IsInstanceValid(_trajectoryGlassesEffect))
                {
                    if (CurrentWeapon != null)
                        _trajectoryGlassesEffect.Call("set_weapon", CurrentWeapon);
                    bool activated = (bool)_trajectoryGlassesEffect.Call("activate");
                    LogToFile($"[Player.ExperimentalSample] Trajectory glasses activated={activated} via experimental sample for {TrajectoryGlassesDuration:F1}s");
                    if (tempCreated)
                    {
                        // Auto-cleanup after duration if we created a temporary node
                        var effectRef = _trajectoryGlassesEffect;
                        var hudRef = _trajectoryGlassesHud;
                        GetTree().CreateTimer(TrajectoryGlassesDuration + 0.5f).Timeout += () =>
                        {
                            if (!IsInstanceValid(this)) return;
                            // Only reset the equipped fields if they still point at our temp node
                            if (_trajectoryGlassesEffect == effectRef)
                            {
                                _trajectoryGlassesEquipped = false;
                                _trajectoryGlassesEffect = null;
                                _trajectoryGlassesHud = null;
                            }
                            if (IsInstanceValid(effectRef)) effectRef.QueueFree();
                            if (hudRef != null && IsInstanceValid(hudRef)) hudRef.QueueFree();
                        };
                    }
                    return TrajectoryGlassesDuration;
                }
                // Fallback: homing burst
                if (!_homingActive) { _homingActive = true; _homingTimer = HomingDuration; PlayHomingSound(); StartHomingScanner(); EmitSignal(SignalName.HomingActivated); }
                LogToFile("[Player.ExperimentalSample] Trajectory glasses fallback: homing burst");
                return HomingDuration;
            }

            case 9: // LASER_SIGHT — passive; trigger homing burst as visible effect
                if (!_homingActive)
                {
                    _homingActive = true;
                    _homingTimer = HomingDuration;
                    PlayHomingSound();
                    StartHomingScanner();
                    EmitSignal(SignalName.HomingActivated);
                }
                LogToFile("[Player.ExperimentalSample] Laser sight effect: homing burst triggered");
                return HomingDuration;

            case 10: // EXTENDED_MAGAZINE — passive; trigger homing burst as visible effect
                if (!_homingActive)
                {
                    _homingActive = true;
                    _homingTimer = HomingDuration;
                    PlayHomingSound();
                    StartHomingScanner();
                    EmitSignal(SignalName.HomingActivated);
                }
                LogToFile("[Player.ExperimentalSample] Extended magazine effect: homing burst triggered");
                return HomingDuration;

            case 11: // LOUDSPEAKER — apply pacification effect (always, without checking equipped)
            {
                Vector2 aimDir = LoudspeakerGetAimDirection();
                // Show cone visual (needs the cone effect node; create temp one if needed)
                if (_loudspeakerConeEffect == null || !IsInstanceValid(_loudspeakerConeEffect))
                {
                    var coneScript = GD.Load<Script>("res://scripts/effects/loudspeaker_cone_effect.gd");
                    if (coneScript != null)
                    {
                        var tempCone = new Node2D();
                        tempCone.SetScript(coneScript);
                        tempCone.Name = "LoudspeakerConeEffectTemp";
                        AddChild(tempCone);
                        _loudspeakerConeEffect = tempCone;
                        LogToFile("[Player.ExperimentalSample] Loudspeaker: temporary cone effect node created");
                        // Auto-cleanup after animation completes (approx 1 s)
                        GetTree().CreateTimer(1.5f).Timeout += () =>
                        {
                            if (_loudspeakerConeEffect == tempCone)
                                _loudspeakerConeEffect = null;
                            if (IsInstanceValid(tempCone)) tempCone.QueueFree();
                        };
                    }
                }
                if (_loudspeakerConeEffect != null && IsInstanceValid(_loudspeakerConeEffect))
                    _loudspeakerConeEffect.Call("play", aimDir);
                // Alert all enemies (draw attention) and pacify those in the cone
                LoudspeakerAlertAllEnemies();
                LoudspeakerApplyEffect(aimDir, 1.0f, 0.0f);
                LogToFile("[Player.ExperimentalSample] Loudspeaker effect applied via experimental sample");
                return 2.0f;
            }

            case 12: // BREACHING_CHARGES — countdown 1.8s, place at end of timer, then detonate (Issue #1127)
            {
                const float BreachingTimerDuration = 1.8f;
                // Use existing effect node if equipped; otherwise create a temporary one
                Node? bcEffect = _breachingChargesEffect;
                bool bcTempCreated = false;
                if (bcEffect == null || !IsInstanceValid(bcEffect))
                {
                    var bcScript = GD.Load<Script>("res://scripts/effects/breaching_charges_effect.gd");
                    if (bcScript != null)
                    {
                        bcEffect = new Node();
                        bcEffect.SetScript(bcScript);
                        bcEffect.Name = "BreachingChargesEffectTemp";
                        AddChild(bcEffect);
                        bcEffect.Call("initialize", this);
                        bcTempCreated = true;
                        LogToFile("[Player.ExperimentalSample] Breaching charges: temporary node created");
                    }
                }
                if (bcEffect != null && IsInstanceValid(bcEffect))
                {
                    // Countdown runs for BreachingTimerDuration seconds; charge is placed and detonated at the end
                    LogToFile($"[Player.ExperimentalSample] Breaching charges: placing and detonating after {BreachingTimerDuration}s");
                    var bcRef = bcEffect;
                    GetTree().CreateTimer(BreachingTimerDuration).Timeout += () =>
                    {
                        if (!IsInstanceValid(bcRef)) return;
                        // Place charge near wall; if no wall, force-place at player feet
                        bool placed = (bool)bcRef.Call("try_place_charge");
                        if (!placed)
                        {
                            bcRef.Set("has_placed_charge", true);
                            bcRef.Set("_charge_position", GlobalPosition);
                            bcRef.Set("_charge_wall_direction", Vector2.Down);
                            bcRef.Set("_charged_walls", new Godot.Collections.Array());
                            LogToFile("[Player.ExperimentalSample] Breaching charges: no wall nearby, placed at player feet");
                        }
                        else
                        {
                            LogToFile("[Player.ExperimentalSample] Breaching charges: charge placed on wall");
                        }
                        bool det = (bool)bcRef.Call("detonate");
                        LogToFile($"[Player.ExperimentalSample] Breaching charges: detonated={det}");
                        if (bcTempCreated && IsInstanceValid(bcRef)) bcRef.QueueFree();
                    };
                    return BreachingTimerDuration;
                }
                LogToFile("[Player.ExperimentalSample] Breaching charges: failed to create effect node");
                return 0.5f;
            }

            case 13: // ARMORED_SKIN — passive; trigger homing burst as visible effect
                if (!_homingActive)
                {
                    _homingActive = true;
                    _homingTimer = HomingDuration;
                    PlayHomingSound();
                    StartHomingScanner();
                    EmitSignal(SignalName.HomingActivated);
                }
                LogToFile("[Player.ExperimentalSample] Armored skin effect: homing burst triggered");
                return HomingDuration;

            case 14: // AUTO_RELOAD — passive; trigger homing burst as visible effect
                if (!_homingActive)
                {
                    _homingActive = true;
                    _homingTimer = HomingDuration;
                    PlayHomingSound();
                    StartHomingScanner();
                    EmitSignal(SignalName.HomingActivated);
                }
                LogToFile("[Player.ExperimentalSample] Auto-reload effect: homing burst triggered");
                return HomingDuration;

            case 15: // DRILLING_BULLETS — apply drilling to current magazine (always, even if not equipped)
            {
                int activeAmmo = CurrentWeapon is Shotgun shotgunEx
                    ? shotgunEx.ShellsInTube
                    : (CurrentWeapon?.CurrentAmmo ?? 0);
                if (CurrentWeapon != null && activeAmmo > 0)
                {
                    CurrentWeapon.DrillingBulletsRemaining = activeAmmo;
                    LogToFile($"[Player.ExperimentalSample] Drilling bullets effect: {activeAmmo} drilling bullets applied to current magazine");
                }
                else
                {
                    if (!_homingActive) { _homingActive = true; _homingTimer = HomingDuration; PlayHomingSound(); StartHomingScanner(); EmitSignal(SignalName.HomingActivated); }
                    LogToFile("[Player.ExperimentalSample] Drilling bullets effect: homing burst fallback (no ammo)");
                }
                return 2.0f;
            }

            case 16: // RECOIL_COMPENSATOR — activate for 4 seconds (Issue #1127)
            {
                const float RecoilEffectDuration = 1.8f;
                // Use experimental timer: HandleRecoilCompensatorInput ticks it each frame
                // so the effect stays active for the full 4 s without needing Space held.
                _recoilCompensatorEquipped = true;
                _recoilCompensatorActive = true;
                _recoilCompensatorExperimentalTimer = RecoilEffectDuration;
                QueueRedraw();
                LogToFile($"[Player.ExperimentalSample] Recoil compensator activated for {RecoilEffectDuration}s");
                return RecoilEffectDuration;
            }

            case 17: // COMBAT_DISPOSITION — passive; trigger homing burst as visible effect
                if (!_homingActive)
                {
                    _homingActive = true;
                    _homingTimer = HomingDuration;
                    PlayHomingSound();
                    StartHomingScanner();
                    EmitSignal(SignalName.HomingActivated);
                }
                LogToFile("[Player.ExperimentalSample] Combat disposition effect: homing burst triggered");
                return HomingDuration;

            default:
                LogToFile($"[Player.ExperimentalSample] Unknown item type {itemType} — homing fallback");
                if (!_homingActive) { _homingActive = true; _homingTimer = HomingDuration; PlayHomingSound(); StartHomingScanner(); EmitSignal(SignalName.HomingActivated); }
                return HomingDuration;
        }
    }

    #endregion

    // =========================================================================
    // Fine Motor Skills Active Item (Issue #1315, #1337)
    // =========================================================================
    #region Fine Motor Skills

    /// <summary>
    /// Whether the fine motor skills item is equipped.
    /// </summary>
    private bool _fineMotorSkillsEquipped = false;

    /// <summary>
    /// Whether a fine motor skills reload sequence is currently in progress.
    /// Prevents overlapping activations while reload stages are playing.
    /// </summary>
    private bool _fineMotorSkillsActive = false;

    /// <summary>
    /// Delay in seconds before Fine Motor Skills activates after pressing Space (Issue #1337).
    /// Set to 0 to disable the delay. Configurable for gameplay tuning.
    /// </summary>
    private const float FineMotorSkillsActivationDelay = 0.2f;

    /// <summary>
    /// Delay in seconds between sequential reload stages (Issue #1337).
    /// Controls the pacing of individual reload steps (e.g., each bolt step, each shell load).
    /// </summary>
    private const float FineMotorSkillsStageDelay = 0.2f;

    /// <summary>
    /// Initializes the fine motor skills item if ActiveItemManager has it selected.
    /// </summary>
    private void InitFineMotorSkills()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.FineMotorSkills] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_fine_motor_skills"))
        {
            LogToFile("[Player.FineMotorSkills] ActiveItemManager missing has_fine_motor_skills method");
            return;
        }

        bool hasFineMotorSkills = (bool)activeItemManager.Call("has_fine_motor_skills");
        if (!hasFineMotorSkills)
        {
            LogToFile("[Player.FineMotorSkills] Fine motor skills not selected in ActiveItemManager");
            return;
        }

        _fineMotorSkillsEquipped = true;
        LogToFile("[Player.FineMotorSkills] Fine motor skills equipped — unlimited charges, no cooldown");
    }

    /// <summary>
    /// Handles fine motor skills input: press Space to reload weapon with sequential
    /// reload stages after a configurable activation delay (Issue #1337).
    /// Works with all weapon types: Revolver (fills cylinder), Shotgun (fills tube + resets pump),
    /// Sniper Rifle (completes bolt cycle + reloads), and standard weapons (instant magazine swap).
    /// </summary>
    private void HandleFineMotorSkillsInput()
    {
        if (!_fineMotorSkillsEquipped)
        {
            return;
        }

        if (!Input.IsActionJustPressed("flashlight_toggle"))
        {
            return;
        }

        // Prevent overlapping activations while a reload sequence is playing
        if (_fineMotorSkillsActive)
        {
            LogToFile("[Player.FineMotorSkills] Already active — ignoring input");
            return;
        }

        // Issue #1036: Block active item use when jammed
        if (IsActiveItemJammedVerbose())
        {
            LogToFile("[Player.FineMotorSkills] Space blocked by Radio Jammer (Issue #1036)");
            return;
        }

        LogToFile("[Player.FineMotorSkills] Activating — sequential reload with stages (Issue #1337)");
        _fineMotorSkillsActive = true;

        // Start async reload sequence with activation delay
        FineMotorSkillsActivateAsync();
    }

    /// <summary>
    /// Asynchronously activates fine motor skills: waits for activation delay,
    /// then dispatches to weapon-specific sequential reload (Issue #1337).
    /// </summary>
    private async void FineMotorSkillsActivateAsync()
    {
        // Wait for activation delay before starting reload (Issue #1337)
        if (FineMotorSkillsActivationDelay > 0)
        {
            await ToSignal(GetTree().CreateTimer(FineMotorSkillsActivationDelay), "timeout");
        }

        // Handle weapon-specific sequential reload
        if (CurrentWeapon is Revolver revolver)
        {
            await FineMotorSkillsReloadRevolverAsync(revolver);
        }
        else if (CurrentWeapon is Shotgun shotgun)
        {
            await FineMotorSkillsReloadShotgunAsync(shotgun);
        }
        else if (CurrentWeapon is SniperRifle sniper)
        {
            await FineMotorSkillsReloadSniperAsync(sniper);
        }
        else if (CurrentWeapon != null)
        {
            FineMotorSkillsReloadStandard(CurrentWeapon);
        }

        _fineMotorSkillsActive = false;
    }

    /// <summary>
    /// Sequentially reloads a revolver: open cylinder, insert cartridges one by one, close cylinder (Issue #1337).
    /// Each stage plays its sound and waits before proceeding to the next.
    /// </summary>
    private async Task FineMotorSkillsReloadRevolverAsync(Revolver revolver)
    {
        await revolver.FineMotorSkillsReloadAsync(FineMotorSkillsStageDelay);
        LogToFile($"[Player.FineMotorSkills] Revolver reloaded: {revolver.CurrentAmmo}/{revolver.CylinderCapacity}");
    }

    /// <summary>
    /// Sequentially reloads a shotgun: load shells one by one, then close action (Issue #1337).
    /// Each stage plays its sound and waits before proceeding to the next.
    /// </summary>
    private async Task FineMotorSkillsReloadShotgunAsync(Shotgun shotgun)
    {
        await shotgun.FineMotorSkillsReloadAsync(FineMotorSkillsStageDelay);
        LogToFile($"[Player.FineMotorSkills] Shotgun reloaded: {shotgun.ShellsInTube}/{shotgun.TubeMagazineCapacity}");
    }

    /// <summary>
    /// Sequentially reloads a sniper rifle: reload magazine if needed, then complete bolt cycle
    /// step by step (Issue #1337). Each bolt step plays its sound and waits.
    /// </summary>
    private async Task FineMotorSkillsReloadSniperAsync(SniperRifle sniper)
    {
        // First, reload magazine if needed
        if (sniper.CurrentAmmo < (sniper.WeaponData?.MagazineSize ?? 0) && sniper.ReserveAmmo > 0)
        {
            sniper.InstantReload();
            LogToFile($"[Player.FineMotorSkills] Sniper rifle magazine reloaded: {sniper.CurrentAmmo} rounds");

            // Wait between reload and bolt cycle
            if (FineMotorSkillsStageDelay > 0)
            {
                await ToSignal(GetTree().CreateTimer(FineMotorSkillsStageDelay), "timeout");
            }
        }

        // Then complete bolt cycle step by step if needed
        if (sniper.NeedsBoltCycle)
        {
            await sniper.FineBoltCycleAsync(FineMotorSkillsStageDelay);
            LogToFile("[Player.FineMotorSkills] Sniper rifle bolt cycle completed");
        }

        LogToFile($"[Player.FineMotorSkills] Sniper rifle combat-ready: {sniper.CurrentAmmo} rounds, bolt={sniper.IsBoltReady}");
    }

    /// <summary>
    /// Instantly reloads a standard weapon (rifle, pistol, SMG): swaps to fullest magazine.
    /// Standard weapons don't have sequential stages — they reload in one step.
    /// </summary>
    private void FineMotorSkillsReloadStandard(BaseWeapon weapon)
    {
        if (weapon.CurrentAmmo < (weapon.WeaponData?.MagazineSize ?? 0) && weapon.ReserveAmmo > 0)
        {
            weapon.InstantReload();

            // Play reload sound
            var audioManager = GetNodeOrNull("/root/AudioManager");
            if (audioManager != null && audioManager.HasMethod("play_reload_full"))
            {
                audioManager.Call("play_reload_full", GlobalPosition);
            }

            LogToFile($"[Player.FineMotorSkills] Standard weapon reloaded: {weapon.CurrentAmmo} rounds");
        }
        else
        {
            LogToFile("[Player.FineMotorSkills] Standard weapon already full or no spare ammo");
        }
    }

    #endregion

    #region Dash Active Item (Issue #1071)

    /// <summary>Reference to the instantiated DashEffect node (GDScript).</summary>
    private Node? _dashEffect = null;

    /// <summary>Whether the dash active item is currently equipped.</summary>
    private bool _dashEquipped = false;

    /// <summary>Path to the DashEffect scene.</summary>
    private const string DashEffectScenePath = "res://scenes/effects/DashEffect.tscn";

    /// <summary>
    /// Initialize dash active item by checking ActiveItemManager and instantiating the DashEffect scene.
    /// </summary>
    private void InitDash()
    {
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager == null)
        {
            LogToFile("[Player.Dash] ActiveItemManager not found");
            return;
        }

        if (!activeItemManager.HasMethod("has_dash"))
        {
            LogToFile("[Player.Dash] ActiveItemManager missing has_dash method");
            return;
        }

        bool hasDash = (bool)activeItemManager.Call("has_dash");
        if (!hasDash)
        {
            LogToFile("[Player.Dash] No dash selected in ActiveItemManager");
            return;
        }

        if (!ResourceLoader.Exists(DashEffectScenePath))
        {
            LogToFile($"[Player.Dash] DashEffect scene not found: {DashEffectScenePath}");
            return;
        }

        var scene = GD.Load<PackedScene>(DashEffectScenePath);
        if (scene == null)
        {
            LogToFile("[Player.Dash] Failed to load DashEffect scene");
            return;
        }

        _dashEffect = scene.Instantiate();
        AddChild(_dashEffect);
        _dashEffect.Call("initialize", this);
        _dashEquipped = true;
        LogToFile("[Player.Dash] Initialized — 3 charges, cooldown only after all charges spent");
    }

    /// <summary>
    /// Handle dash input: press Space to dash in movement direction (Issue #1071).
    /// </summary>
    private void HandleDashInput()
    {
        if (!_dashEquipped || _dashEffect == null)
        {
            return;
        }

        if (!Input.IsActionJustPressed("flashlight_toggle"))
        {
            return;
        }

        // Issue #1036: Block active item use when jammed
        if (IsActiveItemJammedVerbose())
        {
            LogToFile("[Player.Dash] Space blocked by Radio Jammer (Issue #1036)");
            return;
        }

        // Always dash toward aim/cursor direction (not movement direction)
        Vector2 dir = (GetGlobalMousePosition() - GlobalPosition).Normalized();

        _dashEffect.Call("activate", dir);
    }

    /// <summary>
    /// Check if the player is currently mid-dash (immune to damage).
    /// Called by the damage pipeline and movement override.
    /// </summary>
    public bool IsDashActive()
    {
        if (!_dashEquipped || _dashEffect == null)
            return false;
        if (!IsInstanceValid(_dashEffect))
            return false;
        return (bool)_dashEffect.Call("is_dashing");
    }

    #endregion
}
