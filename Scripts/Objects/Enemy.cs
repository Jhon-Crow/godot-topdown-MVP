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
    /// Color when at full health.
    /// </summary>
    [Export]
    public Color FullHealthColor { get; set; } = new Color(0.9f, 0.2f, 0.2f, 1.0f);

    /// <summary>
    /// Color when at low health (interpolates based on health percentage).
    /// </summary>
    [Export]
    public Color LowHealthColor { get; set; } = new Color(0.3f, 0.1f, 0.1f, 1.0f);

    /// <summary>
    /// Color to flash when hit.
    /// </summary>
    [Export]
    public Color HitFlashColor { get; set; } = new Color(1.0f, 1.0f, 1.0f, 1.0f);

    /// <summary>
    /// Duration of hit flash effect in seconds.
    /// </summary>
    [Export]
    public float HitFlashDuration { get; set; } = 0.1f;

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
        if (!IsAlive)
        {
            return;
        }

        EmitSignal(SignalName.Hit);

        if (_healthComponent != null)
        {
            // Show hit flash effect
            ShowHitFlash();
            _healthComponent.TakeDamage(amount);
        }
        else
        {
            // Fallback behavior if no health component
            _isHit = true;
            HandleHitEffect();
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
            AddChild(_healthComponent);
        }

        // Configure random health (2-4 HP)
        _healthComponent.UseRandomHealth = true;
        _healthComponent.MinRandomHealth = 2;
        _healthComponent.MaxRandomHealth = 4;
        _healthComponent.InitializeHealth();

        GD.Print($"[Enemy] {Name}: Spawned with health {_healthComponent.CurrentHealth}/{_healthComponent.MaxHealth}");

        // Connect signals
        _healthComponent.Died += OnHealthDied;
        _healthComponent.HealthChanged += OnHealthChanged;

        // Update visual color based on initial health
        UpdateHealthVisual();
    }

    /// <summary>
    /// Called when health changes - updates visual feedback.
    /// </summary>
    private void OnHealthChanged(float currentHealth, float maxHealth)
    {
        GD.Print($"[Enemy] {Name}: Health changed to {currentHealth}/{maxHealth} ({_healthComponent?.HealthPercent * 100:F0}%)");
        UpdateHealthVisual();
    }

    /// <summary>
    /// Updates the sprite color based on current health percentage.
    /// </summary>
    private void UpdateHealthVisual()
    {
        if (_sprite == null || _healthComponent == null)
        {
            return;
        }

        // Interpolate color based on health percentage
        float healthPercent = _healthComponent.HealthPercent;
        _sprite.Modulate = FullHealthColor.Lerp(LowHealthColor, 1.0f - healthPercent);
    }

    /// <summary>
    /// Called when the health component signals death.
    /// </summary>
    private void OnHealthDied()
    {
        GD.Print($"[Enemy] {Name}: Died!");
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
        if (!IsAlive)
        {
            return;
        }

        EmitSignal(SignalName.Hit);

        // Apply 1 damage (for hit-based system)
        if (_healthComponent != null && _healthComponent.IsAlive)
        {
            GD.Print($"[Enemy] {Name}: Hit! Taking 1 damage. Current health: {_healthComponent.CurrentHealth}");
            // Show hit flash effect
            ShowHitFlash();

            // Determine if this hit will be lethal before applying damage
            bool willBeFatal = _healthComponent.CurrentHealth <= 1.0f;

            // Play appropriate hit sound
            if (willBeFatal)
            {
                PlayHitLethalSound();
            }
            else
            {
                PlayHitNonLethalSound();
            }

            _healthComponent.TakeDamage(1.0f);
        }
        else
        {
            // Handle without health component (legacy behavior)
            _isHit = true;
            HandleHitEffect();
        }
    }

    /// <summary>
    /// Plays the lethal hit sound when enemy dies.
    /// </summary>
    private void PlayHitLethalSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_hit_lethal"))
        {
            audioManager.Call("play_hit_lethal", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the non-lethal hit sound when enemy is damaged but survives.
    /// </summary>
    private void PlayHitNonLethalSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_hit_non_lethal"))
        {
            audioManager.Call("play_hit_non_lethal", GlobalPosition);
        }
    }

    /// <summary>
    /// Shows a brief flash effect when hit.
    /// </summary>
    private async void ShowHitFlash()
    {
        if (_sprite == null)
        {
            return;
        }

        Color previousColor = _sprite.Modulate;
        _sprite.Modulate = HitFlashColor;

        await ToSignal(GetTree().CreateTimer(HitFlashDuration), "timeout");

        // Restore color based on current health (if still alive)
        if (_healthComponent != null && _healthComponent.IsAlive)
        {
            UpdateHealthVisual();
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

        // Reset health (will re-randomize if UseRandomHealth is true)
        _healthComponent?.ResetToMax();

        // Update visual to reflect new health
        UpdateHealthVisual();
    }
}
