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
    /// Whether to use random initial health.
    /// </summary>
    [Export]
    public bool UseRandomHealth { get; set; } = false;

    /// <summary>
    /// Minimum random health (when UseRandomHealth is true).
    /// </summary>
    [Export]
    public int MinRandomHealth { get; set; } = 2;

    /// <summary>
    /// Maximum random health (when UseRandomHealth is true).
    /// </summary>
    [Export]
    public int MaxRandomHealth { get; set; } = 4;

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
        InitializeHealth();
    }

    /// <summary>
    /// Initializes health based on configuration settings.
    /// If UseRandomHealth is true, generates random health between MinRandomHealth and MaxRandomHealth.
    /// Otherwise uses InitialHealth if positive, or MaxHealth.
    /// </summary>
    public void InitializeHealth()
    {
        string ownerName = GetParent()?.Name ?? "Unknown";

        if (UseRandomHealth)
        {
            // Generate random health between min and max (inclusive)
            int randomHealth = GD.RandRange(MinRandomHealth, MaxRandomHealth);
            MaxHealth = MaxRandomHealth;
            CurrentHealth = randomHealth;
            GD.Print($"[HealthComponent] {ownerName}: Initialized with random health {CurrentHealth}/{MaxHealth} (range: {MinRandomHealth}-{MaxRandomHealth})");
        }
        else
        {
            CurrentHealth = InitialHealth > 0 ? InitialHealth : MaxHealth;
            GD.Print($"[HealthComponent] {ownerName}: Initialized with health {CurrentHealth}/{MaxHealth}");
        }

        EmitSignal(SignalName.HealthChanged, CurrentHealth, MaxHealth);
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

        string ownerName = GetParent()?.Name ?? "Unknown";
        float previousHealth = CurrentHealth;
        CurrentHealth = Mathf.Max(0, CurrentHealth - amount);

        float actualDamage = previousHealth - CurrentHealth;
        GD.Print($"[HealthComponent] {ownerName}: Took {actualDamage} damage. Health: {previousHealth} -> {CurrentHealth}/{MaxHealth}");

        EmitSignal(SignalName.Damaged, actualDamage, CurrentHealth);
        EmitSignal(SignalName.HealthChanged, CurrentHealth, MaxHealth);

        if (!IsAlive)
        {
            GD.Print($"[HealthComponent] {ownerName}: Died!");
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
    /// Resets health to maximum, or re-randomizes if UseRandomHealth is enabled.
    /// </summary>
    public void ResetToMax()
    {
        string ownerName = GetParent()?.Name ?? "Unknown";

        if (UseRandomHealth)
        {
            // Re-randomize health on reset
            int randomHealth = GD.RandRange(MinRandomHealth, MaxRandomHealth);
            CurrentHealth = randomHealth;
            GD.Print($"[HealthComponent] {ownerName}: Reset with new random health {CurrentHealth}/{MaxHealth}");
        }
        else
        {
            CurrentHealth = MaxHealth;
            GD.Print($"[HealthComponent] {ownerName}: Reset to max health {CurrentHealth}/{MaxHealth}");
        }
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
