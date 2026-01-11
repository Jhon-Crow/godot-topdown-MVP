using Godot;

namespace GodotTopDownTemplate.Components;

/// <summary>
/// Reusable component for managing entity health.
/// Can be attached to any Node to give it health management capabilities.
/// </summary>
public partial class HealthComponent : Node
{
    /// <summary>
    /// Maximum health value.
    /// </summary>
    [Export]
    public float MaxHealth { get; set; } = 100.0f;

    /// <summary>
    /// Initial health value. If 0 or negative, uses MaxHealth.
    /// </summary>
    [Export]
    public float InitialHealth { get; set; } = 0.0f;

    /// <summary>
    /// Whether the entity can be damaged.
    /// </summary>
    [Export]
    public bool Invulnerable { get; set; } = false;

    /// <summary>
    /// Current health value.
    /// </summary>
    public float CurrentHealth { get; private set; }

    /// <summary>
    /// Whether the entity is alive (health > 0).
    /// </summary>
    public bool IsAlive => CurrentHealth > 0;

    /// <summary>
    /// Health as a percentage (0.0 to 1.0).
    /// </summary>
    public float HealthPercent => MaxHealth > 0 ? CurrentHealth / MaxHealth : 0;

    /// <summary>
    /// Signal emitted when damage is taken.
    /// </summary>
    [Signal]
    public delegate void DamagedEventHandler(float amount, float currentHealth);

    /// <summary>
    /// Signal emitted when healed.
    /// </summary>
    [Signal]
    public delegate void HealedEventHandler(float amount, float currentHealth);

    /// <summary>
    /// Signal emitted when health changes (either damage or heal).
    /// </summary>
    [Signal]
    public delegate void HealthChangedEventHandler(float currentHealth, float maxHealth);

    /// <summary>
    /// Signal emitted when the entity dies (health reaches 0).
    /// </summary>
    [Signal]
    public delegate void DiedEventHandler();

    public override void _Ready()
    {
        // Initialize health
        CurrentHealth = InitialHealth > 0 ? InitialHealth : MaxHealth;
    }

    /// <summary>
    /// Apply damage to the entity.
    /// </summary>
    /// <param name="amount">Amount of damage to apply (positive value).</param>
    public void TakeDamage(float amount)
    {
        if (Invulnerable || !IsAlive || amount <= 0)
        {
            return;
        }

        float previousHealth = CurrentHealth;
        CurrentHealth = Mathf.Max(0, CurrentHealth - amount);

        float actualDamage = previousHealth - CurrentHealth;

        EmitSignal(SignalName.Damaged, actualDamage, CurrentHealth);
        EmitSignal(SignalName.HealthChanged, CurrentHealth, MaxHealth);

        if (!IsAlive)
        {
            EmitSignal(SignalName.Died);
        }
    }

    /// <summary>
    /// Heal the entity.
    /// </summary>
    /// <param name="amount">Amount of health to restore (positive value).</param>
    public void Heal(float amount)
    {
        if (!IsAlive || amount <= 0)
        {
            return;
        }

        float previousHealth = CurrentHealth;
        CurrentHealth = Mathf.Min(MaxHealth, CurrentHealth + amount);

        float actualHeal = CurrentHealth - previousHealth;

        if (actualHeal > 0)
        {
            EmitSignal(SignalName.Healed, actualHeal, CurrentHealth);
            EmitSignal(SignalName.HealthChanged, CurrentHealth, MaxHealth);
        }
    }

    /// <summary>
    /// Sets health to a specific value.
    /// </summary>
    /// <param name="value">The new health value.</param>
    public void SetHealth(float value)
    {
        bool wasAlive = IsAlive;
        CurrentHealth = Mathf.Clamp(value, 0, MaxHealth);
        EmitSignal(SignalName.HealthChanged, CurrentHealth, MaxHealth);

        if (wasAlive && !IsAlive)
        {
            EmitSignal(SignalName.Died);
        }
    }

    /// <summary>
    /// Resets health to maximum.
    /// </summary>
    public void ResetToMax()
    {
        CurrentHealth = MaxHealth;
        EmitSignal(SignalName.HealthChanged, CurrentHealth, MaxHealth);
    }

    /// <summary>
    /// Sets max health and optionally scales current health proportionally.
    /// </summary>
    /// <param name="newMaxHealth">The new maximum health value.</param>
    /// <param name="scaleCurrentHealth">If true, scales current health proportionally.</param>
    public void SetMaxHealth(float newMaxHealth, bool scaleCurrentHealth = false)
    {
        if (newMaxHealth <= 0)
        {
            return;
        }

        if (scaleCurrentHealth && MaxHealth > 0)
        {
            float ratio = CurrentHealth / MaxHealth;
            MaxHealth = newMaxHealth;
            CurrentHealth = MaxHealth * ratio;
        }
        else
        {
            MaxHealth = newMaxHealth;
            CurrentHealth = Mathf.Min(CurrentHealth, MaxHealth);
        }

        EmitSignal(SignalName.HealthChanged, CurrentHealth, MaxHealth);
    }
}
