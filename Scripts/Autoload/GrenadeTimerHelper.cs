using Godot;
using GodotTopdown.Scripts.Projectiles;

namespace GodotTopdown.Scripts.Autoload
{
    /// <summary>
    /// Autoload helper for attaching C# GrenadeTimer component to grenades.
    ///
    /// FIX for Issue #432: Enemy grenades thrown by GDScript code need the C# GrenadeTimer
    /// component for reliable explosion handling in exports. GDScript can call methods on this
    /// autoload to add the component without needing to instantiate C# classes directly.
    ///
    /// Usage from GDScript:
    ///   var helper = get_node_or_null("/root/GrenadeTimerHelper")
    ///   if helper:
    ///       helper.attach_grenade_timer(grenade, "Frag")  # or "Flashbang"
    ///       helper.activate_timer(grenade)
    ///       helper.mark_as_thrown(grenade)
    /// </summary>
    [GlobalClass]
    public partial class GrenadeTimerHelper : Node
    {
        public override void _Ready()
        {
            LogToFile("[GrenadeTimerHelper] Autoload ready");
        }

        /// <summary>
        /// Attach a GrenadeTimer component to a grenade.
        /// Call this from GDScript immediately after instantiating a grenade.
        /// </summary>
        /// <param name="grenade">The grenade RigidBody2D to attach the timer to.</param>
        /// <param name="grenadeType">Type of grenade: "Frag" or "Flashbang".</param>
        public void AttachGrenadeTimer(RigidBody2D grenade, string grenadeType)
        {
            if (grenade == null)
            {
                GD.PrintErr("[GrenadeTimerHelper] ERROR: grenade is null");
                return;
            }

            // Check if timer already exists
            var existingTimer = grenade.GetNodeOrNull<GrenadeTimer>("GrenadeTimer");
            if (existingTimer != null)
            {
                LogToFile("[GrenadeTimerHelper] GrenadeTimer already attached to " + grenade.Name);
                return;
            }

            // Determine grenade type
            var type = grenadeType.ToLower().Contains("frag")
                ? GrenadeTimer.GrenadeType.Frag
                : GrenadeTimer.GrenadeType.Flashbang;

            // Create and configure the GrenadeTimer component
            var timer = new GrenadeTimer();
            timer.Name = "GrenadeTimer";
            timer.Type = type;

            // Copy relevant properties from grenade (if they exist as exported properties)
            var fuseTime = grenade.Get("fuse_time");
            if (fuseTime.VariantType != Variant.Type.Nil)
            {
                timer.FuseTime = (float)fuseTime;
            }

            var effectRadius = grenade.Get("effect_radius");
            if (effectRadius.VariantType != Variant.Type.Nil)
            {
                timer.EffectRadius = (float)effectRadius;
            }

            var explosionDamage = grenade.Get("explosion_damage");
            if (explosionDamage.VariantType != Variant.Type.Nil)
            {
                timer.ExplosionDamage = (int)explosionDamage;
            }

            var blindnessDuration = grenade.Get("blindness_duration");
            if (blindnessDuration.VariantType != Variant.Type.Nil)
            {
                timer.BlindnessDuration = (float)blindnessDuration;
            }

            var stunDuration = grenade.Get("stun_duration");
            if (stunDuration.VariantType != Variant.Type.Nil)
            {
                timer.StunDuration = (float)stunDuration;
            }

            var groundFriction = grenade.Get("ground_friction");
            if (groundFriction.VariantType != Variant.Type.Nil)
            {
                timer.GroundFriction = (float)groundFriction;
            }

            // FIX for Issue #432: Apply type-based defaults BEFORE adding to scene.
            // GDScript Get() calls may fail silently in exported builds, leaving us with
            // incorrect values (e.g., Frag grenade using Flashbang's 400 radius instead of 225).
            timer.SetTypeBasedDefaults();

            // Add the timer component to the grenade
            grenade.AddChild(timer);
            LogToFile($"[GrenadeTimerHelper] Attached GrenadeTimer to {grenade.Name} (type: {type})");
        }

        /// <summary>
        /// Activate the grenade timer (call when pin is pulled).
        /// </summary>
        public void ActivateTimer(RigidBody2D grenade)
        {
            if (grenade == null)
            {
                GD.PrintErr("[GrenadeTimerHelper] ERROR: grenade is null");
                return;
            }

            var timer = grenade.GetNodeOrNull<GrenadeTimer>("GrenadeTimer");
            if (timer == null)
            {
                LogToFile("[GrenadeTimerHelper] WARNING: No GrenadeTimer found on " + grenade.Name);
                return;
            }

            timer.ActivateTimer();
        }

        /// <summary>
        /// Mark the grenade as thrown (enables impact detection for Frag grenades).
        /// </summary>
        public void MarkAsThrown(RigidBody2D grenade)
        {
            if (grenade == null)
            {
                GD.PrintErr("[GrenadeTimerHelper] ERROR: grenade is null");
                return;
            }

            var timer = grenade.GetNodeOrNull<GrenadeTimer>("GrenadeTimer");
            if (timer == null)
            {
                LogToFile("[GrenadeTimerHelper] WARNING: No GrenadeTimer found on " + grenade.Name);
                return;
            }

            timer.MarkAsThrown();
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
