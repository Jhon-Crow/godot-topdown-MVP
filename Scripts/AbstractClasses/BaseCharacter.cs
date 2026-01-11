using Godot;
using GodotTopDownTemplate.Components;
using GodotTopDownTemplate.Interfaces;

namespace GodotTopDownTemplate.AbstractClasses;

/// <summary>
/// Abstract base class for all characters in the game (players, enemies, NPCs).
/// Provides common functionality for movement, health management, and damage handling.
/// </summary>
public abstract partial class BaseCharacter : CharacterBody2D, IDamageable
{
    /// <summary>
    /// Maximum movement speed in pixels per second.
    /// </summary>
    [Export]
    public float MaxSpeed { get; set; } = 200.0f;

    /// <summary>
    /// Acceleration rate - how quickly the character reaches max speed.
    /// </summary>
    [Export]
    public float Acceleration { get; set; } = 1200.0f;

    /// <summary>
    /// Friction rate - how quickly the character slows down when not moving.
    /// </summary>
    [Export]
    public float Friction { get; set; } = 1000.0f;

    /// <summary>
    /// Health component for managing health.
    /// </summary>
    protected HealthComponent? HealthComponent { get; private set; }

    #region IDamageable Implementation

    /// <inheritdoc/>
    public float CurrentHealth => HealthComponent?.CurrentHealth ?? 0;

    /// <inheritdoc/>
    public float MaxHealth => HealthComponent?.MaxHealth ?? 0;

    /// <inheritdoc/>
    public bool IsAlive => HealthComponent?.IsAlive ?? false;

    /// <inheritdoc/>
    public virtual void TakeDamage(float amount)
    {
        HealthComponent?.TakeDamage(amount);
    }

    /// <inheritdoc/>
    public virtual void Heal(float amount)
    {
        HealthComponent?.Heal(amount);
    }

    /// <inheritdoc/>
    public virtual void OnDeath()
    {
        // Override in derived classes to handle death
    }

    #endregion

    /// <summary>
    /// Signal emitted when the character takes damage.
    /// </summary>
    [Signal]
    public delegate void DamagedEventHandler(float amount, float currentHealth);

    /// <summary>
    /// Signal emitted when the character dies.
    /// </summary>
    [Signal]
    public delegate void DiedEventHandler();

    /// <summary>
    /// Signal emitted when the character is healed.
    /// </summary>
    [Signal]
    public delegate void HealedEventHandler(float amount, float currentHealth);

    public override void _Ready()
    {
        InitializeHealthComponent();
    }

    /// <summary>
    /// Initializes the health component, either from scene tree or creates a new one.
    /// </summary>
    protected virtual void InitializeHealthComponent()
    {
        // Try to find existing HealthComponent in children
        HealthComponent = GetNodeOrNull<HealthComponent>("HealthComponent");

        if (HealthComponent == null)
        {
            // Create a new health component
            HealthComponent = new HealthComponent();
            AddChild(HealthComponent);
        }

        // Connect signals
        HealthComponent.Damaged += OnHealthDamaged;
        HealthComponent.Healed += OnHealthHealed;
        HealthComponent.Died += OnHealthDied;
    }

    /// <summary>
    /// Handles the Damaged signal from HealthComponent.
    /// </summary>
    protected virtual void OnHealthDamaged(float amount, float currentHealth)
    {
        EmitSignal(SignalName.Damaged, amount, currentHealth);
    }

    /// <summary>
    /// Handles the Healed signal from HealthComponent.
    /// </summary>
    protected virtual void OnHealthHealed(float amount, float currentHealth)
    {
        EmitSignal(SignalName.Healed, amount, currentHealth);
    }

    /// <summary>
    /// Handles the Died signal from HealthComponent.
    /// </summary>
    protected virtual void OnHealthDied()
    {
        OnDeath();
        EmitSignal(SignalName.Died);
    }

    /// <summary>
    /// Applies movement based on the input direction.
    /// </summary>
    /// <param name="direction">Normalized direction vector.</param>
    /// <param name="delta">Frame delta time.</param>
    protected virtual void ApplyMovement(Vector2 direction, float delta)
    {
        if (direction != Vector2.Zero)
        {
            // Apply acceleration towards the input direction
            Velocity = Velocity.MoveToward(direction * MaxSpeed, Acceleration * delta);
        }
        else
        {
            // Apply friction to slow down
            Velocity = Velocity.MoveToward(Vector2.Zero, Friction * delta);
        }

        MoveAndSlide();
    }

    /// <summary>
    /// Called when the character collides with another body.
    /// Override to handle collision logic.
    /// </summary>
    /// <param name="collision">The collision information.</param>
    protected virtual void HandleCollision(KinematicCollision2D collision)
    {
        // Override in derived classes to handle collisions
    }
}
