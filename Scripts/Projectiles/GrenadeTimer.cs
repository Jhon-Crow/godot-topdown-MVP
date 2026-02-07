using Godot;
using System;

namespace GodotTopdown.Scripts.Projectiles
{
    /// <summary>
    /// C# component for reliable grenade timer and explosion handling.
    ///
    /// CRITICAL FIX for Issue #432: GDScript methods called via C# Call() silently fail
    /// in exported builds, causing grenades to fly infinitely without exploding.
    ///
    /// This C# component provides a reliable fallback that works regardless of
    /// whether GDScript is executing properly. It handles:
    /// - Timer-based explosion (Flashbang grenades)
    /// - Impact-based explosion (Frag grenades)
    /// - Explosion effects and damage
    /// </summary>
    [GlobalClass]
    public partial class GrenadeTimer : Node
    {
        /// <summary>
        /// The grenade type determines explosion behavior.
        /// Flashbang: Timer-based (4 seconds after activation)
        /// Frag: Impact-based (explodes on contact with walls/enemies)
        /// </summary>
        public enum GrenadeType
        {
            Flashbang,
            Frag
        }

        [Export]
        public GrenadeType Type { get; set; } = GrenadeType.Flashbang;

        [Export]
        public float FuseTime { get; set; } = 4.0f;

        /// <summary>
        /// Effect radius for explosion damage and visual effects.
        /// NOTE: Default is 400 for Flashbang. For Frag grenades, this should be set to 225.
        /// The value should be copied from the grenade's GDScript export or set based on type.
        /// IMPORTANT: In exported builds, GDScript property access via Get() may fail silently,
        /// so SetTypeBasedDefaults() should be called to ensure correct values.
        /// </summary>
        [Export]
        public float EffectRadius { get; set; } = 400.0f;

        [Export]
        public int ExplosionDamage { get; set; } = 99;

        [Export]
        public float BlindnessDuration { get; set; } = 12.0f;

        [Export]
        public float StunDuration { get; set; } = 6.0f;

        /// <summary>
        /// Ground friction for slowing down the grenade (must match GDScript ground_friction).
        /// This is critical because GDScript _physics_process() may not run in exports!
        /// </summary>
        [Export]
        public float GroundFriction { get; set; } = 300.0f;

        /// <summary>
        /// Whether the timer has been activated (pin pulled).
        /// </summary>
        public bool IsTimerActive { get; private set; } = false;

        // NOTE: We always apply C# friction because GDScript _physics_process() does NOT run
        // in exported builds. Detection logic was removed as it added complexity without benefit.

        /// <summary>
        /// Whether the grenade has been thrown (can explode on impact).
        /// </summary>
        public bool IsThrown { get; private set; } = false;

        /// <summary>
        /// Whether the grenade has already exploded.
        /// </summary>
        public bool HasExploded { get; private set; } = false;

        private float _timeRemaining = 0.0f;
        private RigidBody2D? _grenadeBody = null;
        private Vector2 _previousVelocity = Vector2.Zero;
        private bool _hasLanded = false;

        // Landing detection threshold (same as GDScript)
        private const float LandingVelocityThreshold = 50.0f;

        // Type-specific default values from scene files
        // These are used as fallback when GDScript property access fails in exports
        private const float DefaultFragEffectRadius = 225.0f;    // From FragGrenade.tscn
        private const float DefaultFlashbangEffectRadius = 400.0f; // From FlashbangGrenade.tscn
        private const float DefaultFragGroundFriction = 280.0f;  // From FragGrenade.tscn
        private const float DefaultFlashbangGroundFriction = 300.0f; // From FlashbangGrenade.tscn

        /// <summary>
        /// Track whether type-based defaults have been applied.
        /// </summary>
        private bool _defaultsApplied = false;

        /// <summary>
        /// Set default values based on grenade type.
        /// FIX for Issue #432: GDScript Get() calls may fail silently in exported builds,
        /// returning Nil instead of the actual property value. This method ensures correct
        /// values are used based on the grenade type.
        /// </summary>
        public void SetTypeBasedDefaults()
        {
            if (_defaultsApplied)
                return;

            _defaultsApplied = true;

            if (Type == GrenadeType.Frag)
            {
                // Frag grenade defaults (from FragGrenade.tscn)
                // Only override if still at default flashbang values (property read likely failed)
                if (EffectRadius >= 400.0f - 0.01f)  // Using epsilon for float comparison
                {
                    EffectRadius = DefaultFragEffectRadius;
                    LogToFile($"[GrenadeTimer] Applied Frag default effect_radius: {EffectRadius}");
                }
                if (GroundFriction >= 300.0f - 0.01f)
                {
                    GroundFriction = DefaultFragGroundFriction;
                }
            }
            else
            {
                // Flashbang grenade defaults (from FlashbangGrenade.tscn)
                // These are already the default values, but set explicitly for clarity
                if (EffectRadius < 400.0f - 0.01f)
                {
                    EffectRadius = DefaultFlashbangEffectRadius;
                    LogToFile($"[GrenadeTimer] Applied Flashbang default effect_radius: {EffectRadius}");
                }
            }
        }

        public override void _Ready()
        {
            // Get the parent grenade body
            _grenadeBody = GetParent<RigidBody2D>();
            if (_grenadeBody == null)
            {
                GD.PrintErr("[GrenadeTimer] ERROR: Parent is not a RigidBody2D!");
                return;
            }

            // FIX for Issue #432: Apply type-based defaults BEFORE logging.
            // GDScript Get() calls may fail silently in exports, leaving us with
            // incorrect default values (e.g., Frag using Flashbang's 400 radius).
            SetTypeBasedDefaults();

            // Connect to body_entered signal for impact detection
            _grenadeBody.BodyEntered += OnBodyEntered;

            LogToFile($"[GrenadeTimer] Initialized for {Type} grenade, effect radius: {EffectRadius}");
        }

        public override void _ExitTree()
        {
            if (_grenadeBody != null)
            {
                _grenadeBody.BodyEntered -= OnBodyEntered;
            }
        }

        public override void _PhysicsProcess(double delta)
        {
            if (HasExploded || _grenadeBody == null)
                return;

            // CRITICAL FIX for Issue #432: GDScript _physics_process() does NOT run in exported builds!
            // Evidence from user logs (game_log_20260203_223841.txt):
            //   - Flashbang target: 221.7px, actually traveled: 560px (2.5x overshoot!)
            //   - No friction applied whatsoever
            // We MUST apply friction in C# since GDScript is completely non-functional in exports.
            if (IsThrown && !_grenadeBody.Freeze)
            {
                ApplyGroundFriction((float)delta);
            }

            // Timer countdown for Flashbang grenades
            if (IsTimerActive && Type == GrenadeType.Flashbang)
            {
                _timeRemaining -= (float)delta;
                if (_timeRemaining <= 0)
                {
                    LogToFile("[GrenadeTimer] Timer expired - EXPLODING!");
                    Explode();
                    return;
                }
            }

            // Landing detection for ALL grenades (FIX for Issue #432)
            // Flashbang grenades need landing detection to emit sound for enemy awareness.
            // GDScript _physics_process() doesn't run in exports, so C# handles this.
            if (IsThrown && !_hasLanded)
            {
                float currentSpeed = _grenadeBody.LinearVelocity.Length();
                float previousSpeed = _previousVelocity.Length();

                // Grenade has landed when it was moving fast and now nearly stopped
                if (previousSpeed > LandingVelocityThreshold && currentSpeed < LandingVelocityThreshold)
                {
                    _hasLanded = true;

                    if (Type == GrenadeType.Frag)
                    {
                        // Frag grenades explode on landing
                        LogToFile("[GrenadeTimer] Frag grenade landed - EXPLODING!");
                        Explode();
                        return;
                    }
                    else
                    {
                        // Flashbang grenades emit landing sound for enemy awareness (Issue #432)
                        LogToFile($"[GrenadeTimer] Flashbang grenade landed at {_grenadeBody.GlobalPosition}");
                        EmitGrenadeLandingSound(_grenadeBody.GlobalPosition);
                    }
                }

                _previousVelocity = _grenadeBody.LinearVelocity;
            }
        }

        /// <summary>
        /// Activate the grenade timer (called when pin is pulled).
        /// </summary>
        public void ActivateTimer()
        {
            if (IsTimerActive)
            {
                LogToFile("[GrenadeTimer] Timer already active");
                return;
            }

            IsTimerActive = true;
            _timeRemaining = FuseTime;
            LogToFile($"[GrenadeTimer] Timer activated! {FuseTime} seconds until explosion");
        }

        /// <summary>
        /// Mark the grenade as thrown (enables impact detection for Frag grenades).
        /// </summary>
        public void MarkAsThrown()
        {
            if (IsThrown)
                return;

            IsThrown = true;
            LogToFile("[GrenadeTimer] Grenade marked as thrown - impact detection enabled");
        }

        /// <summary>
        /// Apply ground friction to slow down the grenade.
        /// CRITICAL: This replicates the GDScript _physics_process() friction logic
        /// because GDScript may not run in exported builds!
        /// Formula matches grenade_base.gd: friction_force = velocity.normalized() * ground_friction * delta
        /// </summary>
        private void ApplyGroundFriction(float delta)
        {
            if (_grenadeBody == null || _grenadeBody.Freeze)
                return;

            Vector2 velocity = _grenadeBody.LinearVelocity;
            if (velocity.Length() <= 0.01f)
                return;

            // Calculate friction force (same as GDScript)
            Vector2 frictionForce = velocity.Normalized() * GroundFriction * delta;

            // If friction would overshoot, just stop
            if (frictionForce.Length() >= velocity.Length())
            {
                _grenadeBody.LinearVelocity = Vector2.Zero;
            }
            else
            {
                _grenadeBody.LinearVelocity = velocity - frictionForce;
            }
        }

        /// <summary>
        /// Handle collision with bodies (walls, enemies, etc.).
        /// </summary>
        private void OnBodyEntered(Node body)
        {
            if (HasExploded)
                return;

            // Only Frag grenades explode on impact
            if (Type != GrenadeType.Frag)
                return;

            // Only explode if grenade has been thrown
            if (!IsThrown)
                return;

            // Trigger explosion on solid body contact
            // Note: Check TileMap for legacy Godot 4 and TileMapLayer for newer versions
            if (body is StaticBody2D || body is TileMap || body is TileMapLayer || body is CharacterBody2D)
            {
                LogToFile($"[GrenadeTimer] Impact detected with {body.Name} - EXPLODING!");
                Explode();
            }
        }

        /// <summary>
        /// Trigger the grenade explosion.
        /// </summary>
        public void Explode()
        {
            if (HasExploded)
                return;

            HasExploded = true;

            if (_grenadeBody == null)
                return;

            Vector2 explosionPosition = _grenadeBody.GlobalPosition;
            LogToFile($"[GrenadeTimer] EXPLODED at {explosionPosition}!");

            // Trigger Power Fantasy grenade explosion effect (time-freeze)
            // FIX for Issue #555: GDScript grenade_base._explode() calls PowerFantasyEffectsManager
            // but when C# GrenadeTimer.Explode() fires first and QueueFree()s the grenade,
            // the GDScript path never runs, so the time-freeze effect was missing.
            var powerFantasyManager = GetNodeOrNull("/root/PowerFantasyEffectsManager");
            if (powerFantasyManager != null && powerFantasyManager.HasMethod("on_grenade_exploded"))
            {
                powerFantasyManager.Call("on_grenade_exploded");
            }

            // Apply explosion effects based on type
            if (Type == GrenadeType.Frag)
            {
                ApplyFragExplosion(explosionPosition);
            }
            else
            {
                ApplyFlashbangExplosion(explosionPosition);
            }

            // Play explosion sound
            PlayExplosionSound(explosionPosition);

            // Spawn visual effect
            SpawnExplosionEffect(explosionPosition);

            // Scatter shell casings
            ScatterCasings(explosionPosition);

            // Destroy the grenade
            _grenadeBody.QueueFree();
        }

        /// <summary>
        /// Apply Frag grenade explosion damage.
        /// </summary>
        private void ApplyFragExplosion(Vector2 position)
        {
            LogToFile($"[GrenadeTimer] Applying frag explosion damage (radius: {EffectRadius}, damage: {ExplosionDamage})");

            // Damage enemies in radius
            var enemies = GetTree().GetNodesInGroup("enemies");
            foreach (var enemy in enemies)
            {
                if (enemy is Node2D enemyNode)
                {
                    float distance = position.DistanceTo(enemyNode.GlobalPosition);
                    if (distance <= EffectRadius)
                    {
                        // Check line of sight
                        if (HasLineOfSightTo(position, enemyNode.GlobalPosition))
                        {
                            ApplyDamage(enemyNode, position);
                            LogToFile($"[GrenadeTimer] Damaged enemy at distance {distance:F1}");
                        }
                    }
                }
            }

            // Damage player if in radius
            var players = GetTree().GetNodesInGroup("player");
            foreach (var player in players)
            {
                if (player is Node2D playerNode)
                {
                    float distance = position.DistanceTo(playerNode.GlobalPosition);
                    if (distance <= EffectRadius)
                    {
                        if (HasLineOfSightTo(position, playerNode.GlobalPosition))
                        {
                            ApplyDamage(playerNode, position);
                            LogToFile($"[GrenadeTimer] Damaged player at distance {distance:F1}");
                        }
                    }
                }
            }

            // Spawn shrapnel
            SpawnShrapnel(position);
        }

        /// <summary>
        /// Apply Flashbang grenade effects.
        /// FIX for Issue #469: Flashbang effects should not pass through walls.
        /// Both enemies AND player now require line-of-sight check.
        /// </summary>
        private void ApplyFlashbangExplosion(Vector2 position)
        {
            LogToFile($"[GrenadeTimer] Applying flashbang effects (radius: {EffectRadius}, blindness: {BlindnessDuration}s, stun: {StunDuration}s)");

            // Get all entities in effect radius
            var enemies = GetTree().GetNodesInGroup("enemies");
            var players = GetTree().GetNodesInGroup("player");

            // Affect enemies
            foreach (var enemy in enemies)
            {
                if (enemy is Node2D enemyNode)
                {
                    float distance = position.DistanceTo(enemyNode.GlobalPosition);
                    if (distance <= EffectRadius)
                    {
                        if (HasLineOfSightTo(position, enemyNode.GlobalPosition))
                        {
                            ApplyFlashbangEffect(enemyNode, distance);
                        }
                    }
                }
            }

            // Affect player (if too close AND has line of sight) - Issue #469 fix
            // Walls now block flashbang effect on player, same as enemies
            foreach (var player in players)
            {
                if (player is Node2D playerNode)
                {
                    float distance = position.DistanceTo(playerNode.GlobalPosition);
                    if (distance <= EffectRadius)
                    {
                        // FIX Issue #469: Check line of sight - walls block flashbang effect
                        if (HasLineOfSightTo(position, playerNode.GlobalPosition))
                        {
                            ApplyFlashbangEffectToPlayer(playerNode, distance);
                        }
                        else
                        {
                            LogToFile($"[GrenadeTimer] Player behind wall - flashbang blocked (distance: {distance:F1})");
                        }
                    }
                }
            }
        }

        /// <summary>
        /// Apply flashbang effect to enemy.
        /// </summary>
        private void ApplyFlashbangEffect(Node2D enemy, float distance)
        {
            // Calculate effect intensity based on distance (closer = stronger)
            float intensity = 1.0f - (distance / EffectRadius);

            // Try to apply stun via method call
            if (enemy.HasMethod("apply_flashbang_effect"))
            {
                enemy.Call("apply_flashbang_effect", BlindnessDuration * intensity, StunDuration * intensity);
            }
            else if (enemy.HasMethod("stun"))
            {
                enemy.Call("stun", StunDuration * intensity);
            }

            LogToFile($"[GrenadeTimer] Applied flashbang to enemy at distance {distance:F1} (intensity: {intensity:F2})");
        }

        /// <summary>
        /// Apply flashbang effect to player.
        /// </summary>
        private void ApplyFlashbangEffectToPlayer(Node2D player, float distance)
        {
            // Calculate effect intensity based on distance
            float intensity = 1.0f - (distance / EffectRadius);

            // Try to find and trigger screen flash effect
            var flashScreen = GetNodeOrNull("/root/FlashScreen");
            if (flashScreen != null && flashScreen.HasMethod("flash"))
            {
                flashScreen.Call("flash", BlindnessDuration * intensity);
            }

            LogToFile($"[GrenadeTimer] Applied flashbang to player at distance {distance:F1}");
        }

        /// <summary>
        /// Apply damage to an entity.
        /// </summary>
        private void ApplyDamage(Node2D target, Vector2 explosionPosition)
        {
            Vector2 hitDirection = (target.GlobalPosition - explosionPosition).Normalized();

            if (target.HasMethod("on_hit_with_info"))
            {
                for (int i = 0; i < ExplosionDamage; i++)
                {
                    target.Call("on_hit_with_info", hitDirection, (GodotObject?)null);
                }
            }
            else if (target.HasMethod("on_hit"))
            {
                for (int i = 0; i < ExplosionDamage; i++)
                {
                    target.Call("on_hit");
                }
            }
        }

        /// <summary>
        /// Check if there's line of sight between two positions.
        /// </summary>
        private bool HasLineOfSightTo(Vector2 from, Vector2 to)
        {
            if (_grenadeBody == null)
                return true;

            var spaceState = _grenadeBody.GetWorld2D().DirectSpaceState;
            var query = PhysicsRayQueryParameters2D.Create(from, to);
            query.CollisionMask = 4; // Obstacles only
            query.Exclude = new Godot.Collections.Array<Rid> { _grenadeBody.GetRid() };

            var result = spaceState.IntersectRay(query);
            return result.Count == 0;
        }

        /// <summary>
        /// Play explosion sound.
        /// </summary>
        private void PlayExplosionSound(Vector2 position)
        {
            var audioManager = GetNodeOrNull("/root/AudioManager");
            if (audioManager != null && audioManager.HasMethod("play_flashbang_explosion"))
            {
                bool playerInZone = IsPlayerInZone(position);
                audioManager.Call("play_flashbang_explosion", position, playerInZone);
            }

            // Emit sound for AI awareness
            var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
            if (soundPropagation != null && soundPropagation.HasMethod("emit_sound"))
            {
                float soundRange = 2938.0f; // 2x viewport diagonal
                soundPropagation.Call("emit_sound", 1, position, 2, _grenadeBody, soundRange);
            }
        }

        /// <summary>
        /// Emit grenade landing sound for enemy awareness (Issue #432).
        /// FIX: GDScript _on_grenade_landed() doesn't run in exports, so C# emits the landing sound
        /// for SoundPropagation to notify enemies, allowing them to flee from grenades.
        /// </summary>
        private void EmitGrenadeLandingSound(Vector2 position)
        {
            // Play landing sound via AudioManager
            var audioManager = GetNodeOrNull("/root/AudioManager");
            if (audioManager != null && audioManager.HasMethod("play_grenade_landing"))
            {
                audioManager.Call("play_grenade_landing", position);
            }

            // Emit grenade landing sound for AI awareness via SoundPropagation
            // This triggers enemy grenade avoidance behavior (Issue #426, #407)
            var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
            if (soundPropagation != null && soundPropagation.HasMethod("emit_grenade_landing"))
            {
                soundPropagation.Call("emit_grenade_landing", position, _grenadeBody);
                LogToFile($"[GrenadeTimer] Emitted grenade landing sound at {position}");
            }
        }

        /// <summary>
        /// Check if player is in effect zone (distance AND line of sight).
        /// FIX for Issue #469: Walls block flashbang effects, so we check line of sight.
        /// </summary>
        private bool IsPlayerInZone(Vector2 position)
        {
            var players = GetTree().GetNodesInGroup("player");
            foreach (var player in players)
            {
                if (player is Node2D playerNode)
                {
                    if (position.DistanceTo(playerNode.GlobalPosition) <= EffectRadius)
                    {
                        // FIX Issue #469: Also check line of sight - walls block the effect
                        if (HasLineOfSightTo(position, playerNode.GlobalPosition))
                        {
                            return true;
                        }
                    }
                }
            }
            return false;
        }

        /// <summary>
        /// Spawn visual explosion effect using PointLight2D with shadow_enabled for wall occlusion.
        /// FIX for Issue #432: GDScript Call() silently fails in exports, so we implement
        /// the explosion effect directly in C# to ensure it always works.
        /// FIX for Issue #469: Flashbang uses shadow-enabled PointLight2D so flash doesn't pass through walls.
        /// FIX for Issue #470: Frag grenade uses PointLight2D with shadow_enabled=true to automatically
        /// respect wall geometry through Godot's native 2D lighting/shadow system.
        /// </summary>
        private void SpawnExplosionEffect(Vector2 position)
        {
            if (Type == GrenadeType.Flashbang)
            {
                // Flashbang uses FlashbangEffect.tscn from main branch (Issue #469)
                SpawnFlashbangEffectScene(position);
                return;
            }

            // Frag grenades use ExplosionFlash.tscn from issue-470 branch (Issue #470)
            SpawnFragExplosionFlash(position);
        }

        /// <summary>
        /// Loads and instantiates the FlashbangEffect.tscn scene directly from C#.
        /// FIX for Issue #469: Uses shadow-enabled PointLight2D so flash doesn't pass through walls.
        /// FIX for Issue #432: Bypasses GDScript Call() which fails silently in exports.
        /// </summary>
        private void SpawnFlashbangEffectScene(Vector2 position)
        {
            const string flashbangEffectPath = "res://scenes/effects/FlashbangEffect.tscn";

            // Try to load the flashbang effect scene
            var flashbangScene = GD.Load<PackedScene>(flashbangEffectPath);
            if (flashbangScene == null)
            {
                LogToFile($"[GrenadeTimer] WARNING: FlashbangEffect scene not found at {flashbangEffectPath}, using fallback");
                CreateFallbackExplosionFlash(position);
                return;
            }

            // Instantiate the effect
            var effect = flashbangScene.Instantiate<Node2D>();
            if (effect == null)
            {
                LogToFile($"[GrenadeTimer] WARNING: Failed to instantiate FlashbangEffect, using fallback");
                CreateFallbackExplosionFlash(position);
                return;
            }

            // Position the effect at explosion location
            effect.GlobalPosition = position;

            // Set the effect radius if the method exists
            if (effect.HasMethod("set_effect_radius"))
            {
                effect.Call("set_effect_radius", EffectRadius);
            }

            // Add to the current scene
            GetTree().CurrentScene?.AddChild(effect);

            LogToFile($"[GrenadeTimer] Spawned shadow-enabled flashbang effect at {position} (radius: {EffectRadius})");
        }

        /// <summary>
        /// Spawn frag grenade explosion flash using ExplosionFlash.tscn.
        /// FIX for Issue #470: Uses PointLight2D with shadow_enabled=true for wall occlusion.
        /// </summary>
        private void SpawnFragExplosionFlash(Vector2 position)
        {
            // Try to load and use the new PointLight2D-based explosion flash scene
            // This uses shadow_enabled=true to automatically respect wall geometry
            var explosionFlashScene = GD.Load<PackedScene>("res://scenes/effects/ExplosionFlash.tscn");

            if (explosionFlashScene != null)
            {
                var flash = explosionFlashScene.Instantiate();
                if (flash is Node2D flashNode)
                {
                    flashNode.GlobalPosition = position;

                    // Set explosion type (1 = Frag)
                    flashNode.Set("explosion_type", 1);
                    flashNode.Set("effect_radius", EffectRadius);

                    GetTree().CurrentScene.AddChild(flash);
                    LogToFile($"[GrenadeTimer] Spawned PointLight2D frag explosion flash at {position} (shadow-based wall occlusion)");
                    return;
                }
            }

            // Fallback: create simple PointLight2D directly if scene loading fails
            LogToFile("[GrenadeTimer] ExplosionFlash.tscn not found, using fallback PointLight2D");
            CreateFallbackExplosionFlash(position);
        }

        /// <summary>
        /// Fallback explosion flash using PointLight2D directly.
        /// Used when ExplosionFlash.tscn cannot be loaded.
        /// Uses shadow_enabled=true to respect wall geometry.
        /// </summary>
        private void CreateFallbackExplosionFlash(Vector2 position)
        {
            // Create PointLight2D with shadow enabled for wall occlusion
            var light = new PointLight2D();
            light.GlobalPosition = position;
            light.ZIndex = 10;

            // Enable shadows so light respects wall geometry
            light.ShadowEnabled = true;
            light.ShadowColor = new Color(0, 0, 0, 0.9f);
            light.ShadowFilter = PointLight2D.ShadowFilterEnum.Pcf5;
            light.ShadowFilterSmooth = 6.0f;

            // Create gradient texture for the light
            light.Texture = CreateLightGradientTexture();

            // Set color and intensity based on grenade type
            if (Type == GrenadeType.Flashbang)
            {
                light.Color = new Color(1.0f, 0.95f, 0.9f, 1.0f);
                light.Energy = 8.0f;
                light.TextureScale = EffectRadius / 100.0f;
            }
            else
            {
                light.Color = new Color(1.0f, 0.6f, 0.2f, 1.0f);
                light.Energy = 6.0f;
                light.TextureScale = EffectRadius / 80.0f;
            }

            // Add to scene
            GetTree().CurrentScene.AddChild(light);

            // Create tween to fade out the light
            var tween = GetTree().CreateTween();
            float fadeDuration = Type == GrenadeType.Flashbang ? 0.4f : 0.3f;
            tween.TweenProperty(light, "energy", 0.0f, fadeDuration).SetEase(Tween.EaseType.Out);
            tween.TweenCallback(Callable.From(() => light.QueueFree()));

            LogToFile($"[GrenadeTimer] Spawned fallback PointLight2D explosion at {position}");
        }

        /// <summary>
        /// Create a gradient texture for the PointLight2D.
        /// Creates a radial gradient from white center to transparent edges.
        /// </summary>
        private static ImageTexture CreateLightGradientTexture()
        {
            int size = 512;
            int radius = size / 2;
            var image = Image.CreateEmpty(size, size, false, Image.Format.Rgba8);
            var center = new Vector2(radius, radius);

            for (int x = 0; x < size; x++)
            {
                for (int y = 0; y < size; y++)
                {
                    var pos = new Vector2(x, y);
                    float distance = pos.DistanceTo(center);
                    float normalizedDist = Mathf.Clamp(distance / radius, 0.0f, 1.0f);

                    // Create gradient: bright center fading to transparent edges
                    // Use smooth gradient for natural light falloff
                    float alpha = 1.0f - (normalizedDist * normalizedDist);
                    alpha = Mathf.Max(0.0f, alpha);

                    image.SetPixel(x, y, new Color(1.0f, 1.0f, 1.0f, alpha));
                }
            }

            return ImageTexture.CreateFromImage(image);
        }

        /// <summary>
        /// Spawn shrapnel for Frag grenades.
        /// </summary>
        private void SpawnShrapnel(Vector2 position)
        {
            var shrapnelPath = "res://scenes/projectiles/Shrapnel.tscn";
            var shrapnelScene = GD.Load<PackedScene>(shrapnelPath);
            if (shrapnelScene == null)
            {
                LogToFile("[GrenadeTimer] Shrapnel scene not found");
                return;
            }

            int shrapnelCount = 4;
            float angleStep = Mathf.Tau / shrapnelCount;

            for (int i = 0; i < shrapnelCount; i++)
            {
                float baseAngle = i * angleStep;
                float deviation = (float)GD.RandRange(-0.35, 0.35);
                float finalAngle = baseAngle + deviation;

                Vector2 direction = new Vector2(Mathf.Cos(finalAngle), Mathf.Sin(finalAngle));

                var shrapnel = shrapnelScene.Instantiate();
                if (shrapnel is Node2D shrapnelNode)
                {
                    shrapnelNode.GlobalPosition = position + direction * 10.0f;
                    shrapnelNode.Set("direction", direction);

                    GetTree().CurrentScene.AddChild(shrapnel);
                }
            }

            LogToFile($"[GrenadeTimer] Spawned {shrapnelCount} shrapnel pieces");
        }

        /// <summary>
        /// Scatter shell casings near explosion.
        /// Issue #506: Checks line of sight so casings behind obstacles are not pushed.
        /// </summary>
        private void ScatterCasings(Vector2 position)
        {
            var casings = GetTree().GetNodesInGroup("casings");
            float proximityRadius = EffectRadius * 1.5f;
            // FIX for Issue #432: User requested casings scatter "almost as fast as bullets"
            // Bullet speed is 2500 px/s, so lethal zone casings should get ~2000 impulse
            // Casings have mass and friction so actual velocity will be lower
            float lethalImpulse = 2000.0f;  // Near bullet speed for dramatic scatter
            float proximityImpulse = 500.0f;  // Strong push for outer zone too

            int scatteredCount = 0;

            foreach (var casing in casings)
            {
                if (casing is RigidBody2D casingBody)
                {
                    float distance = position.DistanceTo(casingBody.GlobalPosition);
                    if (distance > proximityRadius)
                        continue;

                    // Issue #506: Check line of sight - obstacles block the shockwave
                    if (!HasLineOfSightTo(position, casingBody.GlobalPosition))
                        continue;

                    Vector2 direction = (casingBody.GlobalPosition - position).Normalized();
                    direction = direction.Rotated((float)GD.RandRange(-0.2, 0.2));

                    float impulseStrength;
                    if (distance <= EffectRadius)
                    {
                        float factor = 1.0f - (distance / EffectRadius);
                        impulseStrength = lethalImpulse * Mathf.Sqrt(factor + 0.1f);
                    }
                    else
                    {
                        float factor = 1.0f - ((distance - EffectRadius) / (proximityRadius - EffectRadius));
                        impulseStrength = proximityImpulse * factor;
                    }

                    if (casingBody.HasMethod("receive_kick"))
                    {
                        casingBody.Call("receive_kick", direction * impulseStrength);
                        scatteredCount++;
                    }
                }
            }

            if (scatteredCount > 0)
            {
                LogToFile($"[GrenadeTimer] Scattered {scatteredCount} casings");
            }
        }

        /// <summary>
        /// Log message to FileLogger if available.
        /// </summary>
        private void LogToFile(string message)
        {
            var fileLogger = GetNodeOrNull("/root/FileLogger");
            if (fileLogger != null && fileLogger.HasMethod("info"))
            {
                fileLogger.Call("info", message);
            }
            else
            {
                GD.Print(message);
            }
        }
    }
}
