using Godot;
using GodotTopDownTemplate.AbstractClasses;

namespace GodotTopDownTemplate.Weapons;

/// <summary>
/// Mini UZI submachine gun - high fire rate automatic weapon with increased spread.
/// Features:
/// - High fire rate (15 shots/sec)
/// - 9mm bullets with 0.5 damage
/// - High spread increase during sustained fire
/// - Ricochets only at angles of 20 degrees or less
/// - Does not penetrate walls
/// - High screen shake
/// - No scope/laser sight
/// - 32 rounds magazine
/// - Reload similar to assault rifle
/// </summary>
public partial class MiniUzi : BaseWeapon
{
    /// <summary>
    /// Reference to the Sprite2D node for the weapon visual.
    /// </summary>
    private Sprite2D? _weaponSprite;

    /// <summary>
    /// Current aim direction based on mouse position.
    /// </summary>
    private Vector2 _aimDirection = Vector2.Right;

    /// <summary>
    /// Current aim angle in radians. Used for sensitivity-based aiming
    /// where the aim interpolates smoothly toward the target angle.
    /// </summary>
    private float _currentAimAngle = 0.0f;

    /// <summary>
    /// Whether the aim angle has been initialized.
    /// </summary>
    private bool _aimAngleInitialized = false;

    /// <summary>
    /// Current recoil offset angle in radians.
    /// Mini UZI has higher recoil than assault rifle.
    /// </summary>
    private float _recoilOffset = 0.0f;

    /// <summary>
    /// Time since the last shot was fired, used for recoil recovery.
    /// </summary>
    private float _timeSinceLastShot = 0.0f;

    /// <summary>
    /// Time in seconds before recoil starts recovering.
    /// Shorter than assault rifle for faster spray patterns.
    /// </summary>
    private const float RecoilRecoveryDelay = 0.08f;

    /// <summary>
    /// Speed at which recoil recovers (radians per second).
    /// </summary>
    private const float RecoilRecoverySpeed = 6.0f;

    /// <summary>
    /// Maximum recoil offset in radians (about 8 degrees - higher than assault rifle).
    /// </summary>
    private const float MaxRecoilOffset = 0.14f;

    /// <summary>
    /// Tracks consecutive shots for spread calculation.
    /// </summary>
    private int _shotCount = 0;

    /// <summary>
    /// Time since last shot for spread reset.
    /// </summary>
    private float _spreadResetTimer = 0.0f;

    /// <summary>
    /// Number of shots before spread starts increasing.
    /// </summary>
    private const int SpreadThreshold = 0;

    /// <summary>
    /// Time in seconds for spread to reset after stopping fire.
    /// </summary>
    private const float SpreadResetTime = 0.3f;

    /// <summary>
    /// Number of shots to reach maximum spread (user requirement: 10 bullets).
    /// </summary>
    private const int ShotsToMaxSpread = 10;

    /// <summary>
    /// Maximum total spread in degrees (user requirement: 60 degrees).
    /// </summary>
    private const float MaxSpread = 60.0f;

    public override void _Ready()
    {
        base._Ready();

        // Get the weapon sprite for visual representation
        _weaponSprite = GetNodeOrNull<Sprite2D>("MiniUziSprite");

        if (_weaponSprite != null)
        {
            var texture = _weaponSprite.Texture;
            GD.Print($"[MiniUzi] MiniUziSprite found: visible={_weaponSprite.Visible}, z_index={_weaponSprite.ZIndex}, texture={(texture != null ? "loaded" : "NULL")}");
        }
        else
        {
            GD.Print("[MiniUzi] No MiniUziSprite node (visual model not yet added)");
        }
    }

    public override void _Process(double delta)
    {
        base._Process(delta);

        // Update time since last shot for recoil recovery
        _timeSinceLastShot += (float)delta;

        // Recover recoil after delay
        if (_timeSinceLastShot >= RecoilRecoveryDelay && _recoilOffset != 0)
        {
            float recoveryAmount = RecoilRecoverySpeed * (float)delta;
            _recoilOffset = Mathf.MoveToward(_recoilOffset, 0, recoveryAmount);
        }

        // Update spread reset timer
        _spreadResetTimer += (float)delta;
        if (_spreadResetTimer >= SpreadResetTime)
        {
            _shotCount = 0;
        }

        // Update aim direction and weapon sprite rotation
        UpdateAimDirection();
    }

    /// <summary>
    /// Updates the aim direction based on mouse position.
    /// Mini UZI uses sensitivity-based aiming for faster rotation than assault rifle.
    /// </summary>
    private void UpdateAimDirection()
    {
        // Get direction to mouse
        Vector2 mousePos = GetGlobalMousePosition();
        Vector2 toMouse = mousePos - GlobalPosition;

        // Calculate target angle from player to mouse
        float targetAngle = toMouse.Angle();

        // Initialize aim angle on first frame
        if (!_aimAngleInitialized)
        {
            _currentAimAngle = targetAngle;
            _aimAngleInitialized = true;
        }

        Vector2 direction;

        // Apply sensitivity "leash" effect when sensitivity is set
        if (WeaponData != null && WeaponData.Sensitivity > 0)
        {
            float angleDiff = Mathf.Wrap(targetAngle - _currentAimAngle, -Mathf.Pi, Mathf.Pi);
            float rotationSpeed = WeaponData.Sensitivity * 10.0f;
            float delta = (float)GetProcessDeltaTime();
            float maxRotation = rotationSpeed * delta;
            float actualRotation = Mathf.Clamp(angleDiff, -maxRotation, maxRotation);
            _currentAimAngle += actualRotation;
            direction = new Vector2(Mathf.Cos(_currentAimAngle), Mathf.Sin(_currentAimAngle));
        }
        else
        {
            // Automatic mode: direct aim at cursor (instant response)
            if (toMouse.LengthSquared() > 0.001f)
            {
                direction = toMouse.Normalized();
                _currentAimAngle = targetAngle;
            }
            else
            {
                direction = _aimDirection;
            }
        }

        // Store the aim direction for shooting
        _aimDirection = direction;

        // Update weapon sprite rotation to match aim direction
        UpdateWeaponSpriteRotation(_aimDirection);
    }

    /// <summary>
    /// Updates the weapon sprite rotation to match the aim direction.
    /// Also handles vertical flipping when aiming left.
    /// </summary>
    private void UpdateWeaponSpriteRotation(Vector2 direction)
    {
        if (_weaponSprite == null)
        {
            return;
        }

        float angle = direction.Angle();
        _weaponSprite.Rotation = angle;

        // Flip the sprite vertically when aiming left
        bool aimingLeft = Mathf.Abs(angle) > Mathf.Pi / 2;
        _weaponSprite.FlipV = aimingLeft;
    }

    /// <summary>
    /// Fires the Mini UZI in automatic mode.
    /// </summary>
    /// <param name="direction">Direction to fire (uses aim direction).</param>
    /// <returns>True if the weapon fired successfully.</returns>
    public override bool Fire(Vector2 direction)
    {
        // Check for empty magazine - play click sound
        if (CurrentAmmo <= 0)
        {
            PlayEmptyClickSound();
            return false;
        }

        // Check if we can fire at all
        if (!CanFire || WeaponData == null || BulletScene == null)
        {
            return false;
        }

        // Apply spread to aim direction
        Vector2 spreadDirection = ApplySpread(_aimDirection);
        bool result = base.Fire(spreadDirection);

        if (result)
        {
            // Play UZI shot sound (uses M16 sounds as per requirement - same loudness as assault rifle)
            PlayUziShotSound();
            // Emit gunshot sound for in-game sound propagation (alerts enemies)
            EmitGunshotSound();
            // Play shell casing sound with delay
            PlayShellCasingDelayed();
            // Trigger screen shake
            TriggerScreenShake(spreadDirection);
            // Update shot count and reset timer
            _shotCount++;
            _spreadResetTimer = 0.0f;
        }

        return result;
    }

    /// <summary>
    /// Applies recoil offset to the shooting direction and adds new recoil.
    /// Mini UZI has progressive spread that reaches max (60°) after 10 bullets.
    /// </summary>
    private Vector2 ApplySpread(Vector2 direction)
    {
        // Apply the current recoil offset to the direction
        Vector2 result = direction.Rotated(_recoilOffset);

        // Add recoil for the next shot
        if (WeaponData != null)
        {
            // Calculate current spread based on shot count
            // Progressive spread: starts at base SpreadAngle and increases to MaxSpread over ShotsToMaxSpread bullets
            float baseSpread = WeaponData.SpreadAngle;
            float spreadRange = MaxSpread - baseSpread;

            // Calculate spread ratio (0.0 at shot 0, 1.0 at shot ShotsToMaxSpread)
            float spreadRatio = Mathf.Clamp((float)_shotCount / ShotsToMaxSpread, 0.0f, 1.0f);
            float currentSpread = baseSpread + spreadRange * spreadRatio;

            // Convert spread angle from degrees to radians
            float spreadRadians = Mathf.DegToRad(currentSpread);

            // Generate random recoil direction with higher variation
            float recoilDirection = (float)GD.RandRange(-1.0, 1.0);
            float recoilAmount = spreadRadians * Mathf.Abs(recoilDirection);

            // Calculate max recoil offset based on current spread
            float maxRecoilOffset = Mathf.DegToRad(currentSpread * 0.5f);

            // Add to current recoil, clamped to current maximum
            _recoilOffset += recoilDirection * recoilAmount * 0.6f;
            _recoilOffset = Mathf.Clamp(_recoilOffset, -maxRecoilOffset, maxRecoilOffset);
        }

        // Reset time since last shot for recoil recovery
        _timeSinceLastShot = 0;

        return result;
    }

    /// <summary>
    /// Plays the empty gun click sound.
    /// </summary>
    private void PlayEmptyClickSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_empty_click"))
        {
            audioManager.Call("play_empty_click", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the UZI shot sound via AudioManager.
    /// Uses M16 sounds as per requirement (same loudness as assault rifle).
    /// </summary>
    private void PlayUziShotSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_m16_shot"))
        {
            audioManager.Call("play_m16_shot", GlobalPosition);
        }
    }

    /// <summary>
    /// Emits a gunshot sound to SoundPropagation system for in-game sound propagation.
    /// </summary>
    private void EmitGunshotSound()
    {
        var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
        if (soundPropagation != null && soundPropagation.HasMethod("emit_sound"))
        {
            float loudness = WeaponData?.Loudness ?? 1469.0f;
            soundPropagation.Call("emit_sound", 0, GlobalPosition, 0, this, loudness);
        }
    }

    /// <summary>
    /// Plays shell casing sound with a delay.
    /// </summary>
    private async void PlayShellCasingDelayed()
    {
        await ToSignal(GetTree().CreateTimer(0.1), "timeout");
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_shell_rifle"))
        {
            audioManager.Call("play_shell_rifle", GlobalPosition);
        }
    }

    /// <summary>
    /// Triggers screen shake based on shooting direction and current spread.
    /// Mini UZI has high screen shake with progressive intensity:
    /// - Shake intensity increases with consecutive shots (up to 4x at max spread)
    /// - This creates stronger recoil the longer you hold the trigger
    /// </summary>
    private void TriggerScreenShake(Vector2 shootDirection)
    {
        if (WeaponData == null || WeaponData.ScreenShakeIntensity <= 0)
        {
            return;
        }

        var screenShakeManager = GetNodeOrNull("/root/ScreenShakeManager");
        if (screenShakeManager == null || !screenShakeManager.HasMethod("add_shake"))
        {
            return;
        }

        // Calculate base shake intensity based on fire rate
        float fireRate = WeaponData.FireRate;
        float baseShakeIntensity;
        if (fireRate > 0)
        {
            baseShakeIntensity = WeaponData.ScreenShakeIntensity / fireRate * 10.0f;
        }
        else
        {
            baseShakeIntensity = WeaponData.ScreenShakeIntensity;
        }

        // Calculate spread ratio for progressive shake (matches progressive spread system)
        float spreadRatio = Mathf.Clamp((float)_shotCount / ShotsToMaxSpread, 0.0f, 1.0f);

        // Progressive shake intensity: increases from base to 4x as spread increases
        // At first shot (spreadRatio=0): 1.0x intensity
        // At max spread (spreadRatio=1): 4.0x intensity
        float shakeMultiplier = 1.0f + spreadRatio * 3.0f;
        float shakeIntensity = baseShakeIntensity * shakeMultiplier;

        // Calculate recovery time
        float minRecovery = WeaponData.ScreenShakeMinRecoveryTime;
        float maxRecovery = Mathf.Max(WeaponData.ScreenShakeMaxRecoveryTime, 0.05f);
        float recoveryTime = Mathf.Lerp(minRecovery, maxRecovery, spreadRatio);

        screenShakeManager.Call("add_shake", shootDirection, shakeIntensity, recoveryTime);
    }

    /// <summary>
    /// Fires the bullet in the chamber during reload sequence.
    /// </summary>
    public override bool FireChamberBullet(Vector2 direction)
    {
        Vector2 spreadDirection = ApplySpread(_aimDirection);
        bool result = base.FireChamberBullet(spreadDirection);

        if (result)
        {
            PlayUziShotSound();
            EmitGunshotSound();
            PlayShellCasingDelayed();
            TriggerScreenShake(spreadDirection);
            _shotCount++;
            _spreadResetTimer = 0.0f;
        }

        return result;
    }

    /// <summary>
    /// Gets the current aim direction.
    /// </summary>
    public Vector2 AimDirection => _aimDirection;
}
