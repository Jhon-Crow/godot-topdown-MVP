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
    /// - Player position, rotation, and model scale
    /// - Enemy positions, rotations, and alive state
    /// - Bullet positions and rotations
    /// - Grenade positions
    /// - Key events (shots, deaths, explosions)
    ///
    /// Playback recreates the visual representation without running game logic.
    /// </summary>
    [GlobalClass]
    public partial class ReplayManager : Node
    {
        /// <summary>Recording interval in seconds (physics frames).</summary>
        private const float RecordInterval = 1.0f / 60.0f;

        /// <summary>Maximum recording duration in seconds (prevent memory issues).</summary>
        private const float MaxRecordingDuration = 300.0f;

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

        /// <summary>Reference to the level node being recorded.</summary>
        private Node2D? _levelNode;

        /// <summary>Reference to the player node.</summary>
        private Node2D? _player;

        /// <summary>References to enemy nodes.</summary>
        private readonly List<Node> _enemies = new();

        /// <summary>Path to the Entities/Projectiles node.</summary>
        private const string ProjectilesPath = "Entities/Projectiles";

        /// <summary>Replay ghost nodes.</summary>
        private Node2D? _ghostPlayer;
        private readonly List<Node2D> _ghostEnemies = new();
        private readonly List<Node2D> _ghostBullets = new();
        private readonly List<Node2D> _ghostGrenades = new();

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
            public Vector2 PlayerModelScale = Vector2.One;
            public bool PlayerAlive = true;
            public List<EnemyFrameData> Enemies = new();
            public List<ProjectileFrameData> Bullets = new();
            public List<Vector2> Grenades = new();
        }

        private class EnemyFrameData
        {
            public Vector2 Position;
            public float Rotation;
            public bool Alive = true;
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
        // GDScript callers use snake_case via Godot's automatic conversion.
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

            var playerName = player?.Name ?? "NULL";
            var playerValid = player != null && IsInstanceValid(player);
            var levelName = level?.Name ?? "NULL";

            LogToFile("=== REPLAY RECORDING STARTED ===");
            LogToFile($"Level: {levelName}");
            LogToFile($"Player: {playerName} (valid: {playerValid})");
            LogToFile($"Enemies count: {_enemies.Count}");

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

            ApplyFrame(_frames[_playbackFrame]);
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

                var playerModel = _player.GetNodeOrNull<Node2D>("PlayerModel");
                if (playerModel != null)
                    frame.PlayerModelScale = playerModel.Scale;

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

                    if (enemy.HasMethod("is_alive"))
                        enemyData.Alive = (bool)enemy.Call("is_alive");
                    else
                    {
                        var aliveVar = enemy.Get("_is_alive");
                        if (aliveVar.VariantType != Variant.Type.Nil)
                            enemyData.Alive = (bool)aliveVar;
                    }

                    frame.Enemies.Add(enemyData);
                }
                else
                {
                    frame.Enemies.Add(new EnemyFrameData { Alive = false });
                }
            }

            // Record projectiles (bullets)
            if (_levelNode != null && IsInstanceValid(_levelNode))
            {
                var projectilesNode = _levelNode.GetNodeOrNull(ProjectilesPath);
                projectilesNode ??= _levelNode.GetNodeOrNull("Projectiles");

                if (projectilesNode != null)
                {
                    foreach (var projectile in projectilesNode.GetChildren())
                    {
                        if (projectile is Node2D proj2D)
                        {
                            frame.Bullets.Add(new ProjectileFrameData
                            {
                                Position = proj2D.GlobalPosition,
                                Rotation = proj2D.GlobalRotation
                            });
                        }
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

            if (_playbackTime >= GetReplayDuration())
            {
                _playbackTime = GetReplayDuration();
                ApplyFrame(_frames[^1]);
                _playbackEnding = true;
                _playbackEndTimer = 0.5f;
                _isPlayingBack = false;
                return;
            }

            while (_playbackFrame < _frames.Count - 1 && _frames[_playbackFrame + 1].Time <= _playbackTime)
                _playbackFrame++;

            ApplyFrame(_frames[_playbackFrame]);
        }

        private void ApplyFrame(FrameData frame)
        {
            // Update ghost player
            if (_ghostPlayer != null && IsInstanceValid(_ghostPlayer))
            {
                _ghostPlayer.GlobalPosition = frame.PlayerPosition;
                _ghostPlayer.GlobalRotation = frame.PlayerRotation;
                _ghostPlayer.Visible = frame.PlayerAlive;

                var ghostModel = _ghostPlayer.GetNodeOrNull<Node2D>("PlayerModel");
                if (ghostModel != null)
                    ghostModel.Scale = frame.PlayerModelScale;
            }

            // Update ghost enemies
            int count = Mathf.Min(_ghostEnemies.Count, frame.Enemies.Count);
            for (int i = 0; i < count; i++)
            {
                var ghost = _ghostEnemies[i];
                var data = frame.Enemies[i];
                if (ghost != null && IsInstanceValid(ghost))
                {
                    ghost.GlobalPosition = data.Position;
                    ghost.GlobalRotation = data.Rotation;
                    ghost.Visible = data.Alive;
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

            var ghostContainer = new Node2D();
            ghostContainer.Name = "ReplayGhosts";
            ghostContainer.ProcessMode = ProcessModeEnum.Always;
            level.AddChild(ghostContainer);

            _ghostPlayer = CreatePlayerGhost();
            if (_ghostPlayer != null)
                ghostContainer.AddChild(_ghostPlayer);

            if (_frames.Count > 0 && _frames[0].Enemies.Count > 0)
            {
                for (int i = 0; i < _frames[0].Enemies.Count; i++)
                {
                    var ghostEnemy = CreateEnemyGhost();
                    if (ghostEnemy != null)
                    {
                        ghostContainer.AddChild(ghostEnemy);
                        _ghostEnemies.Add(ghostEnemy);
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
                texture.Width = 8;
                texture.Height = 3;
                texture.FillFrom = new Vector2(0, 0);
                texture.FillTo = new Vector2(1, 0);
                var gradient = new Gradient();
                gradient.SetColor(0, new Color(1.0f, 0.9f, 0.2f, 1.0f));
                gradient.SetColor(1, new Color(1.0f, 0.7f, 0.1f, 1.0f));
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

            var projectiles = level.GetNodeOrNull<Node2D>("Entities/Projectiles");
            if (projectiles != null) projectiles.Visible = false;
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
            replayLabel.Text = "▶ REPLAY";
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
