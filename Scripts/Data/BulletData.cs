using Godot;

namespace GodotTopDownTemplate.Data;

/// <summary>
/// Resource class containing bullet configuration data.
/// Can be saved as .tres files and shared between bullet instances.
/// </summary>
[GlobalClass]
public partial class BulletData : Resource
{
    /// <summary>
    /// Speed of the bullet in pixels per second.
    /// </summary>
    [Export]
    public float Speed { get; set; } = 600.0f;

    /// <summary>
    /// Damage dealt by the bullet on hit.
    /// </summary>
    [Export]
    public float Damage { get; set; } = 10.0f;

    /// <summary>
    /// Maximum lifetime in seconds before auto-destruction.
    /// </summary>
    [Export]
    public float Lifetime { get; set; } = 3.0f;

    /// <summary>
    /// Whether the bullet pierces through targets.
    /// </summary>
    [Export]
    public bool Piercing { get; set; } = false;

    /// <summary>
    /// Maximum number of targets the bullet can pierce (if Piercing is true).
    /// </summary>
    [Export]
    public int MaxPierceCount { get; set; } = 1;

    /// <summary>
    /// Size/scale of the bullet for collision and visuals.
    /// </summary>
    [Export]
    public float Size { get; set; } = 1.0f;

    /// <summary>
    /// Knockback force applied to hit targets.
    /// </summary>
    [Export]
    public float Knockback { get; set; } = 0.0f;

    /// <summary>
    /// Color tint of the bullet.
    /// </summary>
    [Export]
    public Color Color { get; set; } = new Color(1.0f, 0.9f, 0.2f, 1.0f);
}
