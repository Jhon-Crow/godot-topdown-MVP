using Godot;
using System.Collections.Generic;

namespace GodotTopDownTemplate.Autoload
{
    /// <summary>
    /// Autoload singleton for recording and playing back game replays.
    ///
    /// Records entity positions, rotations, and key events each physics frame.
    /// Provides playback functionality to watch completed levels.
    ///
    /// This is a C# rewrite of the GDScript replay_system.gd to fix
    /// Godot 4.3 binary tokenization bugs that prevent GDScript autoloads
    /// from loading correctly in exported builds (godotengine/godot#94150,
    /// godotengine/godot#96065).
    ///
    /// Recording captures:
    /// - Player position, rotation, velocity, and model state (aim rotation, scale)
    /// - Enemy positions, rotations, velocities, model rotations, and alive state
    /// - Bullet positions and rotations (scanned from level root Area2D children)
    /// - Grenade positions
    /// - Shooting events for muzzle flash replay
    /// - Enemy hit directions for death animation replay
    ///
    /// Playback recreates the visual representation including:
    /// - Player weapon sprite on ghost (detected from live player)
    /// - Procedural walking animation with correct base positions
    /// - Aiming rotation and sprite flipping
    /// - Death fall animation (body displacement + rotation + fade)
    /// - Muzzle flashes and bullet tracers
    /// </summary>
    [GlobalClass]
    public partial class ReplayManager : Node
    {
        /// <summary>Recording interval in seconds (physics frames).</summary>
        private const float RecordInterval = 1.0f / 60.0f;

        /// <summary>Maximum recording duration in seconds (prevent memory issues).</summary>
        private const float MaxRecordingDuration = 300.0f;

        /// <summary>Walking animation speed multiplier (matches player.gd walk_anim_speed).</summary>
        private const float WalkAnimSpeed = 12.0f;

        /// <summary>Walking animation intensity (matches player.gd walk_anim_intensity).</summary>
        private const float WalkAnimIntensity = 1.0f;

        /// <summary>Minimum velocity magnitude to trigger walking animation.</summary>
        private const float WalkThreshold = 10.0f;

        /// <summary>Duration of the death fall+fade effect in seconds.</summary>
        private const float DeathFadeDuration = 0.8f;

        /// <summary>Death fall displacement in pixels (matches death_animation_component.gd).</summary>
        private const float DeathFallDistance = 25.0f;

        /// <summary>Duration of the muzzle flash effect in seconds.</summary>
        private const float MuzzleFlashDuration = 0.05f;

        /// <summary>Collision layer for bullets (layer 16 = bit 4, value 16).</summary>
        private const uint BulletCollisionLayer = 16;

        /// <summary>All recorded frames for the current/last level.</summary>
        private readonly List<FrameData> _frames = new();

        /// <summary>Current recording time.</summary>
        private float _recordingTime;

        /// <summary>Whether we are currently recording.</summary>
        private bool _isRecording;

        /// <summary>Whether we are currently playing back.</summary>
        private bool _isPlayingBack;

        /// <summary>Whether playback ending is scheduled.</summary>
        private bool _playbackEnding;

        /// <summary>Timer for playback end delay.</summary>
        private float _playbackEndTimer;

        /// <summary>Current playback frame index.</summary>
        private int _playbackFrame;

        /// <summary>Playback speed multiplier.</summary>
        private float _playbackSpeed = 1.0f;

        /// <summary>Accumulated time for playback interpolation.</summary>
        private float _playbackTime;

        /// <summary>Accumulated walk animation time for ghosts during playback.</summary>
        private float _ghostPlayerWalkAnimTime;
        private readonly List<float> _ghostEnemyWalkAnimTimes = new();

        /// <summary>Tracks whether each ghost enemy was alive in previous frame (for death effect).</summary>
        private readonly List<bool> _ghostEnemyPrevAlive = new();

        /// <summary>Death fade timers for ghost enemies (0 = no fade active).</summary>
        private readonly List<float> _ghostEnemyDeathTimers = new();

        /// <summary>Death fall start positions for ghost enemies (recorded at moment of death).</summary>
        private readonly List<Vector2> _ghostEnemyDeathStartPos = new();

        /// <summary>Death fall direction for ghost enemies (from recorded hit direction).</summary>
        private readonly List<Vector2> _ghostEnemyDeathDir = new();

        /// <summary>Reference to the level node being recorded.</summary>
        private Node2D? _levelNode;

        /// <summary>Reference to the player node.</summary>
        private Node2D? _player;

        /// <summary>References to enemy nodes.</summary>
        private readonly List<Node> _enemies = new();

        /// <summary>Detected player weapon texture path for ghost creation.</summary>
        private string _playerWeaponTexturePath = "res://assets/sprites/weapons/m16_rifle_topdown.png";

        /// <summary>Detected weapon sprite offset for ghost creation.</summary>
        private Vector2 _playerWeaponSpriteOffset = new(20, 0);

        /// <summary>Replay ghost nodes.</summary>
        private Node2D? _ghostPlayer;
        private readonly List<Node2D> _ghostEnemies = new();
        private readonly List<Node2D> _ghostBullets = new();
        private readonly List<Node2D> _ghostGrenades = new();

        /// <summary>Active muzzle flash nodes during playback.</summary>
        private readonly List<(Node2D Node, float Timer)> _activeMuzzleFlashes = new();

        /// <summary>Replay UI overlay.</summary>
        private CanvasLayer? _replayUi;

        /// <summary>Signal emitted when replay playback ends.</summary>
        [Signal] public delegate void ReplayEndedEventHandler();

        /// <summary>Signal emitted when replay playback starts.</summary>
        [Signal] public delegate void ReplayStartedEventHandler();

        /// <summary>Signal emitted when playback progress changes.</summary>
        [Signal] public delegate void PlaybackProgressEventHandler(float currentTime, float totalTime);

        /// <summary>
        /// Frame data stored as a simple class to avoid Dictionary overhead.
        /// </summary>
        private class FrameData
        {
            public float Time;
            public Vector2 PlayerPosition;
            public float PlayerRotation;
            public Vector2 PlayerVelocity;
            public float PlayerModelRotation;
            public Vector2 PlayerModelScale = Vector2.One;
            public bool PlayerAlive = true;
            public bool PlayerShooting;
            public List<EnemyFrameData> Enemies = new();
            public List<ProjectileFrameData> Bullets = new();
            public List<Vector2> Grenades = new();
        }

        private class EnemyFrameData
        {
            public Vector2 Position;
            public float Rotation;
            public Vector2 Velocity;
            public float ModelRotation;
            public Vector2 ModelScale = Vector2.One;
            public bool Alive = true;
            public bool Shooting;
            public Vector2 LastHitDirection = Vector2.Right;
        }

        private class ProjectileFrameData
        {
            public Vector2 Position;
            public float Rotation;
        }

        public override void _Ready()
        {
            ProcessMode = ProcessModeEnum.Always;
            LogToFile("ReplayManager ready (C# version loaded and _Ready called)");
        }

        public override void _PhysicsProcess(double delta)
        {
            if (_isRecording)
            {
                RecordFrame((float)delta);
            }
            else if (_playbackEnding)
            {
                _playbackEndTimer -= (float)delta;
                if (_playbackEndTimer <= 0.0f)
                {
                    _playbackEnding = false;
                    StopPlayback();
                }
            }
            else if (_isPlayingBack)
            {
                PlaybackFrameUpdate((float)delta);
            }
        }

        // ============================================================
        // Public API — PascalCase (C# convention)
        // GDScript callers must also use PascalCase for user-defined methods.
        // ============================================================

        /// <summary>
        /// Starts recording a new replay for the given level.
        /// </summary>
        public void StartRecording(Node2D level, Node2D player, Godot.Collections.Array enemies)
        {
            _frames.Clear();
            _recordingTime = 0.0f;
            _isRecording = true;
            _isPlayingBack = false;
            _levelNode = level;
            _player = player;
            _enemies.Clear();
            foreach (var enemy in enemies)
            {
                _enemies.Add(enemy.As<Node>());
            }

            // Detect player weapon for ghost creation later
            DetectPlayerWeapon(player);

            var playerName = player?.Name ?? "NULL";
            var playerValid = player != null && IsInstanceValid(player);
            var levelName = level?.Name ?? "NULL";

            LogToFile("=== REPLAY RECORDING STARTED ===");
            LogToFile($"Level: {levelName}");
            LogToFile($"Player: {playerName} (valid: {playerValid})");
            LogToFile($"Enemies count: {_enemies.Count}");
            LogToFile($"Detected weapon texture: {_playerWeaponTexturePath}");

            for (int i = 0; i < _enemies.Count; i++)
            {
                var enemy = _enemies[i];
                if (enemy != null && IsInstanceValid(enemy))
                    LogToFile($"  Enemy {i}: {enemy.Name}");
                else
                    LogToFile($"  Enemy {i}: INVALID");
            }

            GD.Print($"[ReplayManager] Recording started: Level={levelName}, Player={playerName}, Enemies={_enemies.Count}");
        }

        /// <summary>
        /// Stops recording and saves the replay data.
        /// </summary>
        public void StopRecording()
        {
            if (!_isRecording)
            {
                LogToFile("stop_recording called but was not recording");
                GD.Print("[ReplayManager] stop_recording called but was not recording");
                return;
            }

            _isRecording = false;
            LogToFile("=== REPLAY RECORDING STOPPED ===");
            LogToFile($"Total frames recorded: {_frames.Count}");
            LogToFile($"Total duration: {_recordingTime:F2}s");
            LogToFile($"has_replay() will return: {_frames.Count > 0}");
            GD.Print($"[ReplayManager] Recording stopped: {_frames.Count} frames, {_recordingTime:F2}s duration");
        }

        /// <summary>
        /// Returns true if there is a recorded replay available.
        /// </summary>
        public bool HasReplay()
        {
            return _frames.Count > 0;
        }

        /// <summary>
        /// Returns the duration of the recorded replay in seconds.
        /// </summary>
        public float GetReplayDuration()
        {
            if (_frames.Count == 0) return 0.0f;
            return _frames[^1].Time;
        }

        /// <summary>
        /// Starts playback of the recorded replay.
        /// </summary>
        public void StartPlayback(Node2D level)
        {
            if (_frames.Count == 0)
            {
                LogToFile("Cannot start playback: no frames recorded");
                return;
            }

            _isPlayingBack = true;
            _isRecording = false;
            _playbackEnding = false;
            _playbackEndTimer = 0.0f;
            _playbackFrame = 0;
            _playbackTime = 0.0f;
            _playbackSpeed = 1.0f;
            _ghostPlayerWalkAnimTime = 0.0f;
            _levelNode = level;

            CreateGhostEntities(level);
            CreateReplayUi(level);

            level.GetTree().Paused = true;

            EmitSignal(SignalName.ReplayStarted);
            LogToFile($"Started replay playback. Frames: {_frames.Count}, Duration: {GetReplayDuration():F2}s");
        }

        /// <summary>
        /// Stops playback and cleans up.
        /// </summary>
        public void StopPlayback()
        {
            if (!_isPlayingBack && !_playbackEnding) return;

            _isPlayingBack = false;
            _playbackEnding = false;
            _playbackEndTimer = 0.0f;

            CleanupGhostEntities();
            CleanupMuzzleFlashes();

            if (_replayUi != null && IsInstanceValid(_replayUi))
            {
                _replayUi.QueueFree();
                _replayUi = null;
            }

            if (_levelNode != null && IsInstanceValid(_levelNode))
                _levelNode.GetTree().Paused = false;

            EmitSignal(SignalName.ReplayEnded);
            LogToFile("Stopped replay playback");
        }

        /// <summary>
        /// Sets the playback speed.
        /// </summary>
        public void SetPlaybackSpeed(float speed)
        {
            _playbackSpeed = Mathf.Clamp(speed, 0.25f, 4.0f);
            LogToFile($"Playback speed set to {_playbackSpeed:F2}x");
        }

        /// <summary>
        /// Gets the current playback speed.
        /// </summary>
        public float GetPlaybackSpeed() => _playbackSpeed;

        /// <summary>
        /// Returns whether replay is currently playing.
        /// </summary>
        public bool IsReplaying() => _isPlayingBack;

        /// <summary>
        /// Returns whether replay is currently recording.
        /// </summary>
        public bool IsRecording() => _isRecording;

        /// <summary>
        /// Clears the recorded replay data.
        /// </summary>
        public void ClearReplay()
        {
            _frames.Clear();
            _recordingTime = 0.0f;
            _isRecording = false;
            LogToFile("Replay data cleared");
        }

        /// <summary>
        /// Seeks to a specific time in the replay.
        /// </summary>
        public void SeekTo(float time)
        {
            if (_frames.Count == 0) return;

            time = Mathf.Clamp(time, 0.0f, GetReplayDuration());
            _playbackTime = time;

            for (int i = 0; i < _frames.Count; i++)
            {
                if (_frames[i].Time >= time)
                {
                    _playbackFrame = Mathf.Max(0, i - 1);
                    break;
                }
            }

            ApplyFrame(_frames[_playbackFrame], 0.0f);
        }

        // ============================================================
        // Weapon detection for ghost player
        // ============================================================

        /// <summary>
        /// Detects the weapon type equipped by the player and stores the
        /// texture path so the ghost player can display the correct weapon.
        /// Weapon children are added by level scripts (not baked in Player.tscn),
        /// so we must detect them at recording start.
        /// </summary>
        private void DetectPlayerWeapon(Node2D? player)
        {
            if (player == null || !IsInstanceValid(player))
            {
                _playerWeaponTexturePath = "res://assets/sprites/weapons/m16_rifle_topdown.png";
                _playerWeaponSpriteOffset = new Vector2(20, 0);
                return;
            }

            // Check for weapon children in order of specificity (matches player.gd logic)
            if (player.GetNodeOrNull("MiniUzi") != null)
            {
                _playerWeaponTexturePath = "res://assets/sprites/weapons/mini_uzi_topdown.png";
                _playerWeaponSpriteOffset = new Vector2(15, 0);
                LogToFile("Detected player weapon: Mini UZI");
            }
            else if (player.GetNodeOrNull("Shotgun") != null)
            {
                _playerWeaponTexturePath = "res://assets/sprites/weapons/shotgun_topdown.png";
                _playerWeaponSpriteOffset = new Vector2(20, 0);
                LogToFile("Detected player weapon: Shotgun");
            }
            else if (player.GetNodeOrNull("SniperRifle") != null)
            {
                _playerWeaponTexturePath = "res://assets/sprites/weapons/asvk_topdown.png";
                _playerWeaponSpriteOffset = new Vector2(25, 0);
                LogToFile("Detected player weapon: Sniper Rifle (ASVK)");
            }
            else if (player.GetNodeOrNull("SilencedPistol") != null)
            {
                _playerWeaponTexturePath = "res://assets/sprites/weapons/silenced_pistol_topdown.png";
                _playerWeaponSpriteOffset = new Vector2(15, 0);
                LogToFile("Detected player weapon: Silenced Pistol");
            }
            else
            {
                // Default: Assault Rifle (M16)
                _playerWeaponTexturePath = "res://assets/sprites/weapons/m16_rifle_topdown.png";
                _playerWeaponSpriteOffset = new Vector2(20, 0);
                LogToFile("Detected player weapon: Assault Rifle (default)");
            }
        }

        // ============================================================
        // Private recording logic
        // ============================================================

        private void RecordFrame(float delta)
        {
            _recordingTime += delta;

            if (_recordingTime > MaxRecordingDuration)
            {
                LogToFile("Max recording duration reached, stopping");
                StopRecording();
                return;
            }

            var frame = new FrameData { Time = _recordingTime };

            // Debug log every 60 frames
            if (_frames.Count % 60 == 0)
            {
                LogToFile($"Recording frame {_frames.Count} ({_recordingTime:F1}s): " +
                    $"player_valid={_player != null && IsInstanceValid(_player)}, enemies={_enemies.Count}");
            }

            // Record player state
            if (_player != null && IsInstanceValid(_player))
            {
                frame.PlayerPosition = _player.GlobalPosition;
                frame.PlayerRotation = _player.GlobalRotation;
                frame.PlayerAlive = true;

                // Record velocity for walking animation derivation
                if (_player is CharacterBody2D playerBody)
                    frame.PlayerVelocity = playerBody.Velocity;

                // Record PlayerModel rotation and scale (for aim direction and flip)
                var playerModel = _player.GetNodeOrNull<Node2D>("PlayerModel");
                if (playerModel != null)
                {
                    frame.PlayerModelRotation = playerModel.GlobalRotation;
                    frame.PlayerModelScale = playerModel.Scale;
                }

                // Check alive state (GDScript or C#)
                var isAliveGd = _player.Get("_is_alive");
                if (isAliveGd.VariantType != Variant.Type.Nil)
                    frame.PlayerAlive = (bool)isAliveGd;
                else
                {
                    var isAliveCSharp = _player.Get("IsAlive");
                    if (isAliveCSharp.VariantType != Variant.Type.Nil)
                        frame.PlayerAlive = (bool)isAliveCSharp;
                }

                // Detect shooting by checking if new bullets appeared this frame
                if (_frames.Count > 0)
                {
                    var prevBullets = _frames[^1].Bullets.Count;
                    int currentBullets = CountCurrentProjectiles();
                    frame.PlayerShooting = currentBullets > prevBullets;
                }
            }
            else
            {
                frame.PlayerAlive = false;
            }

            // Record enemy states
            foreach (var enemy in _enemies)
            {
                if (enemy != null && IsInstanceValid(enemy) && enemy is Node2D enemy2D)
                {
                    var enemyData = new EnemyFrameData
                    {
                        Position = enemy2D.GlobalPosition,
                        Rotation = enemy2D.GlobalRotation,
                        Alive = true
                    };

                    // Record velocity for walking animation
                    if (enemy is CharacterBody2D enemyBody)
                        enemyData.Velocity = enemyBody.Velocity;

                    // Record EnemyModel rotation and scale (for aim direction and flip)
                    var enemyModel = enemy2D.GetNodeOrNull<Node2D>("EnemyModel");
                    if (enemyModel != null)
                    {
                        enemyData.ModelRotation = enemyModel.GlobalRotation;
                        enemyData.ModelScale = enemyModel.Scale;
                    }

                    if (enemy.HasMethod("is_alive"))
                        enemyData.Alive = (bool)enemy.Call("is_alive");
                    else
                    {
                        var aliveVar = enemy.Get("_is_alive");
                        if (aliveVar.VariantType != Variant.Type.Nil)
                            enemyData.Alive = (bool)aliveVar;
                    }

                    // Record hit direction for death animation
                    var hitDirVar = enemy.Get("_last_hit_direction");
                    if (hitDirVar.VariantType != Variant.Type.Nil)
                        enemyData.LastHitDirection = (Vector2)hitDirVar;

                    // Check if enemy is shooting
                    var isShootingVar = enemy.Get("_is_shooting");
                    if (isShootingVar.VariantType != Variant.Type.Nil)
                        enemyData.Shooting = (bool)isShootingVar;

                    frame.Enemies.Add(enemyData);
                }
                else
                {
                    frame.Enemies.Add(new EnemyFrameData { Alive = false });
                }
            }

            // Record projectiles (bullets) — scan level root children for Area2D
            // with collision_layer 16 (bullets are added directly to current_scene
            // by weapon scripts, NOT to an Entities/Projectiles container)
            if (_levelNode != null && IsInstanceValid(_levelNode))
            {
                foreach (var child in _levelNode.GetChildren())
                {
                    if (child is Area2D area2D && (area2D.CollisionLayer & BulletCollisionLayer) != 0)
                    {
                        frame.Bullets.Add(new ProjectileFrameData
                        {
                            Position = area2D.GlobalPosition,
                            Rotation = area2D.GlobalRotation
                        });
                    }
                }

                // Record grenades
                var grenades = _levelNode.GetTree().GetNodesInGroup("grenades");
                foreach (var grenade in grenades)
                {
                    if (grenade is Node2D gren2D)
                    {
                        frame.Grenades.Add(gren2D.GlobalPosition);
                    }
                }
            }

            _frames.Add(frame);
        }

        /// <summary>Counts current bullet projectiles in the level for shooting detection.</summary>
        private int CountCurrentProjectiles()
        {
            if (_levelNode == null || !IsInstanceValid(_levelNode)) return 0;
            int count = 0;
            foreach (var child in _levelNode.GetChildren())
            {
                if (child is Area2D area2D && (area2D.CollisionLayer & BulletCollisionLayer) != 0)
                    count++;
            }
            return count;
        }

        // ============================================================
        // Private playback logic
        // ============================================================

        private void PlaybackFrameUpdate(float delta)
        {
            if (_frames.Count == 0)
            {
                StopPlayback();
                return;
            }

            _playbackTime += delta * _playbackSpeed;

            EmitSignal(SignalName.PlaybackProgress, _playbackTime, GetReplayDuration());

            // Update muzzle flash timers
            UpdateMuzzleFlashes(delta);

            if (_playbackTime >= GetReplayDuration())
            {
                _playbackTime = GetReplayDuration();
                ApplyFrame(_frames[^1], delta);
                _playbackEnding = true;
                _playbackEndTimer = 0.5f;
                _isPlayingBack = false;
                return;
            }

            while (_playbackFrame < _frames.Count - 1 && _frames[_playbackFrame + 1].Time <= _playbackTime)
                _playbackFrame++;

            ApplyFrame(_frames[_playbackFrame], delta);
        }

        private void ApplyFrame(FrameData frame, float delta)
        {
            // Update ghost player
            if (_ghostPlayer != null && IsInstanceValid(_ghostPlayer))
            {
                _ghostPlayer.GlobalPosition = frame.PlayerPosition;
                _ghostPlayer.GlobalRotation = frame.PlayerRotation;
                _ghostPlayer.Visible = frame.PlayerAlive;

                // Apply PlayerModel rotation and scale for aiming direction
                var ghostModel = _ghostPlayer.GetNodeOrNull<Node2D>("PlayerModel");
                if (ghostModel != null)
                {
                    ghostModel.GlobalRotation = frame.PlayerModelRotation;
                    ghostModel.Scale = frame.PlayerModelScale;

                    // Apply procedural walking animation based on velocity
                    ApplyWalkAnimation(ghostModel, frame.PlayerVelocity, delta, ref _ghostPlayerWalkAnimTime, true);
                }

                // Spawn muzzle flash if player was shooting this frame
                if (frame.PlayerShooting)
                {
                    SpawnMuzzleFlash(frame.PlayerPosition, frame.PlayerModelRotation);
                }
            }

            // Update ghost enemies
            int count = Mathf.Min(_ghostEnemies.Count, frame.Enemies.Count);
            for (int i = 0; i < count; i++)
            {
                var ghost = _ghostEnemies[i];
                var data = frame.Enemies[i];
                if (ghost == null || !IsInstanceValid(ghost)) continue;

                // Death effect: when alive transitions from true to false, start fall animation
                bool prevAlive = i < _ghostEnemyPrevAlive.Count && _ghostEnemyPrevAlive[i];
                if (prevAlive && !data.Alive)
                {
                    // Start death fall animation
                    if (i < _ghostEnemyDeathTimers.Count)
                        _ghostEnemyDeathTimers[i] = DeathFadeDuration;
                    if (i < _ghostEnemyDeathStartPos.Count)
                        _ghostEnemyDeathStartPos[i] = data.Position;
                    if (i < _ghostEnemyDeathDir.Count)
                        _ghostEnemyDeathDir[i] = data.LastHitDirection.Normalized();
                    // Flash red on death
                    ghost.Modulate = new Color(1.5f, 0.3f, 0.3f, 1.0f);
                }

                // Update death fall animation
                if (i < _ghostEnemyDeathTimers.Count && _ghostEnemyDeathTimers[i] > 0.0f)
                {
                    _ghostEnemyDeathTimers[i] -= delta * _playbackSpeed;
                    float t = Mathf.Clamp(_ghostEnemyDeathTimers[i] / DeathFadeDuration, 0.0f, 1.0f);
                    // t goes from 1.0 (start) to 0.0 (end)
                    float progress = 1.0f - t;
                    // Ease-out curve for natural deceleration
                    float easedProgress = 1.0f - Mathf.Pow(1.0f - progress, 2.0f);

                    ghost.Visible = true;

                    // Displacement: body falls away from hit direction
                    Vector2 startPos = i < _ghostEnemyDeathStartPos.Count ? _ghostEnemyDeathStartPos[i] : data.Position;
                    Vector2 fallDir = i < _ghostEnemyDeathDir.Count ? _ghostEnemyDeathDir[i] : Vector2.Right;
                    ghost.GlobalPosition = startPos + fallDir * DeathFallDistance * easedProgress;

                    // Body rotation during fall (rotate toward fall direction)
                    var enemyModel = ghost.GetNodeOrNull<Node2D>("EnemyModel");
                    if (enemyModel != null)
                    {
                        float fallAngle = fallDir.Angle();
                        float bodyRot = fallAngle * 0.5f * easedProgress;
                        enemyModel.Rotation = bodyRot;

                        // Arm swing during fall
                        var leftArm = enemyModel.GetNodeOrNull<Node2D>("LeftArm");
                        var rightArm = enemyModel.GetNodeOrNull<Node2D>("RightArm");
                        float armAngle = Mathf.DegToRad(30.0f) * easedProgress;
                        if (leftArm != null) leftArm.Rotation = armAngle;
                        if (rightArm != null) rightArm.Rotation = -armAngle;
                    }

                    // Color: red flash fades to dark semi-transparent
                    ghost.Modulate = new Color(
                        Mathf.Lerp(0.3f, 1.5f, t),
                        Mathf.Lerp(0.3f, 0.3f, t),
                        Mathf.Lerp(0.3f, 0.3f, t),
                        Mathf.Lerp(0.0f, 1.0f, t)
                    );

                    if (_ghostEnemyDeathTimers[i] <= 0.0f)
                    {
                        ghost.Visible = false;
                        ghost.Modulate = new Color(1.0f, 1.0f, 1.0f, 0.9f);
                    }
                }
                else if (!data.Alive && (i >= _ghostEnemyDeathTimers.Count || _ghostEnemyDeathTimers[i] <= 0.0f))
                {
                    ghost.Visible = false;
                }
                else if (data.Alive)
                {
                    ghost.Visible = true;
                    ghost.GlobalPosition = data.Position;
                    ghost.GlobalRotation = data.Rotation;

                    // Apply EnemyModel rotation and scale for aiming direction
                    var enemyModel = ghost.GetNodeOrNull<Node2D>("EnemyModel");
                    if (enemyModel != null)
                    {
                        enemyModel.GlobalRotation = data.ModelRotation;
                        enemyModel.Scale = data.ModelScale;
                        enemyModel.Rotation = 0; // Reset any death rotation

                        // Reset arm rotations from any prior death animation
                        var leftArm = enemyModel.GetNodeOrNull<Node2D>("LeftArm");
                        var rightArm = enemyModel.GetNodeOrNull<Node2D>("RightArm");
                        if (leftArm != null) leftArm.Rotation = 0;
                        if (rightArm != null) rightArm.Rotation = 0;

                        // Apply procedural walking animation
                        float walkTime = i < _ghostEnemyWalkAnimTimes.Count ? _ghostEnemyWalkAnimTimes[i] : 0.0f;
                        ApplyWalkAnimation(enemyModel, data.Velocity, delta, ref walkTime, false);
                        if (i < _ghostEnemyWalkAnimTimes.Count)
                            _ghostEnemyWalkAnimTimes[i] = walkTime;
                    }
                }

                if (i < _ghostEnemyPrevAlive.Count)
                    _ghostEnemyPrevAlive[i] = data.Alive;

                // Enemy muzzle flash
                if (data.Shooting && data.Alive)
                {
                    SpawnMuzzleFlash(data.Position, data.ModelRotation);
                }
            }

            // Update ghost bullets
            UpdateGhostProjectiles(frame.Bullets, _ghostBullets, "bullet");

            // Update ghost grenades — convert grenades to projectile data
            var grenadeData = new List<ProjectileFrameData>();
            foreach (var pos in frame.Grenades)
                grenadeData.Add(new ProjectileFrameData { Position = pos, Rotation = 0 });
            UpdateGhostProjectiles(grenadeData, _ghostGrenades, "grenade");
        }

        /// <summary>
        /// Applies procedural walking animation to a model based on velocity.
        /// Uses the same sine wave formulas as player.gd and enemy.gd.
        /// Uses absolute positioning from base positions to prevent arm drift.
        /// </summary>
        private void ApplyWalkAnimation(Node2D model, Vector2 velocity, float delta, ref float walkAnimTime, bool isPlayer)
        {
            float speed = velocity.Length();

            var body = model.GetNodeOrNull<Node2D>("Body");
            var head = model.GetNodeOrNull<Node2D>("Head");
            var leftArm = model.GetNodeOrNull<Node2D>("LeftArm");
            var rightArm = model.GetNodeOrNull<Node2D>("RightArm");

            // Base positions from Player.tscn/Enemy.tscn scene files
            // Player: Body(-4,0), Head(-6,-2), LeftArm(24,6), RightArm(-2,6)
            // Enemy:  Body(-4,0), Head(-6,-2), LeftArm(24,6), RightArm(-2,6)
            float baseBodyY = 0.0f;
            float baseHeadY = -2.0f;
            float baseLeftArmX = 24.0f;
            float baseRightArmX = -2.0f;

            if (speed > WalkThreshold && delta > 0.0f)
            {
                float speedFactor = Mathf.Clamp(speed / 200.0f, 0.5f, 1.5f);
                walkAnimTime += delta * _playbackSpeed * WalkAnimSpeed * speedFactor;

                float bodyBob = Mathf.Sin(walkAnimTime * 2.0f) * 1.5f * WalkAnimIntensity;
                float headBob = Mathf.Sin(walkAnimTime * 2.0f) * 0.8f * WalkAnimIntensity;
                float armSwing = Mathf.Sin(walkAnimTime) * 3.0f * WalkAnimIntensity;

                if (body != null) body.Position = new Vector2(body.Position.X, baseBodyY + bodyBob);
                if (head != null) head.Position = new Vector2(head.Position.X, baseHeadY + headBob);
                // Use absolute position: base + offset (prevents drift)
                if (leftArm != null) leftArm.Position = new Vector2(baseLeftArmX + armSwing, leftArm.Position.Y);
                if (rightArm != null) rightArm.Position = new Vector2(baseRightArmX - armSwing, rightArm.Position.Y);
            }
            else
            {
                walkAnimTime = 0.0f;
                // Reset to base positions
                if (body != null) body.Position = new Vector2(body.Position.X, baseBodyY);
                if (head != null) head.Position = new Vector2(head.Position.X, baseHeadY);
                if (leftArm != null) leftArm.Position = new Vector2(baseLeftArmX, leftArm.Position.Y);
                if (rightArm != null) rightArm.Position = new Vector2(baseRightArmX, rightArm.Position.Y);
            }
        }

        /// <summary>
        /// Spawns a brief muzzle flash visual at the given position and direction.
        /// </summary>
        private void SpawnMuzzleFlash(Vector2 position, float rotation)
        {
            if (_levelNode == null || !IsInstanceValid(_levelNode)) return;
            var ghostContainer = _levelNode.GetNodeOrNull<Node2D>("ReplayGhosts");
            if (ghostContainer == null) return;

            var flash = new Node2D();
            flash.Name = "MuzzleFlash";
            flash.ProcessMode = ProcessModeEnum.Always;
            flash.GlobalPosition = position + new Vector2(Mathf.Cos(rotation), Mathf.Sin(rotation)) * 40.0f;
            flash.GlobalRotation = rotation;

            // Create flash sprite
            var sprite = new Sprite2D();
            var texture = new GradientTexture2D();
            texture.Width = 16;
            texture.Height = 8;
            texture.Fill = GradientTexture2D.FillEnum.Radial;
            texture.FillFrom = new Vector2(0.5f, 0.5f);
            texture.FillTo = new Vector2(1.0f, 0.5f);
            var gradient = new Gradient();
            gradient.SetColor(0, new Color(1.0f, 1.0f, 0.8f, 1.0f));
            gradient.SetColor(1, new Color(1.0f, 0.6f, 0.1f, 0.0f));
            texture.Gradient = gradient;
            sprite.Texture = texture;
            sprite.Scale = new Vector2(2.0f, 2.0f);
            flash.AddChild(sprite);

            ghostContainer.AddChild(flash);
            _activeMuzzleFlashes.Add((flash, MuzzleFlashDuration));
        }

        /// <summary>Updates and removes expired muzzle flashes.</summary>
        private void UpdateMuzzleFlashes(float delta)
        {
            for (int i = _activeMuzzleFlashes.Count - 1; i >= 0; i--)
            {
                var (node, timer) = _activeMuzzleFlashes[i];
                float newTimer = timer - delta * _playbackSpeed;
                if (newTimer <= 0.0f || node == null || !IsInstanceValid(node))
                {
                    if (node != null && IsInstanceValid(node))
                        node.QueueFree();
                    _activeMuzzleFlashes.RemoveAt(i);
                }
                else
                {
                    // Fade out
                    float t = newTimer / MuzzleFlashDuration;
                    node.Modulate = new Color(1.0f, 1.0f, 1.0f, t);
                    _activeMuzzleFlashes[i] = (node, newTimer);
                }
            }
        }

        /// <summary>Cleans up all active muzzle flashes.</summary>
        private void CleanupMuzzleFlashes()
        {
            foreach (var (node, _) in _activeMuzzleFlashes)
            {
                if (node != null && IsInstanceValid(node))
                    node.QueueFree();
            }
            _activeMuzzleFlashes.Clear();
        }

        private void UpdateGhostProjectiles(List<ProjectileFrameData> data, List<Node2D> ghosts, string type)
        {
            // Remove excess
            while (ghosts.Count > data.Count)
            {
                var last = ghosts[^1];
                ghosts.RemoveAt(ghosts.Count - 1);
                if (last != null && IsInstanceValid(last))
                    last.QueueFree();
            }

            // Add new ghosts
            while (ghosts.Count < data.Count)
            {
                var ghost = CreateProjectileGhost(type);
                if (ghost != null)
                    ghosts.Add(ghost);
            }

            // Update positions
            int count = Mathf.Min(ghosts.Count, data.Count);
            for (int i = 0; i < count; i++)
            {
                var ghost = ghosts[i];
                var d = data[i];
                if (ghost != null && IsInstanceValid(ghost))
                {
                    ghost.GlobalPosition = d.Position;
                    ghost.GlobalRotation = d.Rotation;
                    ghost.Visible = true;
                }
            }
        }

        // ============================================================
        // Ghost entity creation
        // ============================================================

        private void CreateGhostEntities(Node2D level)
        {
            CleanupGhostEntities();
            _ghostEnemyWalkAnimTimes.Clear();
            _ghostEnemyPrevAlive.Clear();
            _ghostEnemyDeathTimers.Clear();
            _ghostEnemyDeathStartPos.Clear();
            _ghostEnemyDeathDir.Clear();

            var ghostContainer = new Node2D();
            ghostContainer.Name = "ReplayGhosts";
            ghostContainer.ProcessMode = ProcessModeEnum.Always;
            level.AddChild(ghostContainer);

            _ghostPlayer = CreatePlayerGhost();
            if (_ghostPlayer != null)
            {
                ghostContainer.AddChild(_ghostPlayer);

                // Enable the ghost's Camera2D so it follows the ghost player during
                // replay. The original player's camera is disabled by HideOriginalEntities.
                var ghostCamera = _ghostPlayer.GetNodeOrNull<Camera2D>("Camera2D");
                if (ghostCamera != null)
                {
                    ghostCamera.ProcessMode = ProcessModeEnum.Always;
                    ghostCamera.SetProcess(true);
                    ghostCamera.SetPhysicsProcess(true);
                    ghostCamera.MakeCurrent();
                    LogToFile("Ghost player Camera2D activated for replay");
                }
            }

            if (_frames.Count > 0 && _frames[0].Enemies.Count > 0)
            {
                for (int i = 0; i < _frames[0].Enemies.Count; i++)
                {
                    var ghostEnemy = CreateEnemyGhost();
                    if (ghostEnemy != null)
                    {
                        ghostContainer.AddChild(ghostEnemy);
                        _ghostEnemies.Add(ghostEnemy);
                        _ghostEnemyWalkAnimTimes.Add(0.0f);
                        _ghostEnemyPrevAlive.Add(true);
                        _ghostEnemyDeathTimers.Add(0.0f);
                        _ghostEnemyDeathStartPos.Add(Vector2.Zero);
                        _ghostEnemyDeathDir.Add(Vector2.Right);
                    }
                }
            }

            HideOriginalEntities(level);
        }

        private Node2D? CreatePlayerGhost()
        {
            var playerScene = GD.Load<PackedScene>("res://scenes/characters/Player.tscn");
            if (playerScene != null)
            {
                var ghost = playerScene.Instantiate<Node2D>();
                ghost.Name = "GhostPlayer";
                ghost.ProcessMode = ProcessModeEnum.Always;
                DisableNodeProcessing(ghost);
                SetGhostModulate(ghost, new Color(1.0f, 1.0f, 1.0f, 0.9f));

                // Add weapon sprite to ghost player's WeaponMount
                // (weapons are NOT baked into Player.tscn — they are added dynamically by level scripts)
                AddWeaponSpriteToGhost(ghost);

                return ghost;
            }

            // Fallback: simple colored sprite
            var fallback = new Node2D();
            fallback.Name = "GhostPlayer";
            var sprite = new Sprite2D();
            var img = Image.CreateEmpty(16, 16, false, Image.Format.Rgba8);
            img.Fill(new Color(0.2f, 0.6f, 1.0f, 0.8f));
            sprite.Texture = ImageTexture.CreateFromImage(img);
            fallback.AddChild(sprite);
            return fallback;
        }

        /// <summary>
        /// Adds a weapon sprite to the ghost player's WeaponMount node.
        /// This is necessary because Player.tscn has an empty WeaponMount —
        /// actual weapon sprites are added by level scripts at runtime.
        /// </summary>
        private void AddWeaponSpriteToGhost(Node2D ghost)
        {
            var weaponMount = ghost.GetNodeOrNull<Node2D>("PlayerModel/WeaponMount");
            if (weaponMount == null)
            {
                LogToFile("WARNING: Ghost player has no PlayerModel/WeaponMount node");
                return;
            }

            var weaponTexture = GD.Load<Texture2D>(_playerWeaponTexturePath);
            if (weaponTexture == null)
            {
                LogToFile($"WARNING: Could not load weapon texture: {_playerWeaponTexturePath}");
                return;
            }

            var weaponSprite = new Sprite2D();
            weaponSprite.Name = "GhostWeaponSprite";
            weaponSprite.Texture = weaponTexture;
            weaponSprite.Offset = _playerWeaponSpriteOffset;
            weaponSprite.ZIndex = 1;
            weaponMount.AddChild(weaponSprite);

            LogToFile($"Added weapon sprite to ghost player: {_playerWeaponTexturePath}");
        }

        private Node2D? CreateEnemyGhost()
        {
            var enemyScene = GD.Load<PackedScene>("res://scenes/objects/Enemy.tscn");
            if (enemyScene != null)
            {
                var ghost = enemyScene.Instantiate<Node2D>();
                ghost.Name = "GhostEnemy";
                ghost.ProcessMode = ProcessModeEnum.Always;
                DisableNodeProcessing(ghost);
                SetGhostModulate(ghost, new Color(1.0f, 1.0f, 1.0f, 0.9f));
                return ghost;
            }

            // Fallback: simple colored sprite
            var fallback = new Node2D();
            fallback.Name = "GhostEnemy";
            var sprite = new Sprite2D();
            var img = Image.CreateEmpty(16, 16, false, Image.Format.Rgba8);
            img.Fill(new Color(1.0f, 0.2f, 0.2f, 0.8f));
            sprite.Texture = ImageTexture.CreateFromImage(img);
            fallback.AddChild(sprite);
            return fallback;
        }

        private Node2D? CreateProjectileGhost(string type)
        {
            var ghost = new Node2D();
            ghost.Name = "Ghost" + type.Capitalize();
            ghost.ProcessMode = ProcessModeEnum.Always;

            var sprite = new Sprite2D();

            if (type == "bullet")
            {
                var texture = new GradientTexture2D();
                texture.Width = 16;
                texture.Height = 4;
                texture.FillFrom = new Vector2(0, 0.5f);
                texture.FillTo = new Vector2(1, 0.5f);
                var gradient = new Gradient();
                gradient.SetColor(0, new Color(1.0f, 0.9f, 0.2f, 1.0f));
                gradient.SetColor(1, new Color(1.0f, 0.7f, 0.1f, 0.3f));
                texture.Gradient = gradient;
                sprite.Texture = texture;
            }
            else
            {
                var texture = new GradientTexture2D();
                texture.Width = 12;
                texture.Height = 12;
                texture.Fill = GradientTexture2D.FillEnum.Radial;
                var gradient = new Gradient();
                gradient.SetColor(0, new Color(0.2f, 0.5f, 0.2f, 1.0f));
                gradient.SetColor(1, new Color(0.1f, 0.3f, 0.1f, 0.5f));
                texture.Gradient = gradient;
                sprite.Texture = texture;
            }

            ghost.AddChild(sprite);

            if (_levelNode != null && IsInstanceValid(_levelNode))
            {
                var ghostContainer = _levelNode.GetNodeOrNull<Node2D>("ReplayGhosts");
                ghostContainer?.AddChild(ghost);
            }

            return ghost;
        }

        private void DisableNodeProcessing(Node node)
        {
            node.SetProcess(false);
            node.SetPhysicsProcess(false);
            node.SetProcessInput(false);
            node.SetProcessUnhandledInput(false);

            if (node.GetScript().VariantType != Variant.Type.Nil)
                node.SetScript(default(Variant));

            if (node is CollisionObject2D collisionObj)
            {
                collisionObj.CollisionLayer = 0;
                collisionObj.CollisionMask = 0;
            }

            foreach (var child in node.GetChildren())
                DisableNodeProcessing(child);
        }

        private void SetGhostModulate(Node node, Color color)
        {
            if (node is CanvasItem canvasItem)
                canvasItem.Modulate = color;

            foreach (var child in node.GetChildren())
                SetGhostModulate(child, color);
        }

        private void HideOriginalEntities(Node2D level)
        {
            var player = level.GetNodeOrNull<Node2D>("Entities/Player");
            if (player != null) player.Visible = false;

            var enemiesNode = level.GetNodeOrNull("Environment/Enemies");
            if (enemiesNode != null)
            {
                foreach (var enemy in enemiesNode.GetChildren())
                {
                    if (enemy is Node2D enemy2D)
                        enemy2D.Visible = false;
                }
            }

            // Hide any remaining bullet projectiles (direct children of level root)
            foreach (var child in level.GetChildren())
            {
                if (child is Area2D area2D && (area2D.CollisionLayer & BulletCollisionLayer) != 0)
                    area2D.Visible = false;
            }

            // Hide the score screen / UI overlay (CanvasLayer/UI) so the replay
            // ghosts in the game world are visible. The CanvasLayer renders on top
            // of the game world and would completely obscure the replay otherwise.
            var canvasLayer = level.GetNodeOrNull<CanvasLayer>("CanvasLayer");
            if (canvasLayer != null)
            {
                canvasLayer.Visible = false;
                LogToFile("Hidden CanvasLayer (score screen) for replay visibility");
            }
        }

        private void CleanupGhostEntities()
        {
            if (_ghostPlayer != null && IsInstanceValid(_ghostPlayer))
                _ghostPlayer.QueueFree();
            _ghostPlayer = null;

            foreach (var ghost in _ghostEnemies)
            {
                if (ghost != null && IsInstanceValid(ghost))
                    ghost.QueueFree();
            }
            _ghostEnemies.Clear();

            foreach (var ghost in _ghostBullets)
            {
                if (ghost != null && IsInstanceValid(ghost))
                    ghost.QueueFree();
            }
            _ghostBullets.Clear();

            foreach (var ghost in _ghostGrenades)
            {
                if (ghost != null && IsInstanceValid(ghost))
                    ghost.QueueFree();
            }
            _ghostGrenades.Clear();

            _ghostEnemyWalkAnimTimes.Clear();
            _ghostEnemyPrevAlive.Clear();
            _ghostEnemyDeathTimers.Clear();
            _ghostEnemyDeathStartPos.Clear();
            _ghostEnemyDeathDir.Clear();

            if (_levelNode != null && IsInstanceValid(_levelNode))
            {
                var ghostContainer = _levelNode.GetNodeOrNull("ReplayGhosts");
                ghostContainer?.QueueFree();
            }
        }

        // ============================================================
        // Replay UI
        // ============================================================

        private void CreateReplayUi(Node2D level)
        {
            _replayUi = new CanvasLayer();
            _replayUi.Name = "ReplayUI";
            _replayUi.Layer = 100;
            _replayUi.ProcessMode = ProcessModeEnum.Always;
            level.AddChild(_replayUi);

            // Close button (X) in top-right corner
            var closeBtn = new Button();
            closeBtn.Name = "CloseButton";
            closeBtn.Text = "\u2715";
            closeBtn.SetAnchorsPreset(Control.LayoutPreset.TopRight);
            closeBtn.OffsetLeft = -50;
            closeBtn.OffsetRight = -10;
            closeBtn.OffsetTop = 10;
            closeBtn.OffsetBottom = 50;
            closeBtn.AddThemeFontSizeOverride("font_size", 24);
            closeBtn.ProcessMode = ProcessModeEnum.Always;
            closeBtn.Pressed += OnExitReplayPressed;
            closeBtn.TooltipText = "Close replay (ESC)";
            _replayUi.AddChild(closeBtn);

            var container = new VBoxContainer();
            container.SetAnchorsPreset(Control.LayoutPreset.CenterBottom);
            container.OffsetLeft = -200;
            container.OffsetRight = 200;
            container.OffsetTop = -120;
            container.OffsetBottom = -20;
            container.AddThemeConstantOverride("separation", 10);
            _replayUi.AddChild(container);

            // Replay label
            var replayLabel = new Label();
            replayLabel.Text = "\u25b6 REPLAY";
            replayLabel.HorizontalAlignment = HorizontalAlignment.Center;
            replayLabel.AddThemeFontSizeOverride("font_size", 24);
            replayLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.8f, 0.2f, 1.0f));
            container.AddChild(replayLabel);

            // Progress bar
            var progressContainer = new HBoxContainer();
            progressContainer.AddThemeConstantOverride("separation", 10);
            container.AddChild(progressContainer);

            var timeLabel = new Label();
            timeLabel.Name = "TimeLabel";
            timeLabel.Text = "0:00";
            timeLabel.AddThemeFontSizeOverride("font_size", 16);
            progressContainer.AddChild(timeLabel);

            var progressBar = new ProgressBar();
            progressBar.Name = "ProgressBar";
            progressBar.CustomMinimumSize = new Vector2(300, 0);
            progressBar.MinValue = 0.0;
            progressBar.MaxValue = GetReplayDuration();
            progressBar.Value = 0.0;
            progressBar.ShowPercentage = false;
            progressContainer.AddChild(progressBar);

            var durationLabel = new Label();
            durationLabel.Name = "DurationLabel";
            float dur = GetReplayDuration();
            durationLabel.Text = $"{(int)dur / 60}:{(int)dur % 60:D2}";
            durationLabel.AddThemeFontSizeOverride("font_size", 16);
            progressContainer.AddChild(durationLabel);

            // Speed controls
            var speedContainer = new HBoxContainer();
            speedContainer.AddThemeConstantOverride("separation", 15);
            speedContainer.Alignment = BoxContainer.AlignmentMode.Center;
            container.AddChild(speedContainer);

            float[] speeds = { 0.5f, 1.0f, 2.0f, 4.0f };
            foreach (float speed in speeds)
            {
                var btn = new Button();
                btn.Text = speed < 1.0f ? $"{speed:F1}x" : $"{(int)speed}x";
                btn.CustomMinimumSize = new Vector2(50, 30);
                float capturedSpeed = speed;
                btn.Pressed += () => SetPlaybackSpeed(capturedSpeed);
                speedContainer.AddChild(btn);
            }

            // Exit button
            var exitBtn = new Button();
            exitBtn.Text = "Exit Replay (ESC)";
            exitBtn.CustomMinimumSize = new Vector2(150, 40);
            exitBtn.Pressed += OnExitReplayPressed;
            container.AddChild(exitBtn);

            PlaybackProgress += UpdateReplayUi;
        }

        private void UpdateReplayUi(float currentTime, float totalTime)
        {
            if (_replayUi == null || !IsInstanceValid(_replayUi)) return;

            var progressBar = _replayUi.GetNodeOrNull<ProgressBar>("VBoxContainer/HBoxContainer/ProgressBar");
            if (progressBar != null) progressBar.Value = currentTime;

            var timeLabel = _replayUi.GetNodeOrNull<Label>("VBoxContainer/HBoxContainer/TimeLabel");
            if (timeLabel != null)
                timeLabel.Text = $"{(int)currentTime / 60}:{(int)currentTime % 60:D2}";
        }

        private void OnExitReplayPressed()
        {
            StopPlayback();
            if (_levelNode != null && IsInstanceValid(_levelNode))
            {
                _levelNode.GetTree().Paused = false;
                _levelNode.GetTree().ReloadCurrentScene();
            }
        }

        public override void _Input(InputEvent @event)
        {
            if (!_isPlayingBack && !_playbackEnding) return;

            if (@event is InputEventKey key && key.Pressed)
            {
                switch (key.Keycode)
                {
                    case Key.Escape:
                        OnExitReplayPressed();
                        break;
                    case Key.Key1:
                        SetPlaybackSpeed(0.5f);
                        break;
                    case Key.Key2:
                        SetPlaybackSpeed(1.0f);
                        break;
                    case Key.Key3:
                        SetPlaybackSpeed(2.0f);
                        break;
                    case Key.Key4:
                        SetPlaybackSpeed(4.0f);
                        break;
                }
            }
        }

        // ============================================================
        // Logging
        // ============================================================

        private void LogToFile(string message)
        {
            var fileLogger = GetNodeOrNull("/root/FileLogger");
            if (fileLogger != null && fileLogger.HasMethod("log_info"))
                fileLogger.Call("log_info", "[ReplayManager] " + message);
            else
                GD.Print("[ReplayManager] " + message);
        }
    }
}
