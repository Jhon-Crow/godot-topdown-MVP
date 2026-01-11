using Godot;
using GodotTopDownTemplate.Components;
using GodotTopDownTemplate.Interfaces;

namespace GodotTopDownTemplate.Objects;

/// <summary>
/// Enemy/Target that can be damaged and reacts when hit.
/// Implements IDamageable interface for the damage system.
/// Can be destroyed or respawn after a delay.
/// </summary>
public partial class Enemy : Area2D, IDamageable
{
    /// <summary>
    /// Color to change to when hit.
    /// </summary>
    [Export]
    public Color HitColor { get; set; } = new Color(0.2f, 0.8f, 0.2f, 1.0f);

    /// <summary>
    /// Original color before being hit.
    /// </summary>
    [Export]
    public Color NormalColor { get; set; } = new Color(0.9f, 0.2f, 0.2f, 1.0f);

    /// <summary>
    /// Whether to destroy the target after being hit.
    /// </summary>
    [Export]
    public bool DestroyOnHit { get; set; } = false;

    /// <summary>
    /// Delay before respawning or destroying (in seconds).
    /// </summary>
    [Export]
    public float RespawnDelay { get; set; } = 2.0f;

    /// <summary>
    /// Health component for managing health.
    /// </summary>
    private HealthComponent? _healthComponent;

    /// <summary>
    /// Reference to the sprite for color changes.
    /// </summary>
    private Sprite2D? _sprite;

    /// <summary>
    /// Whether the target has been hit and is in hit state.
    /// </summary>
    private bool _isHit;

    #region IDamageable Implementation

    /// <inheritdoc/>
    public float CurrentHealth => _healthComponent?.CurrentHealth ?? 0;

    /// <inheritdoc/>
    public float MaxHealth => _healthComponent?.MaxHealth ?? 100;

    /// <inheritdoc/>
    public bool IsAlive => _healthComponent?.IsAlive ?? !_isHit;

    /// <inheritdoc/>
    public void TakeDamage(float amount)
    {
        if (_healthComponent != null)
        {
            _healthComponent.TakeDamage(amount);
        }
        else
        {
            // Fallback behavior if no health component
            OnHit();
        }
    }

    /// <inheritdoc/>
    public void Heal(float amount)
    {
        _healthComponent?.Heal(amount);
    }

    /// <inheritdoc/>
    public void OnDeath()
    {
        HandleDeath();
    }

    #endregion

    /// <summary>
    /// Signal emitted when the enemy is hit.
    /// </summary>
    [Signal]
    public delegate void HitEventHandler();

    /// <summary>
    /// Signal emitted when the enemy dies.
    /// </summary>
    [Signal]
    public delegate void DiedEventHandler();

    public override void _Ready()
    {
        // Get sprite reference
        _sprite = GetNodeOrNull<Sprite2D>("Sprite2D");

        // Initialize or create health component
        _healthComponent = GetNodeOrNull<HealthComponent>("HealthComponent");
        if (_healthComponent == null)
        {
            _healthComponent = new HealthComponent();
            _healthComponent.MaxHealth = 10.0f; // Single hit to destroy
            AddChild(_healthComponent);
        }

        _healthComponent.Died += OnHealthDied;

        // Ensure the sprite has the normal color
        if (_sprite != null)
        {
            _sprite.Modulate = NormalColor;
        }
    }

    /// <summary>
    /// Called when the health component signals death.
    /// </summary>
    private void OnHealthDied()
    {
        OnDeath();
    }

    /// <summary>
    /// Legacy hit method for backwards compatibility with bullet.gd.
    /// Called when hit by a bullet using the on_hit() method.
    /// </summary>
    public void on_hit()
    {
        OnHit();
    }

    /// <summary>
    /// Called when the enemy is hit.
    /// </summary>
    public void OnHit()
    {
        if (_isHit)
        {
            return;
        }

        _isHit = true;
        EmitSignal(SignalName.Hit);

        // Change color to show hit
        if (_sprite != null)
        {
            _sprite.Modulate = HitColor;
        }

        // Apply damage if using health component
        if (_healthComponent != null && _healthComponent.IsAlive)
        {
            _healthComponent.TakeDamage(10.0f);
        }
        else
        {
            // Handle without health component
            HandleHitEffect();
        }
    }

    /// <summary>
    /// Handles the visual/behavioral effect of being hit.
    /// </summary>
    private async void HandleHitEffect()
    {
        if (DestroyOnHit)
        {
            // Wait before destroying
            await ToSignal(GetTree().CreateTimer(RespawnDelay), "timeout");
            QueueFree();
        }
        else
        {
            // Wait before resetting
            await ToSignal(GetTree().CreateTimer(RespawnDelay), "timeout");
            Reset();
        }
    }

    /// <summary>
    /// Handles enemy death.
    /// </summary>
    private async void HandleDeath()
    {
        EmitSignal(SignalName.Died);

        if (DestroyOnHit)
        {
            await ToSignal(GetTree().CreateTimer(RespawnDelay), "timeout");
            QueueFree();
        }
        else
        {
            await ToSignal(GetTree().CreateTimer(RespawnDelay), "timeout");
            Reset();
        }
    }

    /// <summary>
    /// Resets the enemy to its initial state.
    /// </summary>
    private void Reset()
    {
        _isHit = false;
        if (_sprite != null)
        {
            _sprite.Modulate = NormalColor;
        }

        // Reset health
        _healthComponent?.ResetToMax();
    }
}
