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
    /// - Impact events (blood decals, bullet hits) for Memory mode
    ///
    /// Playback modes:
    /// - Ghost (default): red/black/white stylized filter, ghost entities
    /// - Memory: full color reproduction with all gameplay effects (blood, casings,
    ///   cinema effects, last chance, penultimate hit) and motion trails
    /// </summary>
    [GlobalClass]
    public partial class ReplayManager : Node
    {
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

        /// <summary>Number of trail segments for motion trail effect.</summary>
        private const int TrailSegments = 6;

        /// <summary>Time between trail segment updates in seconds.</summary>
        private const float TrailUpdateInterval = 0.03f;

        // ============================================================
        // Replay mode enum
        // ============================================================

        /// <summary>Replay viewing mode.</summary>
        public enum ReplayMode
        {
            Ghost,  // Red/black/white stylized filter
            Memory  // Full color with gameplay effects and trails
        }

        /// <summary>Current replay viewing mode.</summary>
        private ReplayMode _currentMode = ReplayMode.Ghost;

        /// <summary>All recorded frames for the current/last level.</summary>
        private readonly List<FrameData> _frames = new();

        // Blood decals and casings are now recorded per-frame in FrameData (cumulative snapshots).

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

        /// <summary>Recorded enemy weapon types (0=RIFLE, 1=SHOTGUN, 2=UZI, 3=MACHETE) for ghost creation.</summary>
        private readonly List<int> _enemyWeaponTypes = new();

        /// <summary>Replay ghost nodes.</summary>
        private Node2D? _ghostPlayer;
        private readonly List<Node2D> _ghostEnemies = new();
        private readonly List<Node2D> _ghostBullets = new();
        private readonly List<Node2D> _ghostGrenades = new();

        /// <summary>Active muzzle flash nodes during playback.</summary>
        private readonly List<(Node2D Node, float Timer)> _activeMuzzleFlashes = new();

        /// <summary>Replay UI overlay.</summary>
        private CanvasLayer? _replayUi;

        /// <summary>Ghost filter overlay for Ghost mode (red/black/white).</summary>
        private CanvasLayer? _ghostFilterLayer;

        // Impact events removed — blood decals are now tracked per-frame in FrameData.

        /// <summary>Baseline blood decal count from frame 0 (decals existing before gameplay).</summary>
        private int _baselineBloodCount;

        /// <summary>Number of blood decals spawned so far during playback.</summary>
        private int _spawnedBloodCount;

        /// <summary>Spawned blood decals during Memory mode playback.</summary>
        private readonly List<Node2D> _memoryBloodDecals = new();

        // Casing snapshots removed — casings are now tracked per-frame in FrameData.

        /// <summary>Recorded footprint snapshots for progressive floor replay.</summary>
        private readonly List<FootprintSnapshot> _footprintSnapshots = new();

        /// <summary>Baseline casing count (casings present before gameplay started).</summary>
        private int _baselineCasingCount;

        /// <summary>Baseline footprint count (footprints present before gameplay started).</summary>
        private int _baselineFootprintCount;

        /// <summary>Number of casings spawned so far during playback.</summary>
        private int _spawnedCasingCount;

        /// <summary>Number of footprints spawned so far during playback.</summary>
        private int _spawnedFootprintCount;

        /// <summary>Spawned casing sprites during Memory mode playback.</summary>
        private readonly List<Node2D> _memoryCasings = new();

        /// <summary>Spawned footprint sprites during Memory mode playback.</summary>
        private readonly List<Node2D> _memoryFootprints = new();

        /// <summary>Motion trail data for player and enemies in Memory mode.</summary>
        private readonly List<Vector2> _playerTrailPositions = new();
        private readonly List<List<Vector2>> _enemyTrailPositions = new();
        private readonly List<Node2D> _trailNodes = new();
        private float _trailUpdateTimer;

        /// <summary>Previous player health for penultimate hit detection during replay.</summary>
        private float _prevPlayerHealth = 100.0f;

        /// <summary>Last applied frame index for ensuring skipped frame events are played.</summary>
        private int _lastAppliedFrame = -1;

        /// <summary>Previous grenade count for detecting grenade explosions.</summary>
        private int _prevGrenadeCount;

        /// <summary>Previous positions for trail tracking.</summary>
        private Vector2 _prevPlayerPos;
        private readonly List<Vector2> _prevEnemyPositions = new();

        /// <summary>Signal emitted when replay playback ends.</summary>
        [Signal] public delegate void ReplayEndedEventHandler();

        /// <summary>Signal emitted when replay playback starts.</summary>
        [Signal] public delegate void ReplayStartedEventHandler();

        /// <summary>Signal emitted when playback progress changes.</summary>
        [Signal] public delegate void PlaybackProgressEventHandler(float currentTime, float totalTime);

        // ============================================================
        // Data classes
        // ============================================================

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
            public float PlayerHealth = 100.0f;
            public List<EnemyFrameData> Enemies = new();
            public List<ProjectileFrameData> Bullets = new();
            public List<GrenadeFrameData> Grenades = new();
            public List<SoundEvent> Events = new();
            /// <summary>Cumulative blood decal positions this frame (snapshot of all decals in scene).</summary>
            public List<BloodDecalData> BloodDecals = new();
            /// <summary>Cumulative casing positions this frame (snapshot of all casings in scene).</summary>
            public List<CasingData> Casings = new();
        }

        /// <summary>Blood decal position/rotation/scale recorded per frame.</summary>
        private class BloodDecalData
        {
            public Vector2 Position;
            public float Rotation;
            public Vector2 Scale = Vector2.One;
        }

        /// <summary>Casing position/rotation recorded per frame.</summary>
        private class CasingData
        {
            public Vector2 Position;
            public float Rotation;
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
            public float Health = 10.0f;
        }

        private class ProjectileFrameData
        {
            public Vector2 Position;
            public float Rotation;
        }

        private class GrenadeFrameData
        {
            public Vector2 Position;
            public float Rotation;
            public string TexturePath = "";
        }

        /// <summary>Sound/gameplay event recorded per frame for replay playback.</summary>
        private class SoundEvent
        {
            public enum SoundType { Shot, Death, Hit, PlayerDeath, PlayerHit, PenultimateHit, GrenadeExplosion }
            public SoundType Type;
            public Vector2 Position;
        }

        // ImpactEvent and CasingSnapshot classes removed — blood decals and casings
        // are now tracked per-frame in FrameData (cumulative snapshot approach matching GDScript).

        /// <summary>Snapshot of blood footprint state at a given frame time.</summary>
        private class FootprintSnapshot
        {
            public float Time;
            public Vector2 Position;
            public float Rotation;
            public Vector2 Scale = Vector2.One;
            /// <summary>Footprint color including alpha (Issue #590 fix 1).</summary>
            public Color Modulate = Colors.White;
            /// <summary>Whether this is a left foot print (Issue #590 fix 1).</summary>
            public bool IsLeft = true;
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
            _footprintSnapshots.Clear();
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

            // Record enemy weapon types for ghost creation later
            _enemyWeaponTypes.Clear();
            foreach (var enemy in _enemies)
            {
                if (enemy != null && IsInstanceValid(enemy))
                {
                    var weaponTypeVar = enemy.Get("weapon_type");
                    int weaponType = weaponTypeVar.VariantType != Variant.Type.Nil
                        ? weaponTypeVar.AsInt32()
                        : 0; // Default to RIFLE
                    _enemyWeaponTypes.Add(weaponType);
                }
                else
                {
                    _enemyWeaponTypes.Add(0); // Default to RIFLE
                }
            }

            // Connect to ImpactEffectsManager signals for recording blood/hits
            ConnectImpactSignals();

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
                int wtype = i < _enemyWeaponTypes.Count ? _enemyWeaponTypes[i] : 0;
                string wtypeName = wtype switch { 0 => "RIFLE", 1 => "SHOTGUN", 2 => "UZI", 3 => "MACHETE", _ => "UNKNOWN" };
                if (enemy != null && IsInstanceValid(enemy))
                    LogToFile($"  Enemy {i}: {enemy.Name} (weapon_type={wtype}/{wtypeName})");
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
            int lastFrameBlood = _frames.Count > 0 ? _frames[^1].BloodDecals.Count : 0;
            int lastFrameCasings = _frames.Count > 0 ? _frames[^1].Casings.Count : 0;
            int frame0Blood = _frames.Count > 0 ? _frames[0].BloodDecals.Count : 0;
            int frame0Casings = _frames.Count > 0 ? _frames[0].Casings.Count : 0;
            LogToFile("=== REPLAY RECORDING STOPPED ===");
            LogToFile($"Total frames recorded: {_frames.Count}");
            LogToFile($"Total duration: {_recordingTime:F2}s");
            LogToFile($"Blood decals at end: {lastFrameBlood} (baseline at frame 0: {frame0Blood})");
            LogToFile($"Casings at end: {lastFrameCasings} (baseline at frame 0: {frame0Casings})");
            LogToFile($"Footprints recorded: {_footprintSnapshots.Count}");
            LogToFile($"has_replay() will return: {_frames.Count > 0}");
            GD.Print($"[ReplayManager] Recording stopped: {_frames.Count} frames, {_recordingTime:F2}s, blood={lastFrameBlood}(baseline={frame0Blood}), casings={lastFrameCasings}(baseline={frame0Casings}), footprints={_footprintSnapshots.Count}");
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

            // Calculate baseline counts from frame 0 data (items that existed before gameplay)
            _baselineBloodCount = _frames.Count > 0 ? _frames[0].BloodDecals.Count : 0;
            _baselineCasingCount = _frames.Count > 0 ? _frames[0].Casings.Count : 0;
            _baselineFootprintCount = 0;
            if (_footprintSnapshots.Count > 0)
            {
                float firstFrameTime = _frames.Count > 0 ? _frames[0].Time : 0.0f;
                for (int i = 0; i < _footprintSnapshots.Count; i++)
                {
                    if (_footprintSnapshots[i].Time <= firstFrameTime)
                        _baselineFootprintCount++;
                    else
                        break;
                }
            }
            _spawnedBloodCount = 0;
            _spawnedCasingCount = 0;
            _spawnedFootprintCount = 0;

            int lastBlood = _frames[^1].BloodDecals.Count;
            int lastCasings = _frames[^1].Casings.Count;
            LogToFile($"Progressive floor state: blood={lastBlood} (baseline={_baselineBloodCount}, to spawn={lastBlood - _baselineBloodCount}), casings={lastCasings} (baseline={_baselineCasingCount}, to spawn={lastCasings - _baselineCasingCount}), footprints={_footprintSnapshots.Count} (baseline={_baselineFootprintCount})");

            _trailUpdateTimer = 0.0f;
            _playerTrailPositions.Clear();
            _enemyTrailPositions.Clear();
            _prevPlayerPos = _frames.Count > 0 ? _frames[0].PlayerPosition : Vector2.Zero;
            _prevPlayerHealth = _frames.Count > 0 ? _frames[0].PlayerHealth : 100.0f;
            _lastAppliedFrame = -1;
            _prevGrenadeCount = 0;
            _prevEnemyPositions.Clear();

            CreateGhostEntities(level);
            CreateReplayUi(level);
            ApplyReplayMode();

            // Issue #597: Set replay_mode on effect managers to prevent time manipulation
            SetEffectManagersReplayMode(true);

            level.GetTree().Paused = true;

            EmitSignal(SignalName.ReplayStarted);
            LogToFile($"Started replay playback. Frames: {_frames.Count}, Duration: {GetReplayDuration():F2}s, Mode: {_currentMode}");
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
            CleanupGhostFilter();
            CleanupMemoryEffects();
            CleanupTrails();

            // Issue #597: Clear replay_mode flag before disabling effects
            // so that reset_effects() can restore Engine.TimeScale if needed
            SetEffectManagersReplayMode(false);

            // Disable all gameplay effects (cinema, hit, penultimate, power fantasy)
            DisableAllReplayEffects();

            // Restore visibility of original floor items that were hidden for Memory mode
            if (_levelNode != null && IsInstanceValid(_levelNode))
            {
                var casings = _levelNode.GetTree().GetNodesInGroup("casings");
                foreach (var casing in casings)
                {
                    if (casing is Node2D c2d)
                        c2d.Visible = true;
                }

                var bloodDecals = _levelNode.GetTree().GetNodesInGroup("blood_puddle");
                foreach (var decal in bloodDecals)
                {
                    if (decal is Node2D d2d)
                        d2d.Visible = true;
                }

                foreach (var child in _levelNode.GetChildren())
                {
                    if (child is Sprite2D sprite2D &&
                        sprite2D.SceneFilePath.Contains("BloodFootprint"))
                    {
                        sprite2D.Visible = true;
                    }
                }
            }

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
            _footprintSnapshots.Clear();
            _enemyWeaponTypes.Clear();
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

            // Issue #597: Reset _lastAppliedFrame so PlayFrameEvents runs for
            // all frames from the seek position onward. Without this, switching
            // replay modes (Ghost→Memory) would leave _lastAppliedFrame pointing
            // to the old playback position, causing PlayFrameEvents to be skipped
            // for all frames up to that old position — meaning no visual effects.
            _lastAppliedFrame = _playbackFrame - 1;

            ApplyFrame(_frames[_playbackFrame], 0.0f);
        }

        // ============================================================
        // Replay mode management
        // ============================================================

        /// <summary>Sets the replay viewing mode and applies visual changes.
        /// Restarts the replay from the beginning when switching modes.</summary>
        public void SetReplayMode(ReplayMode mode)
        {
            if (_currentMode == mode) return;
            _currentMode = mode;
            LogToFile($"Replay mode changed to: {mode}");

            if (_isPlayingBack || _playbackEnding)
            {
                // Disable all active effects before switching modes
                DisableAllReplayEffects();
                ApplyReplayMode();
                // Restart replay from beginning when switching modes
                SeekTo(0.0f);
                LogToFile($"Replay restarted from beginning after mode switch to {mode}");
            }
        }

        /// <summary>Gets the current replay mode.</summary>
        public ReplayMode GetReplayMode() => _currentMode;

        /// <summary>Applies visual changes for the current replay mode.</summary>
        private void ApplyReplayMode()
        {
            if (_currentMode == ReplayMode.Ghost)
            {
                CreateGhostFilter();
                CleanupMemoryEffects();
                CleanupTrails();
                // Disable all gameplay effects when leaving Memory mode
                DisableAllReplayEffects();
                // Set ghost entities to slightly transparent
                SetAllGhostModulate(new Color(1.0f, 1.0f, 1.0f, 0.9f));

                // Restore original casings/footprints/blood visibility for Ghost mode
                if (_levelNode != null && IsInstanceValid(_levelNode))
                {
                    var casings = _levelNode.GetTree().GetNodesInGroup("casings");
                    foreach (var casing in casings)
                    {
                        if (casing is Node2D c2d)
                            c2d.Visible = true;
                    }

                    var bloodDecals = _levelNode.GetTree().GetNodesInGroup("blood_puddle");
                    foreach (var decal in bloodDecals)
                    {
                        if (decal is Node2D d2d)
                            d2d.Visible = true;
                    }

                    foreach (var child in _levelNode.GetChildren())
                    {
                        if (child is Sprite2D sprite2D &&
                            sprite2D.SceneFilePath.Contains("BloodFootprint"))
                        {
                            sprite2D.Visible = true;
                        }
                    }
                }
            }
            else // Memory
            {
                CleanupGhostFilter();
                // Full opacity for memory mode
                SetAllGhostModulate(new Color(1.0f, 1.0f, 1.0f, 1.0f));
                // Enable cinema effects during memory playback
                EnableMemoryEffects();

                // Hide existing casings and footprints for progressive replay,
                // and reset spawn counts so they'll be re-created from the beginning
                if (_levelNode != null && IsInstanceValid(_levelNode))
                {
                    var casings = _levelNode.GetTree().GetNodesInGroup("casings");
                    foreach (var casing in casings)
                    {
                        if (casing is Node2D c2d)
                            c2d.Visible = false;
                    }

                    var bloodDecals = _levelNode.GetTree().GetNodesInGroup("blood_puddle");
                    foreach (var decal in bloodDecals)
                    {
                        if (decal is Node2D d2d)
                            d2d.Visible = false;
                    }

                    foreach (var child in _levelNode.GetChildren())
                    {
                        if (child is Sprite2D sprite2D &&
                            sprite2D.SceneFilePath.Contains("BloodFootprint"))
                        {
                            sprite2D.Visible = false;
                        }
                    }
                }

                // Reset progressive spawn state so casings/footprints/blood
                // get re-spawned up to current playback time
                CleanupMemoryEffects();
                _spawnedBloodCount = 0;
                _spawnedCasingCount = 0;
                _spawnedFootprintCount = 0;
                LogToFile($"Memory mode activated: reset progressive floor state, will spawn up to time {_playbackTime:F2}s");
            }

            // Update mode button states in UI
            UpdateModeButtonStates();
        }

        /// <summary>Sets modulate on all ghost entities.</summary>
        private void SetAllGhostModulate(Color color)
        {
            if (_ghostPlayer != null && IsInstanceValid(_ghostPlayer))
                SetGhostModulate(_ghostPlayer, color);
            foreach (var ghost in _ghostEnemies)
            {
                if (ghost != null && IsInstanceValid(ghost))
                    SetGhostModulate(ghost, color);
            }
        }

        // ============================================================
        // Ghost filter (red/black/white)
        // ============================================================

        /// <summary>Creates a fullscreen shader overlay for Ghost mode.</summary>
        private void CreateGhostFilter()
        {
            if (_ghostFilterLayer != null && IsInstanceValid(_ghostFilterLayer)) return;
            if (_levelNode == null || !IsInstanceValid(_levelNode)) return;

            _ghostFilterLayer = new CanvasLayer();
            _ghostFilterLayer.Name = "GhostFilterLayer";
            _ghostFilterLayer.Layer = 98; // Below replay UI (100) but above game
            _ghostFilterLayer.ProcessMode = ProcessModeEnum.Always;

            var filterRect = new ColorRect();
            filterRect.Name = "GhostFilter";
            filterRect.SetAnchorsPreset(Control.LayoutPreset.FullRect);
            filterRect.MouseFilter = Control.MouseFilterEnum.Ignore;

            // The ghost_replay shader uses hint_screen_texture to sample the
            // rendered scene and applies a red/black/white color grading filter.
            // Uses textureLod for gl_compatibility renderer support.
            var shader = GD.Load<Shader>("res://scripts/shaders/ghost_replay.gdshader");
            if (shader != null)
            {
                var material = new ShaderMaterial();
                material.Shader = shader;
                material.SetShaderParameter("intensity", 1.0f);
                material.SetShaderParameter("red_threshold", 0.15f);
                material.SetShaderParameter("red_boost", 2.0f);
                filterRect.Material = material;
            }

            _ghostFilterLayer.AddChild(filterRect);
            _levelNode.AddChild(_ghostFilterLayer);

            LogToFile("Ghost filter overlay created (screen-texture shader)");
        }

        /// <summary>Restores normal colors when leaving Ghost mode.</summary>
        private void RestoreWorldColors()
        {
            // No world modulation is applied anymore — the ghost_replay shader
            // handles all color grading via screen-texture post-processing.
        }

        /// <summary>Cleans up the ghost filter overlay.</summary>
        private void CleanupGhostFilter()
        {
            RestoreWorldColors();

            if (_ghostFilterLayer != null && IsInstanceValid(_ghostFilterLayer))
            {
                _ghostFilterLayer.QueueFree();
                _ghostFilterLayer = null;
            }
        }

        // ============================================================
        // Memory mode effects
        // ============================================================

        /// <summary>Enables cinema and other effects for Memory mode.</summary>
        private void EnableMemoryEffects()
        {
            // Enable cinema effects (film grain, warm tint, vignette)
            var cinemaEffects = GetNodeOrNull("/root/CinemaEffectsManager");
            if (cinemaEffects != null && cinemaEffects.HasMethod("set_enabled"))
            {
                cinemaEffects.Call("set_enabled", true);
                LogToFile("Memory mode: CinemaEffects enabled");
            }
        }

        /// <summary>
        /// Disables all replay-related effects (cinema, hit, penultimate, power fantasy, last chance).
        /// Called when switching to Ghost mode, stopping playback, or restarting replay.
        /// Restores Engine.TimeScale to 1.0 to undo any time slowdown effects.
        /// </summary>
        private void DisableAllReplayEffects()
        {
            // Disable cinema effects
            var cinemaEffects = GetNodeOrNull("/root/CinemaEffectsManager");
            if (cinemaEffects != null && cinemaEffects.HasMethod("set_enabled"))
            {
                cinemaEffects.Call("set_enabled", false);
                LogToFile("DisableAllReplayEffects: CinemaEffects disabled");
            }

            // Reset hit effects (saturation + time slowdown)
            var hitEffects = GetNodeOrNull("/root/HitEffectsManager");
            if (hitEffects != null && hitEffects.HasMethod("reset_effects"))
            {
                hitEffects.Call("reset_effects");
                LogToFile("DisableAllReplayEffects: HitEffects reset");
            }

            // Reset penultimate hit effects (saturation/contrast + time slowdown)
            var penultimateEffects = GetNodeOrNull("/root/PenultimateHitEffectsManager");
            if (penultimateEffects != null && penultimateEffects.HasMethod("reset_effects"))
            {
                penultimateEffects.Call("reset_effects");
                LogToFile("DisableAllReplayEffects: PenultimateHitEffects reset");
            }

            // Reset power fantasy effects (kill/grenade time slowdown)
            var powerFantasyManager = GetNodeOrNull("/root/PowerFantasyEffectsManager");
            if (powerFantasyManager != null && powerFantasyManager.HasMethod("reset_effects"))
            {
                powerFantasyManager.Call("reset_effects");
                LogToFile("DisableAllReplayEffects: PowerFantasyEffects reset");
            }

            // Reset last chance effects
            var lastChanceEffects = GetNodeOrNull("/root/LastChanceEffectsManager");
            if (lastChanceEffects != null && lastChanceEffects.HasMethod("reset_effects"))
            {
                lastChanceEffects.Call("reset_effects");
                LogToFile("DisableAllReplayEffects: LastChanceEffects reset");
            }

            // Ensure time scale is restored
            Engine.TimeScale = 1.0;
        }

        /// <summary>
        /// Sets the replay_mode flag on all effect managers.
        /// Issue #597: When replay_mode is true, effect managers skip Engine.TimeScale
        /// and process_mode changes while still applying all visual effects (shaders,
        /// saturation, contrast, enemy coloring).
        /// </summary>
        private void SetEffectManagersReplayMode(bool enabled)
        {
            // Issue #597: Set replay_mode flag AND process_mode on each effect manager.
            // process_mode must be Always during replay so effect timers run when tree is paused.
            var processMode = enabled ? (int)ProcessModeEnum.Always : (int)ProcessModeEnum.Inherit;

            var hitEffects = GetNodeOrNull("/root/HitEffectsManager");
            if (hitEffects != null)
            {
                hitEffects.Set("replay_mode", enabled);
                hitEffects.Set("process_mode", processMode);
            }

            var penultimateEffects = GetNodeOrNull("/root/PenultimateHitEffectsManager");
            if (penultimateEffects != null)
            {
                penultimateEffects.Set("replay_mode", enabled);
                penultimateEffects.Set("process_mode", processMode);
            }

            var powerFantasyManager = GetNodeOrNull("/root/PowerFantasyEffectsManager");
            if (powerFantasyManager != null)
            {
                powerFantasyManager.Set("replay_mode", enabled);
                powerFantasyManager.Set("process_mode", processMode);
            }

            var lastChanceEffects = GetNodeOrNull("/root/LastChanceEffectsManager");
            if (lastChanceEffects != null)
            {
                lastChanceEffects.Set("replay_mode", enabled);
                lastChanceEffects.Set("process_mode", processMode);
            }

            LogToFile($"Effect managers replay_mode set to: {enabled}");
        }

        /// <summary>Cleans up Memory mode effects and blood decals.</summary>
        private void CleanupMemoryEffects()
        {
            foreach (var decal in _memoryBloodDecals)
            {
                if (decal != null && IsInstanceValid(decal))
                    decal.QueueFree();
            }
            _memoryBloodDecals.Clear();

            foreach (var casing in _memoryCasings)
            {
                if (casing != null && IsInstanceValid(casing))
                    casing.QueueFree();
            }
            _memoryCasings.Clear();

            foreach (var footprint in _memoryFootprints)
            {
                if (footprint != null && IsInstanceValid(footprint))
                    footprint.QueueFree();
            }
            _memoryFootprints.Clear();
        }

        /// <summary>
        /// Updates blood decals to match the current frame's cumulative data.
        /// Only active in Memory mode. Spawns new decals beyond the baseline count.
        /// </summary>
        private void UpdateReplayBloodDecals(FrameData frame)
        {
            if (_currentMode != ReplayMode.Memory) return;
            if (_levelNode == null || !IsInstanceValid(_levelNode)) return;

            int newCount = frame.BloodDecals.Count - _baselineBloodCount;
            if (newCount <= 0) return;
            if (_spawnedBloodCount >= newCount) return;

            var ghostContainer = _levelNode.GetNodeOrNull<Node2D>("ReplayGhosts");
            if (ghostContainer == null) return;

            // Try to load the actual BloodDecal scene
            PackedScene? bloodDecalScene = null;
            if (ResourceLoader.Exists("res://scenes/effects/BloodDecal.tscn"))
                bloodDecalScene = GD.Load<PackedScene>("res://scenes/effects/BloodDecal.tscn");

            int spawned = 0;
            for (int i = _baselineBloodCount + _spawnedBloodCount; i < frame.BloodDecals.Count; i++)
            {
                var data = frame.BloodDecals[i];

                if (bloodDecalScene != null)
                {
                    var decal = bloodDecalScene.Instantiate<Node2D>();
                    decal.ProcessMode = ProcessModeEnum.Always;
                    decal.GlobalPosition = data.Position;
                    decal.Rotation = data.Rotation;
                    decal.Scale = data.Scale;
                    DisableNodeProcessing(decal);
                    ghostContainer.AddChild(decal);
                    _memoryBloodDecals.Add(decal);
                }
                else
                {
                    // Fallback: simple red circle
                    var fallback = new Node2D();
                    fallback.Name = "MemoryBloodDecal";
                    fallback.ProcessMode = ProcessModeEnum.Always;
                    fallback.GlobalPosition = data.Position;

                    var sprite = new Sprite2D();
                    var texture = new GradientTexture2D();
                    texture.Width = 24;
                    texture.Height = 24;
                    texture.Fill = GradientTexture2D.FillEnum.Radial;
                    texture.FillFrom = new Vector2(0.5f, 0.5f);
                    texture.FillTo = new Vector2(1.0f, 0.5f);
                    var gradient = new Gradient();
                    var bloodColor = new Color(0.6f, 0.0f, 0.0f, 0.85f);
                    gradient.SetColor(0, bloodColor);
                    gradient.SetColor(1, new Color(bloodColor.R, bloodColor.G, bloodColor.B, 0.0f));
                    texture.Gradient = gradient;
                    sprite.Texture = texture;
                    fallback.AddChild(sprite);

                    ghostContainer.AddChild(fallback);
                    _memoryBloodDecals.Add(fallback);
                }
                spawned++;
            }

            _spawnedBloodCount += spawned;

            if (spawned > 0)
                LogToFile($"Spawned {spawned} replay blood decals (total: {_spawnedBloodCount}/{frame.BloodDecals.Count - _baselineBloodCount})");
        }

        /// <summary>
        /// Updates casings to match the current frame's cumulative data.
        /// Only active in Memory mode. Spawns new casings beyond the baseline count.
        /// </summary>
        private void UpdateReplayCasings(FrameData frame)
        {
            if (_currentMode != ReplayMode.Memory) return;
            if (_levelNode == null || !IsInstanceValid(_levelNode)) return;

            int newCount = frame.Casings.Count - _baselineCasingCount;
            if (newCount <= 0) return;
            if (_spawnedCasingCount >= newCount) return;

            var ghostContainer = _levelNode.GetNodeOrNull<Node2D>("ReplayGhosts");
            if (ghostContainer == null) return;

            // Load casing texture
            Texture2D? casingTexture = null;
            if (ResourceLoader.Exists("res://assets/sprites/effects/casing_rifle.png"))
                casingTexture = GD.Load<Texture2D>("res://assets/sprites/effects/casing_rifle.png");

            int spawned = 0;
            for (int i = _baselineCasingCount + _spawnedCasingCount; i < frame.Casings.Count; i++)
            {
                var data = frame.Casings[i];

                var casing = new Sprite2D();
                casing.Name = "ReplayCasing";
                casing.ProcessMode = ProcessModeEnum.Always;
                if (casingTexture != null)
                    casing.Texture = casingTexture;
                else
                {
                    var img = Image.CreateEmpty(6, 3, false, Image.Format.Rgba8);
                    img.Fill(new Color(0.9f, 0.8f, 0.4f, 0.9f));
                    casing.Texture = ImageTexture.CreateFromImage(img);
                }
                casing.GlobalPosition = data.Position;
                casing.Rotation = data.Rotation;
                casing.ZIndex = 0;
                ghostContainer.AddChild(casing);
                _memoryCasings.Add(casing);
                spawned++;
            }

            _spawnedCasingCount += spawned;

            if (spawned > 0)
                LogToFile($"Spawned {spawned} replay casings (total: {_spawnedCasingCount}/{frame.Casings.Count - _baselineCasingCount})");
        }

        /// <summary>Spawns footprints up to the current playback time (Memory mode only).</summary>
        private void SpawnFootprintsUpToTime(float time)
        {
            if (_currentMode != ReplayMode.Memory) return;
            if (_levelNode == null || !IsInstanceValid(_levelNode)) return;
            if (_footprintSnapshots.Count <= _baselineFootprintCount) return;

            var ghostContainer = _levelNode.GetNodeOrNull<Node2D>("ReplayGhosts");
            if (ghostContainer == null)
            {
                LogToFile("WARNING: ReplayGhosts container not found for footprint spawn");
                return;
            }

            // Try to load the actual BloodFootprint scene
            PackedScene? footprintScene = null;
            if (ResourceLoader.Exists("res://scenes/effects/BloodFootprint.tscn"))
                footprintScene = GD.Load<PackedScene>("res://scenes/effects/BloodFootprint.tscn");

            int spawned = 0;
            int startIdx = _baselineFootprintCount + _spawnedFootprintCount;
            for (int i = startIdx; i < _footprintSnapshots.Count; i++)
            {
                if (_footprintSnapshots[i].Time > time) break;

                var data = _footprintSnapshots[i];

                if (footprintScene != null)
                {
                    var footprint = footprintScene.Instantiate<Node2D>();
                    footprint.ProcessMode = ProcessModeEnum.Always;
                    // Do NOT call DisableNodeProcessing here — the BloodFootprint script
                    // loads boot print textures in _ready(), so removing the script would
                    // leave the sprite with no texture (invisible footprint).
                    // The script is lightweight (no physics, no collision) so it's safe to keep.
                    footprint.GlobalPosition = data.Position;
                    footprint.Rotation = data.Rotation;
                    footprint.Scale = data.Scale;
                    ghostContainer.AddChild(footprint);

                    // Issue #590 fix 1: Apply foot type and modulate so footprints are visible.
                    // set_foot() assigns the boot texture (left or right), without which
                    // the Sprite2D has no texture and is invisible.
                    if (footprint.HasMethod("set_foot"))
                        footprint.Call("set_foot", data.IsLeft);
                    if (footprint.HasMethod("set_alpha"))
                        footprint.Call("set_alpha", data.Modulate.A);
                    if (footprint.HasMethod("set_blood_color"))
                        footprint.Call("set_blood_color", data.Modulate);

                    _memoryFootprints.Add(footprint);
                }
                else
                {
                    // Fallback: simple dark red sprite
                    var footprint = new Sprite2D();
                    footprint.Name = "ReplayFootprint";
                    footprint.ProcessMode = ProcessModeEnum.Always;
                    var img = Image.CreateEmpty(8, 12, false, Image.Format.Rgba8);
                    img.Fill(new Color(data.Modulate.R, data.Modulate.G, data.Modulate.B, data.Modulate.A));
                    footprint.Texture = ImageTexture.CreateFromImage(img);
                    footprint.GlobalPosition = data.Position;
                    footprint.Rotation = data.Rotation;
                    footprint.Scale = data.Scale;
                    footprint.ZIndex = 1;
                    ghostContainer.AddChild(footprint);
                    _memoryFootprints.Add(footprint);
                }
                spawned++;
            }

            _spawnedFootprintCount += spawned;

            if (spawned > 0)
                LogToFile($"Spawned {spawned} replay footprints (total: {_spawnedFootprintCount}/{_footprintSnapshots.Count - _baselineFootprintCount}) at time {time:F2}s");
        }

        // ============================================================
        // Motion trail effects (Memory mode)
        // ============================================================

        /// <summary>Updates motion trails for moving entities.</summary>
        private void UpdateTrails(FrameData frame, float delta)
        {
            if (_currentMode != ReplayMode.Memory) return;

            _trailUpdateTimer += delta * _playbackSpeed;
            if (_trailUpdateTimer < TrailUpdateInterval) return;
            _trailUpdateTimer = 0.0f;

            // Update player trail — clear trail when standing still
            if (frame.PlayerAlive)
            {
                float playerSpeed = (frame.PlayerPosition - _prevPlayerPos).Length();
                if (playerSpeed > 5.0f)
                {
                    _playerTrailPositions.Insert(0, frame.PlayerPosition);
                    if (_playerTrailPositions.Count > TrailSegments)
                        _playerTrailPositions.RemoveAt(_playerTrailPositions.Count - 1);
                }
                else
                {
                    _playerTrailPositions.Clear();
                }
                _prevPlayerPos = frame.PlayerPosition;
            }

            // Update enemy trails
            int enemyCount = Mathf.Min(_ghostEnemies.Count, frame.Enemies.Count);
            while (_enemyTrailPositions.Count < enemyCount)
                _enemyTrailPositions.Add(new List<Vector2>());
            while (_prevEnemyPositions.Count < enemyCount)
                _prevEnemyPositions.Add(Vector2.Zero);

            for (int i = 0; i < enemyCount; i++)
            {
                var data = frame.Enemies[i];
                if (data.Alive)
                {
                    float enemySpeed = (data.Position - _prevEnemyPositions[i]).Length();
                    if (enemySpeed > 5.0f)
                    {
                        _enemyTrailPositions[i].Insert(0, data.Position);
                        if (_enemyTrailPositions[i].Count > TrailSegments)
                            _enemyTrailPositions[i].RemoveAt(_enemyTrailPositions[i].Count - 1);
                    }
                    else
                    {
                        _enemyTrailPositions[i].Clear();
                    }
                    _prevEnemyPositions[i] = data.Position;
                }
            }

            // Render trails
            RenderTrails(frame);
        }

        /// <summary>Renders motion trail sprites for all entities.</summary>
        private void RenderTrails(FrameData frame)
        {
            if (_levelNode == null || !IsInstanceValid(_levelNode)) return;
            var ghostContainer = _levelNode.GetNodeOrNull<Node2D>("ReplayGhosts");
            if (ghostContainer == null) return;

            // Clean up old trail nodes
            CleanupTrails();

            // Player trail (blue flame)
            // Issue #590 fix 3: Trail is 3x wider for better visibility
            if (_playerTrailPositions.Count > 1 && frame.PlayerAlive)
            {
                for (int i = 1; i < _playerTrailPositions.Count; i++)
                {
                    float alpha = 1.0f - ((float)i / _playerTrailPositions.Count);
                    var trailNode = CreateTrailSegment(
                        _playerTrailPositions[i],
                        new Color(0.3f, 0.5f, 1.0f, alpha * 0.5f),
                        Mathf.Max(6.0f, 24.0f * alpha)
                    );
                    if (trailNode != null)
                    {
                        ghostContainer.AddChild(trailNode);
                        _trailNodes.Add(trailNode);
                    }
                }
            }

            // Enemy trails (red flame)
            int enemyCount = Mathf.Min(_ghostEnemies.Count, frame.Enemies.Count);
            for (int ei = 0; ei < enemyCount; ei++)
            {
                if (ei >= _enemyTrailPositions.Count) break;
                var trail = _enemyTrailPositions[ei];
                if (trail.Count <= 1 || !frame.Enemies[ei].Alive) continue;

                for (int i = 1; i < trail.Count; i++)
                {
                    float alpha = 1.0f - ((float)i / trail.Count);
                    var trailNode = CreateTrailSegment(
                        trail[i],
                        new Color(1.0f, 0.3f, 0.2f, alpha * 0.4f),
                        Mathf.Max(2.0f, 6.0f * alpha)
                    );
                    if (trailNode != null)
                    {
                        ghostContainer.AddChild(trailNode);
                        _trailNodes.Add(trailNode);
                    }
                }
            }

            // Bullet trails (yellow flame)
            for (int i = 0; i < frame.Bullets.Count; i++)
            {
                var bullet = frame.Bullets[i];
                var direction = new Vector2(Mathf.Cos(bullet.Rotation), Mathf.Sin(bullet.Rotation));
                for (int seg = 1; seg <= 3; seg++)
                {
                    float alpha = 1.0f - (seg * 0.3f);
                    var trailPos = bullet.Position - direction * seg * 8.0f;
                    var trailNode = CreateTrailSegment(
                        trailPos,
                        new Color(1.0f, 0.8f, 0.2f, alpha * 0.6f),
                        Mathf.Max(1.0f, 4.0f * alpha)
                    );
                    if (trailNode != null)
                    {
                        ghostContainer.AddChild(trailNode);
                        _trailNodes.Add(trailNode);
                    }
                }
            }
        }

        /// <summary>Creates a single trail segment sprite.</summary>
        private Node2D? CreateTrailSegment(Vector2 position, Color color, float size)
        {
            var node = new Node2D();
            node.Name = "TrailSegment";
            node.ProcessMode = ProcessModeEnum.Always;
            node.GlobalPosition = position;

            var sprite = new Sprite2D();
            var texture = new GradientTexture2D();
            int texSize = Mathf.Max(4, (int)(size * 2));
            texture.Width = texSize;
            texture.Height = texSize;
            texture.Fill = GradientTexture2D.FillEnum.Radial;
            texture.FillFrom = new Vector2(0.5f, 0.5f);
            texture.FillTo = new Vector2(1.0f, 0.5f);
            var gradient = new Gradient();
            gradient.SetColor(0, color);
            gradient.SetColor(1, new Color(color.R, color.G, color.B, 0.0f));
            texture.Gradient = gradient;
            sprite.Texture = texture;
            node.AddChild(sprite);

            return node;
        }

        /// <summary>Cleans up all trail nodes.</summary>
        private void CleanupTrails()
        {
            foreach (var trail in _trailNodes)
            {
                if (trail != null && IsInstanceValid(trail))
                    trail.QueueFree();
            }
            _trailNodes.Clear();
        }

        // ============================================================
        // Impact event recording
        // ============================================================

        /// <summary>Connects to ImpactEffectsManager signals to record blood/hit events.</summary>
        private void ConnectImpactSignals()
        {
            // We record blood decal positions by scanning the level periodically during recording.
            // This is simpler than signal-based approach since ImpactEffectsManager doesn't emit
            // signals for individual effects. Instead, we snapshot blood decals.
        }

        /// <summary>
        /// Records cumulative floor state into the frame data: all blood decals, casings,
        /// and footprints currently in the scene. This matches the GDScript approach where
        /// each frame stores a full snapshot of floor items, enabling progressive playback
        /// by comparing against baseline (frame 0) counts.
        /// </summary>
        private void RecordCumulativeFloorState(FrameData frame)
        {
            if (_levelNode == null || !IsInstanceValid(_levelNode)) return;

            // Record all blood decals (Sprite2D nodes only, not their child Area2Ds)
            var bloodPuddles = _levelNode.GetTree().GetNodesInGroup("blood_puddle");
            foreach (var puddle in bloodPuddles)
            {
                // Only record Sprite2D nodes — blood_decal.gd also adds a child Area2D
                // to the same group, so we must filter by Sprite2D to avoid duplicates
                if (puddle is Sprite2D sprite2D && IsInstanceValid(sprite2D))
                {
                    frame.BloodDecals.Add(new BloodDecalData
                    {
                        Position = sprite2D.GlobalPosition,
                        Rotation = sprite2D.Rotation,
                        Scale = sprite2D.Scale
                    });
                }
            }

            // Record all casings (from "casings" group)
            var casings = _levelNode.GetTree().GetNodesInGroup("casings");
            foreach (var casing in casings)
            {
                if (casing is Node2D casing2D && IsInstanceValid(casing2D))
                {
                    frame.Casings.Add(new CasingData
                    {
                        Position = casing2D.GlobalPosition,
                        Rotation = casing2D.Rotation
                    });
                }
            }

            // Record new blood footprints (timed snapshots for progressive spawning)
            RecordNewFootprints();
        }

        /// <summary>Records new blood footprints that appeared since last frame.</summary>
        private void RecordNewFootprints()
        {
            if (_levelNode == null || !IsInstanceValid(_levelNode)) return;

            foreach (var child in _levelNode.GetChildren())
            {
                if (child is Sprite2D sprite2D &&
                    !sprite2D.HasMeta("replay_footprint_recorded") &&
                    sprite2D.ZIndex == 1 &&
                    sprite2D.SceneFilePath.Contains("BloodFootprint"))
                {
                    sprite2D.SetMeta("replay_footprint_recorded", true);

                    // Issue #590 fix 1: Determine which foot by checking texture path
                    bool isLeft = true;
                    if (sprite2D.Texture != null)
                    {
                        var texPath = sprite2D.Texture.ResourcePath;
                        if (texPath.Contains("right"))
                            isLeft = false;
                    }

                    _footprintSnapshots.Add(new FootprintSnapshot
                    {
                        Time = _recordingTime,
                        Position = sprite2D.GlobalPosition,
                        Rotation = sprite2D.Rotation,
                        Scale = sprite2D.Scale,
                        // Issue #590 fix 1: Record modulate (color + alpha) and foot type
                        Modulate = sprite2D.Modulate,
                        IsLeft = isLeft
                    });
                }
            }
        }

        // ============================================================
        // Weapon detection for ghost player
        // ============================================================

        /// <summary>
        /// Detects the weapon type equipped by the player and stores the
        /// texture path so the ghost player can display the correct weapon.
        /// Uses CurrentWeapon property name as the primary detection method,
        /// with child node name lookup as fallback.
        /// </summary>
        private void DetectPlayerWeapon(Node2D? player)
        {
            if (player == null || !IsInstanceValid(player))
            {
                _playerWeaponTexturePath = "res://assets/sprites/weapons/m16_rifle_topdown.png";
                _playerWeaponSpriteOffset = new Vector2(20, 0);
                return;
            }

            // Primary detection: use CurrentWeapon property name (most reliable,
            // works even when weapon is equipped by C# Player._Ready() before
            // the level script runs).
            string weaponName = "";
            var currentWeapon = player.Get("CurrentWeapon").AsGodotObject() as Node;
            if (currentWeapon != null && IsInstanceValid(currentWeapon))
            {
                weaponName = currentWeapon.Name;
            }

            // Fallback: check child node names directly
            if (string.IsNullOrEmpty(weaponName))
            {
                string[] knownWeapons = { "Revolver", "MakarovPM", "MiniUzi", "Shotgun",
                                          "SniperRifle", "SilencedPistol", "AssaultRifle" };
                foreach (var name in knownWeapons)
                {
                    if (player.GetNodeOrNull(name) != null)
                    {
                        weaponName = name;
                        break;
                    }
                }
            }

            switch (weaponName)
            {
                case "MiniUzi":
                    _playerWeaponTexturePath = "res://assets/sprites/weapons/mini_uzi_topdown.png";
                    _playerWeaponSpriteOffset = new Vector2(15, 0);
                    LogToFile("Detected player weapon: Mini UZI");
                    break;
                case "Shotgun":
                    _playerWeaponTexturePath = "res://assets/sprites/weapons/shotgun_topdown.png";
                    _playerWeaponSpriteOffset = new Vector2(20, 0);
                    LogToFile("Detected player weapon: Shotgun");
                    break;
                case "SniperRifle":
                    _playerWeaponTexturePath = "res://assets/sprites/weapons/asvk_topdown.png";
                    _playerWeaponSpriteOffset = new Vector2(25, 0);
                    LogToFile("Detected player weapon: Sniper Rifle (ASVK)");
                    break;
                case "SilencedPistol":
                    _playerWeaponTexturePath = "res://assets/sprites/weapons/silenced_pistol_topdown.png";
                    _playerWeaponSpriteOffset = new Vector2(15, 0);
                    LogToFile("Detected player weapon: Silenced Pistol");
                    break;
                case "Revolver":
                    _playerWeaponTexturePath = "res://assets/sprites/weapons/revolver_topdown.png";
                    _playerWeaponSpriteOffset = new Vector2(15, 0);
                    LogToFile("Detected player weapon: Revolver");
                    break;
                case "MakarovPM":
                    _playerWeaponTexturePath = "res://assets/sprites/weapons/makarov_pm_topdown.png";
                    _playerWeaponSpriteOffset = new Vector2(15, 0);
                    LogToFile("Detected player weapon: Makarov PM");
                    break;
                case "AssaultRifle":
                    _playerWeaponTexturePath = "res://assets/sprites/weapons/m16_rifle_topdown.png";
                    _playerWeaponSpriteOffset = new Vector2(20, 0);
                    LogToFile("Detected player weapon: Assault Rifle");
                    break;
                default:
                    _playerWeaponTexturePath = "res://assets/sprites/weapons/m16_rifle_topdown.png";
                    _playerWeaponSpriteOffset = new Vector2(20, 0);
                    LogToFile($"Detected player weapon: unknown '{weaponName}', using Assault Rifle (default)");
                    break;
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

                if (_player is CharacterBody2D playerBody)
                    frame.PlayerVelocity = playerBody.Velocity;

                var playerModel = _player.GetNodeOrNull<Node2D>("PlayerModel");
                if (playerModel != null)
                {
                    frame.PlayerModelRotation = playerModel.GlobalRotation;
                    frame.PlayerModelScale = playerModel.Scale;
                }

                var isAliveGd = _player.Get("_is_alive");
                if (isAliveGd.VariantType != Variant.Type.Nil)
                    frame.PlayerAlive = (bool)isAliveGd;
                else
                {
                    var isAliveCSharp = _player.Get("IsAlive");
                    if (isAliveCSharp.VariantType != Variant.Type.Nil)
                        frame.PlayerAlive = (bool)isAliveCSharp;
                }

                // Record player health for penultimate hit effect during replay
                var healthGd = _player.Get("_current_health");
                if (healthGd.VariantType != Variant.Type.Nil)
                    frame.PlayerHealth = (float)(int)healthGd;
                else
                {
                    var healthCs = _player.Get("CurrentHealth");
                    if (healthCs.VariantType != Variant.Type.Nil)
                        frame.PlayerHealth = (float)healthCs;
                }

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

                    if (enemy is CharacterBody2D enemyBody)
                        enemyData.Velocity = enemyBody.Velocity;

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

                    var hitDirVar = enemy.Get("_last_hit_direction");
                    if (hitDirVar.VariantType != Variant.Type.Nil)
                        enemyData.LastHitDirection = (Vector2)hitDirVar;

                    var isShootingVar = enemy.Get("_is_shooting");
                    if (isShootingVar.VariantType != Variant.Type.Nil)
                        enemyData.Shooting = (bool)isShootingVar;

                    // Record enemy health for hit detection
                    var enemyHealthVar = enemy.Get("_current_health");
                    if (enemyHealthVar.VariantType != Variant.Type.Nil)
                        enemyData.Health = (float)(double)enemyHealthVar;
                    else
                    {
                        var enemyHealthCs = enemy.Get("CurrentHealth");
                        if (enemyHealthCs.VariantType != Variant.Type.Nil)
                            enemyData.Health = (float)enemyHealthCs;
                    }

                    frame.Enemies.Add(enemyData);
                }
                else
                {
                    frame.Enemies.Add(new EnemyFrameData { Alive = false });
                }
            }

            // Record projectiles
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

                var grenades = _levelNode.GetTree().GetNodesInGroup("grenades");
                foreach (var grenade in grenades)
                {
                    if (grenade is Node2D gren2D)
                    {
                        var grenData = new GrenadeFrameData
                        {
                            Position = gren2D.GlobalPosition,
                            Rotation = gren2D.GlobalRotation,
                            TexturePath = ""
                        };

                        // Capture the grenade's sprite texture path
                        var grenSprite = gren2D.GetNodeOrNull<Sprite2D>("Sprite2D");
                        if (grenSprite?.Texture != null)
                            grenData.TexturePath = grenSprite.Texture.ResourcePath;

                        frame.Grenades.Add(grenData);
                    }
                }
            }

            // Record cumulative floor state: all blood decals, casings, footprints currently in scene
            RecordCumulativeFloorState(frame);

            // Record sound events by detecting state changes
            RecordSoundEvents(frame);

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

        /// <summary>
        /// Records sound events by comparing the current frame to the previous frame.
        /// Detects shots, hits, deaths, and grenade explosions.
        /// </summary>
        private void RecordSoundEvents(FrameData frame)
        {
            if (_frames.Count == 0) return;
            var prevFrame = _frames[^1];

            // Detect new bullets (shot event)
            if (frame.Bullets.Count > prevFrame.Bullets.Count)
            {
                for (int i = prevFrame.Bullets.Count; i < frame.Bullets.Count; i++)
                {
                    frame.Events.Add(new SoundEvent
                    {
                        Type = SoundEvent.SoundType.Shot,
                        Position = frame.Bullets[i].Position
                    });
                }
            }

            // Detect enemy deaths and hits
            int enemyCount = Mathf.Min(frame.Enemies.Count, prevFrame.Enemies.Count);
            for (int i = 0; i < enemyCount; i++)
            {
                if (prevFrame.Enemies[i].Alive && !frame.Enemies[i].Alive)
                {
                    frame.Events.Add(new SoundEvent
                    {
                        Type = SoundEvent.SoundType.Death,
                        Position = frame.Enemies[i].Position
                    });
                }
                else if (frame.Enemies[i].Alive && prevFrame.Enemies[i].Alive &&
                         frame.Enemies[i].Health < prevFrame.Enemies[i].Health)
                {
                    frame.Events.Add(new SoundEvent
                    {
                        Type = SoundEvent.SoundType.Hit,
                        Position = frame.Enemies[i].Position
                    });
                }
            }

            // Detect player death
            if (prevFrame.PlayerAlive && !frame.PlayerAlive)
            {
                frame.Events.Add(new SoundEvent
                {
                    Type = SoundEvent.SoundType.PlayerDeath,
                    Position = frame.PlayerPosition
                });
            }

            // Detect player hit (health decreased but alive)
            if (frame.PlayerAlive && prevFrame.PlayerAlive &&
                frame.PlayerHealth < prevFrame.PlayerHealth)
            {
                frame.Events.Add(new SoundEvent
                {
                    Type = SoundEvent.SoundType.PlayerHit,
                    Position = frame.PlayerPosition
                });
            }

            // Detect penultimate hit (health drops to <= 1 HP)
            if (frame.PlayerAlive && frame.PlayerHealth <= 1.0f &&
                frame.PlayerHealth > 0.0f && prevFrame.PlayerHealth > 1.0f)
            {
                frame.Events.Add(new SoundEvent
                {
                    Type = SoundEvent.SoundType.PenultimateHit,
                    Position = frame.PlayerPosition
                });
            }

            // Detect grenade explosions (grenade count decreased)
            if (frame.Grenades.Count < prevFrame.Grenades.Count)
            {
                // Grenades that were present in previous frame but gone now have exploded
                // Use the previous positions of grenades that disappeared
                for (int i = frame.Grenades.Count; i < prevFrame.Grenades.Count; i++)
                {
                    frame.Events.Add(new SoundEvent
                    {
                        Type = SoundEvent.SoundType.GrenadeExplosion,
                        Position = prevFrame.Grenades[i].Position
                    });
                }
            }
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

            UpdateMuzzleFlashes(delta);

            // Spawn footprints for Memory mode (timed snapshots)
            SpawnFootprintsUpToTime(_playbackTime);

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

            // Play events for all frames we may have skipped over
            if (_playbackFrame > _lastAppliedFrame)
            {
                for (int fi = Mathf.Max(_lastAppliedFrame + 1, 0); fi <= _playbackFrame && fi < _frames.Count; fi++)
                {
                    PlayFrameEvents(_frames[fi]);
                }
                _lastAppliedFrame = _playbackFrame;
            }

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

                var ghostModel = _ghostPlayer.GetNodeOrNull<Node2D>("PlayerModel");
                if (ghostModel != null)
                {
                    ghostModel.GlobalRotation = frame.PlayerModelRotation;
                    ghostModel.Scale = frame.PlayerModelScale;

                    ApplyWalkAnimation(ghostModel, frame.PlayerVelocity, delta, ref _ghostPlayerWalkAnimTime, true);
                }

                if (frame.PlayerShooting)
                {
                    SpawnMuzzleFlash(frame.PlayerPosition, frame.PlayerModelRotation);
                }

                // Penultimate hit effect is triggered via PlayFrameEvents sound events
                _prevPlayerHealth = frame.PlayerHealth;
            }

            // Update ghost enemies
            int count = Mathf.Min(_ghostEnemies.Count, frame.Enemies.Count);
            for (int i = 0; i < count; i++)
            {
                var ghost = _ghostEnemies[i];
                var data = frame.Enemies[i];
                if (ghost == null || !IsInstanceValid(ghost)) continue;

                bool prevAlive = i < _ghostEnemyPrevAlive.Count && _ghostEnemyPrevAlive[i];
                if (prevAlive && !data.Alive)
                {
                    if (i < _ghostEnemyDeathTimers.Count)
                        _ghostEnemyDeathTimers[i] = DeathFadeDuration;
                    if (i < _ghostEnemyDeathStartPos.Count)
                        _ghostEnemyDeathStartPos[i] = data.Position;
                    if (i < _ghostEnemyDeathDir.Count)
                        _ghostEnemyDeathDir[i] = data.LastHitDirection.Normalized();
                    ghost.Modulate = new Color(1.5f, 0.3f, 0.3f, 1.0f);

                    // Blood decals at death positions are now captured by the
                    // per-frame cumulative recording and spawned via UpdateReplayBloodDecals.

                    // Hit visual effect is triggered via PlayFrameEvents sound events
                }

                if (i < _ghostEnemyDeathTimers.Count && _ghostEnemyDeathTimers[i] > 0.0f)
                {
                    _ghostEnemyDeathTimers[i] -= delta * _playbackSpeed;
                    float t = Mathf.Clamp(_ghostEnemyDeathTimers[i] / DeathFadeDuration, 0.0f, 1.0f);
                    float progress = 1.0f - t;
                    float easedProgress = 1.0f - Mathf.Pow(1.0f - progress, 2.0f);

                    ghost.Visible = true;

                    Vector2 startPos = i < _ghostEnemyDeathStartPos.Count ? _ghostEnemyDeathStartPos[i] : data.Position;
                    Vector2 fallDir = i < _ghostEnemyDeathDir.Count ? _ghostEnemyDeathDir[i] : Vector2.Right;
                    ghost.GlobalPosition = startPos + fallDir * DeathFallDistance * easedProgress;

                    var enemyModel = ghost.GetNodeOrNull<Node2D>("EnemyModel");
                    if (enemyModel != null)
                    {
                        float fallAngle = fallDir.Angle();
                        float bodyRot = fallAngle * 0.5f * easedProgress;
                        enemyModel.Rotation = bodyRot;

                        var leftArm = enemyModel.GetNodeOrNull<Node2D>("LeftArm");
                        var rightArm = enemyModel.GetNodeOrNull<Node2D>("RightArm");
                        float armAngle = Mathf.DegToRad(30.0f) * easedProgress;
                        if (leftArm != null) leftArm.Rotation = armAngle;
                        if (rightArm != null) rightArm.Rotation = -armAngle;
                    }

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

                    var enemyModel = ghost.GetNodeOrNull<Node2D>("EnemyModel");
                    if (enemyModel != null)
                    {
                        enemyModel.GlobalRotation = data.ModelRotation;
                        enemyModel.Scale = data.ModelScale;
                        enemyModel.Rotation = 0;

                        var leftArm = enemyModel.GetNodeOrNull<Node2D>("LeftArm");
                        var rightArm = enemyModel.GetNodeOrNull<Node2D>("RightArm");
                        if (leftArm != null) leftArm.Rotation = 0;
                        if (rightArm != null) rightArm.Rotation = 0;

                        float walkTime = i < _ghostEnemyWalkAnimTimes.Count ? _ghostEnemyWalkAnimTimes[i] : 0.0f;
                        ApplyWalkAnimation(enemyModel, data.Velocity, delta, ref walkTime, false);
                        if (i < _ghostEnemyWalkAnimTimes.Count)
                            _ghostEnemyWalkAnimTimes[i] = walkTime;
                    }
                }

                if (i < _ghostEnemyPrevAlive.Count)
                    _ghostEnemyPrevAlive[i] = data.Alive;

                if (data.Shooting && data.Alive)
                {
                    SpawnMuzzleFlash(data.Position, data.ModelRotation);
                }
            }

            // Update ghost bullets and their trails
            UpdateGhostProjectiles(frame.Bullets, _ghostBullets, "bullet");
            UpdateBulletTrails(frame.Bullets, _ghostBullets);

            // Update ghost grenades
            UpdateGhostGrenades(frame.Grenades, _ghostGrenades);

            // Update blood decals and casings for Memory mode (per-frame cumulative data)
            UpdateReplayBloodDecals(frame);
            UpdateReplayCasings(frame);

            // Update motion trails (Memory mode only)
            UpdateTrails(frame, delta);
        }

        private void ApplyWalkAnimation(Node2D model, Vector2 velocity, float delta, ref float walkAnimTime, bool isPlayer)
        {
            float speed = velocity.Length();

            var body = model.GetNodeOrNull<Node2D>("Body");
            var head = model.GetNodeOrNull<Node2D>("Head");
            var leftArm = model.GetNodeOrNull<Node2D>("LeftArm");
            var rightArm = model.GetNodeOrNull<Node2D>("RightArm");

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
                if (leftArm != null) leftArm.Position = new Vector2(baseLeftArmX + armSwing, leftArm.Position.Y);
                if (rightArm != null) rightArm.Position = new Vector2(baseRightArmX - armSwing, rightArm.Position.Y);
            }
            else
            {
                walkAnimTime = 0.0f;
                if (body != null) body.Position = new Vector2(body.Position.X, baseBodyY);
                if (head != null) head.Position = new Vector2(head.Position.X, baseHeadY);
                if (leftArm != null) leftArm.Position = new Vector2(baseLeftArmX, leftArm.Position.Y);
                if (rightArm != null) rightArm.Position = new Vector2(baseRightArmX, rightArm.Position.Y);
            }
        }

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
                    float t = newTimer / MuzzleFlashDuration;
                    node.Modulate = new Color(1.0f, 1.0f, 1.0f, t);
                    _activeMuzzleFlashes[i] = (node, newTimer);
                }
            }
        }

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
            while (ghosts.Count > data.Count)
            {
                var last = ghosts[^1];
                ghosts.RemoveAt(ghosts.Count - 1);
                if (last != null && IsInstanceValid(last))
                    last.QueueFree();
            }

            while (ghosts.Count < data.Count)
            {
                var ghost = CreateProjectileGhost(type);
                if (ghost != null)
                    ghosts.Add(ghost);
            }

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

        /// <summary>
        /// Updates the trailing Line2D on ghost bullets to show their path.
        /// Matches GDScript _update_bullet_trail() functionality.
        /// </summary>
        private void UpdateBulletTrails(List<ProjectileFrameData> data, List<Node2D> ghosts)
        {
            int count = Mathf.Min(ghosts.Count, data.Count);
            for (int i = 0; i < count; i++)
            {
                var ghost = ghosts[i];
                if (ghost == null || !IsInstanceValid(ghost)) continue;

                var trail = ghost.GetNodeOrNull<Line2D>("Trail");
                if (trail == null) continue;

                trail.AddPoint(data[i].Position);
                while (trail.GetPointCount() > 6)
                    trail.RemovePoint(0);
            }
        }

        private void UpdateGhostGrenades(List<GrenadeFrameData> data, List<Node2D> ghosts)
        {
            while (ghosts.Count > data.Count)
            {
                var last = ghosts[^1];
                ghosts.RemoveAt(ghosts.Count - 1);
                if (last != null && IsInstanceValid(last))
                    last.QueueFree();
            }

            while (ghosts.Count < data.Count)
            {
                // Get the texture path from the grenade data for proper sprite loading
                string texPath = ghosts.Count < data.Count ? data[ghosts.Count].TexturePath : "";
                var ghost = CreateGrenadeGhost(texPath);
                if (ghost != null)
                    ghosts.Add(ghost);
            }

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
                    int weaponType = i < _enemyWeaponTypes.Count ? _enemyWeaponTypes[i] : 0;
                    var ghostEnemy = CreateEnemyGhost(weaponType);
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

                AddWeaponSpriteToGhost(ghost);

                return ghost;
            }

            var fallback = new Node2D();
            fallback.Name = "GhostPlayer";
            var sprite = new Sprite2D();
            var img = Image.CreateEmpty(16, 16, false, Image.Format.Rgba8);
            img.Fill(new Color(0.2f, 0.6f, 1.0f, 0.8f));
            sprite.Texture = ImageTexture.CreateFromImage(img);
            fallback.AddChild(sprite);
            return fallback;
        }

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

        /// <summary>
        /// Creates an enemy ghost with the correct weapon sprite.
        /// </summary>
        /// <param name="weaponType">Weapon type (0=RIFLE, 1=SHOTGUN, 2=UZI, 3=MACHETE).</param>
        private Node2D? CreateEnemyGhost(int weaponType = 0)
        {
            var enemyScene = GD.Load<PackedScene>("res://scenes/objects/Enemy.tscn");
            if (enemyScene != null)
            {
                var ghost = enemyScene.Instantiate<Node2D>();
                ghost.Name = "GhostEnemy";
                ghost.ProcessMode = ProcessModeEnum.Always;
                DisableNodeProcessing(ghost);
                SetGhostModulate(ghost, new Color(1.0f, 1.0f, 1.0f, 0.9f));

                // Apply the correct weapon sprite based on recorded weapon type.
                // Enemy.tscn defaults to RIFLE sprite; only change if different.
                ApplyEnemyWeaponSprite(ghost, weaponType);

                return ghost;
            }

            var fallback = new Node2D();
            fallback.Name = "GhostEnemy";
            var sprite = new Sprite2D();
            var img = Image.CreateEmpty(16, 16, false, Image.Format.Rgba8);
            img.Fill(new Color(1.0f, 0.2f, 0.2f, 0.8f));
            sprite.Texture = ImageTexture.CreateFromImage(img);
            fallback.AddChild(sprite);
            return fallback;
        }

        /// <summary>
        /// Applies the correct weapon sprite texture to a ghost enemy based on weapon type.
        /// Weapon type 0 (RIFLE) uses the default sprite already in the scene.
        /// </summary>
        private void ApplyEnemyWeaponSprite(Node2D ghost, int weaponType)
        {
            if (weaponType == 0) return; // RIFLE is the default, no change needed

            // Map weapon type to sprite path (matches WeaponConfigComponent constants)
            string? spritePath = weaponType switch
            {
                1 => "res://assets/sprites/weapons/shotgun_topdown.png",     // SHOTGUN
                2 => "res://assets/sprites/weapons/mini_uzi_topdown.png",    // UZI
                3 => "res://assets/sprites/weapons/machete_topdown.png",     // MACHETE
                _ => null
            };

            if (spritePath == null || !ResourceLoader.Exists(spritePath)) return;

            // Find the weapon sprite in the enemy scene (EnemyModel/WeaponMount/WeaponSprite)
            var weaponSprite = ghost.GetNodeOrNull<Sprite2D>("EnemyModel/WeaponMount/WeaponSprite");

            if (weaponSprite != null)
            {
                var texture = GD.Load<Texture2D>(spritePath);
                if (texture != null)
                {
                    weaponSprite.Texture = texture;
                    LogToFile($"Applied weapon sprite to ghost enemy: {spritePath}");
                }
            }
        }

        private Node2D? CreateProjectileGhost(string type, string texturePath = "")
        {
            if (type == "bullet")
            {
                return CreateBulletGhost();
            }
            else
            {
                return CreateGrenadeGhost(texturePath);
            }
        }

        /// <summary>Creates a bullet ghost by loading the actual Bullet.tscn scene.</summary>
        private Node2D? CreateBulletGhost()
        {
            var bulletScene = GD.Load<PackedScene>("res://scenes/projectiles/Bullet.tscn");
            if (bulletScene != null)
            {
                var ghost = bulletScene.Instantiate<Node2D>();
                ghost.Name = "GhostBullet";
                ghost.ProcessMode = ProcessModeEnum.Always;
                DisableNodeProcessing(ghost);

                // Re-initialize the trail Line2D since _ready() was removed by DisableNodeProcessing.
                // The bullet script normally sets trail.top_level = true and clears points.
                var trail = ghost.GetNodeOrNull<Line2D>("Trail");
                if (trail != null)
                {
                    trail.ProcessMode = ProcessModeEnum.Always;
                    trail.ClearPoints();
                    // top_level = true makes the Line2D use global coordinates,
                    // so trail points added via AddPoint() are at their true global positions.
                    trail.TopLevel = true;
                    trail.Position = Vector2.Zero;
                }

                if (_levelNode != null && IsInstanceValid(_levelNode))
                {
                    var ghostContainer = _levelNode.GetNodeOrNull<Node2D>("ReplayGhosts");
                    ghostContainer?.AddChild(ghost);
                }
                return ghost;
            }

            // Fallback: programmatic sprite
            var fallback = new Node2D();
            fallback.Name = "GhostBullet";
            fallback.ProcessMode = ProcessModeEnum.Always;
            var sprite = new Sprite2D();
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
            fallback.AddChild(sprite);

            if (_levelNode != null && IsInstanceValid(_levelNode))
            {
                var ghostContainer = _levelNode.GetNodeOrNull<Node2D>("ReplayGhosts");
                ghostContainer?.AddChild(fallback);
            }
            return fallback;
        }

        /// <summary>Creates a grenade ghost by loading the actual grenade texture.</summary>
        private Node2D? CreateGrenadeGhost(string texturePath)
        {
            var ghost = new Node2D();
            ghost.Name = "GhostGrenade";
            ghost.ProcessMode = ProcessModeEnum.Always;

            var sprite = new Sprite2D();

            // Try to load the actual grenade texture
            if (!string.IsNullOrEmpty(texturePath))
            {
                Texture2D? tex = null;
                if (ResourceLoader.Exists(texturePath))
                    tex = GD.Load<Texture2D>(texturePath);

                if (tex != null)
                {
                    sprite.Texture = tex;
                    LogToFile($"Grenade ghost: loaded texture {texturePath}");
                    ghost.AddChild(sprite);

                    if (_levelNode != null && IsInstanceValid(_levelNode))
                    {
                        var ghostContainer = _levelNode.GetNodeOrNull<Node2D>("ReplayGhosts");
                        ghostContainer?.AddChild(ghost);
                    }
                    return ghost;
                }
            }

            // Try loading common grenade textures in order (flashbang is most common)
            Texture2D? defaultTex = null;
            foreach (var path in new[] {
                "res://assets/sprites/weapons/flashbang.png",
                "res://assets/sprites/weapons/frag_grenade.png",
                "res://assets/sprites/weapons/defensive_grenade.png"
            })
            {
                if (ResourceLoader.Exists(path))
                {
                    defaultTex = GD.Load<Texture2D>(path);
                    if (defaultTex != null)
                    {
                        LogToFile($"Grenade ghost: loaded fallback texture {path}");
                        break;
                    }
                }
            }

            if (defaultTex != null)
            {
                sprite.Texture = defaultTex;
            }
            else
            {
                // Last resort: programmatic fallback
                LogToFile("WARNING: No grenade texture found, using programmatic fallback");
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

            foreach (var child in level.GetChildren())
            {
                if (child is Area2D area2D && (area2D.CollisionLayer & BulletCollisionLayer) != 0)
                    area2D.Visible = false;
            }

            // Hide the score screen CanvasLayer so replay ghosts are visible
            var canvasLayer = level.GetNodeOrNull<CanvasLayer>("CanvasLayer");
            if (canvasLayer != null)
            {
                canvasLayer.Visible = false;
                LogToFile("Hidden CanvasLayer (score screen) for replay visibility");
            }

            // In Memory mode, hide existing blood decals, casings, and footprints
            // (they'll be re-created progressively during playback)
            if (_currentMode == ReplayMode.Memory)
            {
                var bloodDecals = level.GetTree().GetNodesInGroup("blood_puddle");
                foreach (var decal in bloodDecals)
                {
                    if (decal is Node2D d2d)
                        d2d.Visible = false;
                }

                // Hide existing casings
                var casings = level.GetTree().GetNodesInGroup("casings");
                foreach (var casing in casings)
                {
                    if (casing is Node2D c2d)
                        c2d.Visible = false;
                }
                LogToFile($"Hidden {casings.Count} existing casings for progressive replay");

                // Hide existing blood footprints (Sprite2D children of level with BloodFootprint scene)
                foreach (var child in level.GetChildren())
                {
                    if (child is Sprite2D sprite2D &&
                        sprite2D.SceneFilePath.Contains("BloodFootprint"))
                    {
                        sprite2D.Visible = false;
                    }
                }
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

        /// <summary>Reference to the Ghost mode button for state updates.</summary>
        private Button? _ghostModeBtn;
        /// <summary>Reference to the Memory mode button for state updates.</summary>
        private Button? _memoryModeBtn;

        private void CreateReplayUi(Node2D level)
        {
            _replayUi = new CanvasLayer();
            _replayUi.Name = "ReplayUI";
            _replayUi.Layer = 100;
            _replayUi.ProcessMode = ProcessModeEnum.Always;
            level.AddChild(_replayUi);

            // Close button (X) in top-right corner — returns to score screen
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
            closeBtn.TooltipText = "Return to results (ESC)";
            _replayUi.AddChild(closeBtn);

            // Mode switcher (top-left corner)
            var modeContainer = new HBoxContainer();
            modeContainer.Name = "ModeContainer";
            modeContainer.SetAnchorsPreset(Control.LayoutPreset.TopLeft);
            modeContainer.OffsetLeft = 10;
            modeContainer.OffsetTop = 10;
            modeContainer.OffsetRight = 300;
            modeContainer.OffsetBottom = 50;
            modeContainer.AddThemeConstantOverride("separation", 5);
            _replayUi.AddChild(modeContainer);

            var modeLabel = new Label();
            modeLabel.Text = "MODE:";
            modeLabel.AddThemeFontSizeOverride("font_size", 16);
            modeLabel.AddThemeColorOverride("font_color", new Color(0.7f, 0.7f, 0.7f, 1.0f));
            modeContainer.AddChild(modeLabel);

            _ghostModeBtn = new Button();
            _ghostModeBtn.Text = "\ud83d\udc7b Ghost";
            _ghostModeBtn.CustomMinimumSize = new Vector2(90, 35);
            _ghostModeBtn.AddThemeFontSizeOverride("font_size", 14);
            _ghostModeBtn.ProcessMode = ProcessModeEnum.Always;
            _ghostModeBtn.Pressed += () => SetReplayMode(ReplayMode.Ghost);
            _ghostModeBtn.TooltipText = "Red/black/white stylized replay";
            modeContainer.AddChild(_ghostModeBtn);

            _memoryModeBtn = new Button();
            _memoryModeBtn.Text = "\ud83c\udfac Memory";
            _memoryModeBtn.CustomMinimumSize = new Vector2(100, 35);
            _memoryModeBtn.AddThemeFontSizeOverride("font_size", 14);
            _memoryModeBtn.ProcessMode = ProcessModeEnum.Always;
            _memoryModeBtn.Pressed += () => SetReplayMode(ReplayMode.Memory);
            _memoryModeBtn.TooltipText = "Full color with effects and trails";
            modeContainer.AddChild(_memoryModeBtn);

            UpdateModeButtonStates();

            // Bottom panel
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

            // Exit button — returns to score screen
            var exitBtn = new Button();
            exitBtn.Text = "Back to Results (ESC)";
            exitBtn.CustomMinimumSize = new Vector2(180, 40);
            exitBtn.Pressed += OnExitReplayPressed;
            container.AddChild(exitBtn);

            PlaybackProgress += UpdateReplayUi;
        }

        /// <summary>Updates the visual state of mode toggle buttons.</summary>
        private void UpdateModeButtonStates()
        {
            if (_ghostModeBtn != null && IsInstanceValid(_ghostModeBtn))
            {
                _ghostModeBtn.Disabled = (_currentMode == ReplayMode.Ghost);
            }
            if (_memoryModeBtn != null && IsInstanceValid(_memoryModeBtn))
            {
                _memoryModeBtn.Disabled = (_currentMode == ReplayMode.Memory);
            }
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

        /// <summary>
        /// Called when the X button or ESC is pressed during replay.
        /// Returns to the score/results screen instead of reloading the scene.
        /// </summary>
        private void OnExitReplayPressed()
        {
            LogToFile("Exit replay pressed — returning to results screen");

            StopPlayback();

            if (_levelNode == null || !IsInstanceValid(_levelNode)) return;

            _levelNode.GetTree().Paused = false;

            // Re-show the score screen CanvasLayer (was hidden when replay started)
            var canvasLayer = _levelNode.GetNodeOrNull<CanvasLayer>("CanvasLayer");
            if (canvasLayer != null)
            {
                canvasLayer.Visible = true;
                LogToFile("Score screen CanvasLayer re-shown");
            }

            // Re-show original entities that were hidden for replay
            var player = _levelNode.GetNodeOrNull<Node2D>("Entities/Player");
            if (player != null) player.Visible = true;

            var enemiesNode = _levelNode.GetNodeOrNull("Environment/Enemies");
            if (enemiesNode != null)
            {
                foreach (var enemy in enemiesNode.GetChildren())
                {
                    if (enemy is Node2D enemy2D)
                        enemy2D.Visible = true;
                }
            }

            // Re-show blood decals that were hidden for Memory mode
            var bloodDecals = _levelNode.GetTree().GetNodesInGroup("blood_puddle");
            foreach (var decal in bloodDecals)
            {
                if (decal is Node2D d2d)
                    d2d.Visible = true;
            }

            // Re-show casings that were hidden for Memory mode
            var casings = _levelNode.GetTree().GetNodesInGroup("casings");
            foreach (var casing in casings)
            {
                if (casing is Node2D c2d)
                    c2d.Visible = true;
            }

            // Re-show footprints that were hidden for Memory mode
            foreach (var child in _levelNode.GetChildren())
            {
                if (child is Sprite2D sprite2D &&
                    sprite2D.SceneFilePath.Contains("BloodFootprint"))
                {
                    sprite2D.Visible = true;
                }
            }

            // Restore world colors (in case Ghost mode tinted them)
            RestoreWorldColors();

            // Show cursor for button interaction
            Input.SetMouseMode(Input.MouseModeEnum.Confined);
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
                    case Key.G:
                        SetReplayMode(ReplayMode.Ghost);
                        break;
                    case Key.M:
                        SetReplayMode(ReplayMode.Memory);
                        break;
                }
            }
        }

        // ============================================================
        // Sound event playback and grenade explosion effects
        // ============================================================

        /// <summary>
        /// Plays sound events and visual effects for a frame during replay playback.
        /// Triggers AudioManager sounds and visual effects without modifying Engine.TimeScale.
        /// </summary>
        private void PlayFrameEvents(FrameData frame)
        {
            if (frame.Events.Count == 0) return;

            LogToFile($"PlayFrameEvents: processing {frame.Events.Count} events at time {frame.Time:F2}s (mode={_currentMode})");

            var audioManager = GetNodeOrNull("/root/AudioManager");

            foreach (var evt in frame.Events)
            {
                switch (evt.Type)
                {
                    case SoundEvent.SoundType.Shot:
                        if (audioManager != null && audioManager.HasMethod("play_m16_shot"))
                            audioManager.Call("play_m16_shot", evt.Position);
                        break;

                    case SoundEvent.SoundType.Death:
                        if (audioManager != null && audioManager.HasMethod("play_hit_lethal"))
                            audioManager.Call("play_hit_lethal", evt.Position);
                        TriggerReplayHitEffect();
                        TriggerReplayPowerFantasyKill();
                        break;

                    case SoundEvent.SoundType.Hit:
                        if (audioManager != null && audioManager.HasMethod("play_hit_non_lethal"))
                            audioManager.Call("play_hit_non_lethal", evt.Position);
                        TriggerReplayHitEffect();
                        break;

                    case SoundEvent.SoundType.PlayerDeath:
                        if (audioManager != null && audioManager.HasMethod("play_hit_lethal"))
                            audioManager.Call("play_hit_lethal", evt.Position);
                        break;

                    case SoundEvent.SoundType.PlayerHit:
                        if (audioManager != null && audioManager.HasMethod("play_hit_non_lethal"))
                            audioManager.Call("play_hit_non_lethal", evt.Position);
                        break;

                    case SoundEvent.SoundType.PenultimateHit:
                        TriggerReplayPenultimateEffect();
                        break;

                    case SoundEvent.SoundType.GrenadeExplosion:
                        if (audioManager != null && audioManager.HasMethod("play_flashbang_explosion"))
                            audioManager.Call("play_flashbang_explosion", evt.Position, false);
                        SpawnExplosionFlash(evt.Position);
                        TriggerReplayPowerFantasyGrenade();
                        break;
                }
            }
        }

        /// <summary>
        /// Spawns a brief explosion flash at the given position during replay.
        /// Uses PointLight2D with shadow support for wall occlusion.
        /// </summary>
        private void SpawnExplosionFlash(Vector2 position)
        {
            if (_levelNode == null || !IsInstanceValid(_levelNode)) return;
            var ghostContainer = _levelNode.GetNodeOrNull<Node2D>("ReplayGhosts");
            if (ghostContainer == null) return;

            // Try to use the actual explosion flash scene
            var explosionScene = GD.Load<PackedScene>("res://scenes/effects/ExplosionFlash.tscn");
            if (explosionScene != null)
            {
                var flash = explosionScene.Instantiate<Node2D>();
                flash.ProcessMode = ProcessModeEnum.Always;
                flash.GlobalPosition = position;
                ghostContainer.AddChild(flash);
                return;
            }

            // Fallback: create a PointLight2D flash manually
            var flashNode = new PointLight2D();
            flashNode.Name = "ExplosionFlash";
            flashNode.ProcessMode = ProcessModeEnum.Always;
            flashNode.GlobalPosition = position;
            flashNode.Color = new Color(1.0f, 0.9f, 0.5f, 1.0f);
            flashNode.Energy = 3.0f;
            flashNode.TextureScale = 4.0f;
            flashNode.ShadowEnabled = true;

            // Create a radial gradient texture for the light
            var texture = new GradientTexture2D();
            texture.Width = 128;
            texture.Height = 128;
            texture.Fill = GradientTexture2D.FillEnum.Radial;
            texture.FillFrom = new Vector2(0.5f, 0.5f);
            texture.FillTo = new Vector2(1.0f, 0.5f);
            var gradient = new Gradient();
            gradient.SetColor(0, Colors.White);
            gradient.SetColor(1, new Color(1.0f, 1.0f, 1.0f, 0.0f));
            texture.Gradient = gradient;
            flashNode.Texture = texture;

            ghostContainer.AddChild(flashNode);

            // Schedule cleanup after 0.3 seconds using a timer
            var cleanupTimer = new Godot.Timer();
            cleanupTimer.WaitTime = 0.3;
            cleanupTimer.OneShot = true;
            cleanupTimer.ProcessMode = ProcessModeEnum.Always;
            cleanupTimer.Timeout += () =>
            {
                if (IsInstanceValid(flashNode))
                    flashNode.QueueFree();
                if (IsInstanceValid(cleanupTimer))
                    cleanupTimer.QueueFree();
            };
            ghostContainer.AddChild(cleanupTimer);
            cleanupTimer.Start();
        }

        // ============================================================
        // Replay visual effects (visual-only via replay_mode flag, no time manipulation)
        // Issue #597: Effect managers have a replay_mode flag that prevents
        // Engine.TimeScale and process_mode changes while keeping all visual effects.
        // ============================================================

        /// <summary>
        /// Triggers the hit effect during replay playback.
        /// The HitEffectsManager.replay_mode flag prevents Engine.TimeScale changes
        /// while still applying the saturation shader overlay.
        /// </summary>
        private void TriggerReplayHitEffect()
        {
            // Only trigger gameplay effects in Memory mode.
            // Ghost mode uses a stylized red/black/white filter.
            if (_currentMode != ReplayMode.Memory) return;

            var hitEffects = GetNodeOrNull("/root/HitEffectsManager");
            if (hitEffects != null && hitEffects.HasMethod("on_player_hit_enemy"))
            {
                hitEffects.Call("on_player_hit_enemy");
                LogToFile("Replay effect triggered: HitEffects.on_player_hit_enemy");
            }
        }

        /// <summary>
        /// Triggers the penultimate hit effect during replay playback.
        /// The PenultimateHitEffectsManager.replay_mode flag prevents Engine.TimeScale
        /// changes while still applying saturation/contrast shader and enemy coloring.
        /// </summary>
        private void TriggerReplayPenultimateEffect()
        {
            // Only trigger gameplay effects in Memory mode.
            if (_currentMode != ReplayMode.Memory) return;

            var penultimateEffects = GetNodeOrNull("/root/PenultimateHitEffectsManager");
            if (penultimateEffects != null)
            {
                // Call directly — HasMethod may not find underscore-prefixed methods reliably.
                penultimateEffects.Call("_start_penultimate_effect");
                LogToFile("Replay effect triggered: PenultimateHit._start_penultimate_effect");
            }
        }

        /// <summary>
        /// Triggers the Power Fantasy kill effect during replay playback.
        /// Calls _start_effect() directly (bypassing difficulty check) because
        /// the replay_mode flag prevents Engine.TimeScale changes.
        /// </summary>
        private void TriggerReplayPowerFantasyKill()
        {
            // Only trigger gameplay effects in Memory mode.
            if (_currentMode != ReplayMode.Memory) return;

            var powerFantasyManager = GetNodeOrNull("/root/PowerFantasyEffectsManager");
            if (powerFantasyManager != null)
            {
                // Call _start_effect directly — HasMethod may not find underscore-prefixed
                // GDScript methods reliably in all Godot versions.
                powerFantasyManager.Call("_start_effect", 300.0);
                LogToFile("Replay effect triggered: PowerFantasy._start_effect(300ms)");
            }
        }

        /// <summary>
        /// Triggers the Power Fantasy grenade explosion effect during replay playback.
        /// Calls LastChanceEffectsManager.trigger_grenade_last_chance() directly because
        /// the replay_mode flag prevents process_mode freezing.
        /// </summary>
        private void TriggerReplayPowerFantasyGrenade()
        {
            // Only trigger gameplay effects in Memory mode.
            if (_currentMode != ReplayMode.Memory) return;

            var lastChanceManager = GetNodeOrNull("/root/LastChanceEffectsManager");
            if (lastChanceManager != null && lastChanceManager.HasMethod("trigger_grenade_last_chance"))
            {
                lastChanceManager.Call("trigger_grenade_last_chance", 2.0);
                LogToFile("Replay effect triggered: LastChance.trigger_grenade_last_chance(2.0s)");
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
