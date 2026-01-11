namespace GodotTopDownTemplate.Interfaces;

/// <summary>
/// Interface for entities that can receive damage.
/// Implement this interface on any game object that should be able to take damage.
/// </summary>
public interface IDamageable
{
    /// <summary>
    /// Current health value of the entity.
    /// </summary>
    float CurrentHealth { get; }

    /// <summary>
    /// Maximum health value of the entity.
    /// </summary>
    float MaxHealth { get; }

    /// <summary>
    /// Whether the entity is currently alive (health > 0).
    /// </summary>
    bool IsAlive { get; }

    /// <summary>
    /// Apply damage to the entity.
    /// </summary>
    /// <param name="amount">Amount of damage to apply.</param>
    void TakeDamage(float amount);

    /// <summary>
    /// Heal the entity.
    /// </summary>
    /// <param name="amount">Amount of health to restore.</param>
    void Heal(float amount);

    /// <summary>
    /// Called when the entity dies (health reaches 0).
    /// </summary>
    void OnDeath();
}
