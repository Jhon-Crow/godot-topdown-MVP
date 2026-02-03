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

        /// <summary>
        /// Whether C# should apply friction (only when GDScript is not running).
        /// We detect this by checking if velocity is being reduced each frame.
        /// If velocity is NOT being reduced (GDScript friction not working), we apply it.
        /// </summary>
        private bool _shouldApplyFriction = false;
        private Vector2 _lastVelocityForFrictionCheck = Vector2.Zero;
        private int _framesWithoutFriction = 0;
        private const int FramesToDetectNoFriction = 3;

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

        public override void _Ready()
        {
            // Get the parent grenade body
            _grenadeBody = GetParent<RigidBody2D>();
            if (_grenadeBody == null)
            {
                GD.PrintErr("[GrenadeTimer] ERROR: Parent is not a RigidBody2D!");
                return;
            }

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

            // CRITICAL FIX for Issue #432: Apply ground friction in C# ONLY if GDScript is not doing it.
            // GDScript _physics_process() applies friction, so we must detect if it's running.
            // If velocity is NOT being reduced each frame, GDScript friction isn't working.
            DetectAndApplyFriction((float)delta);

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

            // Landing detection for Frag grenades
            if (IsThrown && Type == GrenadeType.Frag && !_hasLanded)
            {
                float currentSpeed = _grenadeBody.LinearVelocity.Length();
                float previousSpeed = _previousVelocity.Length();

                // Grenade has landed when it was moving fast and now nearly stopped
                if (previousSpeed > LandingVelocityThreshold && currentSpeed < LandingVelocityThreshold)
                {
                    LogToFile("[GrenadeTimer] Frag grenade landed - EXPLODING!");
                    _hasLanded = true;
                    Explode();
                    return;
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
        /// Detect if GDScript friction is working and apply C# friction only if needed.
        /// This prevents double-friction which causes grenades to stop way too early.
        /// </summary>
        private void DetectAndApplyFriction(float delta)
        {
            if (_grenadeBody == null || _grenadeBody.Freeze)
                return;

            Vector2 currentVelocity = _grenadeBody.LinearVelocity;

            // Skip if grenade is already stopped
            if (currentVelocity.Length() <= 0.01f)
            {
                _lastVelocityForFrictionCheck = currentVelocity;
                return;
            }

            // Check if velocity has been reduced since last frame (GDScript friction working)
            if (_lastVelocityForFrictionCheck.Length() > 0.01f)
            {
                float expectedVelocityWithoutFriction = _lastVelocityForFrictionCheck.Length();
                float actualVelocity = currentVelocity.Length();

                // Calculate how much friction SHOULD have reduced velocity this frame
                float expectedFrictionReduction = GroundFriction * delta;

                // If velocity dropped by roughly the expected amount, GDScript friction is working
                float velocityDrop = expectedVelocityWithoutFriction - actualVelocity;

                // GDScript is applying friction if velocity dropped by at least 50% of expected
                if (velocityDrop >= expectedFrictionReduction * 0.5f)
                {
                    // GDScript friction is working - don't apply C# friction
                    _framesWithoutFriction = 0;
                    _shouldApplyFriction = false;
                }
                else
                {
                    // Velocity didn't drop as expected - GDScript might not be working
                    _framesWithoutFriction++;

                    // After several frames with no friction, enable C# friction
                    if (_framesWithoutFriction >= FramesToDetectNoFriction)
                    {
                        _shouldApplyFriction = true;
                    }
                }
            }

            // Store current velocity for next frame comparison
            _lastVelocityForFrictionCheck = currentVelocity;

            // Apply C# friction only if GDScript friction is not working
            if (_shouldApplyFriction)
            {
                ApplyGroundFriction(delta);
            }
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
            if (body is StaticBody2D || body is TileMapLayer || body is CharacterBody2D)
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

            // Affect player (if too close)
            foreach (var player in players)
            {
                if (player is Node2D playerNode)
                {
                    float distance = position.DistanceTo(playerNode.GlobalPosition);
                    if (distance <= EffectRadius)
                    {
                        ApplyFlashbangEffectToPlayer(playerNode, distance);
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
        /// Check if player is in effect zone.
        /// </summary>
        private bool IsPlayerInZone(Vector2 position)
        {
            var players = GetTree().GetNodesInGroup("player");
            foreach (var player in players)
            {
                if (player is Node2D playerNode)
                {
                    if (position.DistanceTo(playerNode.GlobalPosition) <= EffectRadius)
                        return true;
                }
            }
            return false;
        }

        /// <summary>
        /// Spawn visual explosion effect.
        /// </summary>
        private void SpawnExplosionEffect(Vector2 position)
        {
            // First, try to trigger the GDScript explosion effect method on the grenade itself
            // This handles the visual effects defined in the GDScript subclass (FragGrenade, FlashbangGrenade)
            if (_grenadeBody != null && _grenadeBody.HasMethod("_spawn_explosion_effect"))
            {
                _grenadeBody.Call("_spawn_explosion_effect");
                LogToFile("[GrenadeTimer] Called GDScript _spawn_explosion_effect()");
            }
            else if (_grenadeBody != null && _grenadeBody.HasMethod("_create_simple_explosion"))
            {
                // Fallback to simple explosion if the specific method isn't available
                _grenadeBody.Call("_create_simple_explosion");
                LogToFile("[GrenadeTimer] Called GDScript _create_simple_explosion()");
            }
            else
            {
                // Final fallback: use ImpactEffectsManager directly
                var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
                if (impactManager != null && impactManager.HasMethod("spawn_flashbang_effect"))
                {
                    impactManager.Call("spawn_flashbang_effect", position, EffectRadius);
                    LogToFile("[GrenadeTimer] Called ImpactEffectsManager.spawn_flashbang_effect()");
                }
                else
                {
                    LogToFile("[GrenadeTimer] WARNING: No explosion effect method available");
                }
            }
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
