using Godot;
using System;

namespace GodotTopDownTemplate.Effects;

/// <summary>
/// Visual teleportation effect for level transitions (Issue #721).
///
/// Creates a sci-fi style teleportation effect with:
/// - A bottom portal ring (concentric circles)
/// - A top portal ring (descends/ascends during animation)
/// - Particle effects (sparkles, light beams)
/// - A light column between the portals
///
/// Animation phases:
/// - DISAPPEAR: Top ring descends, player fades out (sinking into portal)
/// - APPEAR: Top ring ascends, player fades in (emerging from portal)
///
/// This C# version ensures the effect works in exported builds where
/// GDScript may not execute properly due to Godot 4.3 binary tokenization bug.
/// </summary>
public partial class TeleportEffect : Node2D
{
    /// <summary>
    /// Signal emitted when the animation finishes (either disappear or appear).
    /// </summary>
    [Signal]
    public delegate void AnimationFinishedEventHandler(string animationType);

    /// <summary>
    /// Signal emitted during disappear when player should be hidden.
    /// </summary>
    [Signal]
    public delegate void PlayerShouldHideEventHandler();

    /// <summary>
    /// Signal emitted during appear when player should be shown.
    /// </summary>
    [Signal]
    public delegate void PlayerShouldShowEventHandler();

    /// <summary>
    /// Animation phases.
    /// </summary>
    private enum AnimPhase { Idle, Disappear, Appear }

    /// <summary>
    /// Current animation phase.
    /// </summary>
    private AnimPhase _currentPhase = AnimPhase.Idle;

    /// <summary>
    /// Duration of the teleport animation in seconds.
    /// </summary>
    private const float AnimationDuration = 0.8f;

    /// <summary>
    /// Color for the portal rings (cyan/blue sci-fi style).
    /// </summary>
    private static readonly Color PortalColor = new(0.2f, 0.8f, 1.0f, 0.9f);

    /// <summary>
    /// Color for the light column.
    /// </summary>
    private static readonly Color LightColor = new(0.3f, 0.9f, 1.0f, 0.7f);

    /// <summary>
    /// Color for particles.
    /// </summary>
    private static readonly Color ParticleColor = new(0.5f, 0.95f, 1.0f, 0.8f);

    /// <summary>
    /// Radius of the portal rings.
    /// </summary>
    private const float PortalRadius = 40.0f;

    /// <summary>
    /// Height of the light column at maximum.
    /// </summary>
    private const float ColumnHeight = 80.0f;

    /// <summary>
    /// Ring thickness.
    /// </summary>
    private const float RingThickness = 3.0f;

    /// <summary>
    /// Number of concentric rings.
    /// </summary>
    private const int RingCount = 3;

    /// <summary>
    /// Animation progress (0.0 to 1.0).
    /// </summary>
    private float _progress = 0.0f;

    /// <summary>
    /// Bottom portal ring (stays at player feet).
    /// </summary>
    private Node2D? _bottomRing;

    /// <summary>
    /// Top portal ring (moves up/down during animation).
    /// </summary>
    private Node2D? _topRing;

    /// <summary>
    /// Light column between portals.
    /// </summary>
    private ColorRect? _lightColumn;

    /// <summary>
    /// Particle emitter for sparkles.
    /// </summary>
    private GpuParticles2D? _particles;

    /// <summary>
    /// Point light for glow effect.
    /// </summary>
    private PointLight2D? _pointLight;

    /// <summary>
    /// Reference to the target (usually player) for visibility control.
    /// </summary>
    private Node2D? _target;

    /// <summary>
    /// Initial player modulate value to restore.
    /// </summary>
    private Color _originalModulate = Colors.White;

    public override void _Ready()
    {
        ZIndex = 10;

        // Create visual components
        CreatePortalRings();
        CreateLightColumn();
        CreateParticles();
        CreatePointLight();

        // Start hidden
        SetEffectVisible(false);

        LogToFile("[TeleportEffect] C# TeleportEffect ready");
    }

    /// <summary>
    /// Set the target node whose visibility will be controlled during the effect.
    /// </summary>
    public void SetTarget(Node2D target)
    {
        _target = target;
        if (_target != null)
        {
            _originalModulate = _target.Modulate;
        }
    }

    /// <summary>
    /// Play the disappear animation (player sinks into portal).
    /// </summary>
    public void PlayDisappear()
    {
        if (_currentPhase != AnimPhase.Idle)
            return;

        _currentPhase = AnimPhase.Disappear;
        _progress = 0.0f;
        SetEffectVisible(true);

        LogToFile("[TeleportEffect] Playing disappear animation");
    }

    /// <summary>
    /// Play the appear animation (player emerges from portal).
    /// </summary>
    public void PlayAppear()
    {
        if (_currentPhase != AnimPhase.Idle)
            return;

        _currentPhase = AnimPhase.Appear;
        _progress = 0.0f;
        SetEffectVisible(true);

        // Start with target hidden for appear animation
        if (_target != null && IsInstanceValid(_target))
        {
            _target.Modulate = new Color(_originalModulate.R, _originalModulate.G, _originalModulate.B, 0.0f);
        }

        LogToFile("[TeleportEffect] Playing appear animation");
    }

    public override void _Process(double delta)
    {
        if (_currentPhase == AnimPhase.Idle)
            return;

        // Update animation progress
        _progress += (float)delta / AnimationDuration;
        _progress = Mathf.Clamp(_progress, 0.0f, 1.0f);

        // Update visual elements based on progress and phase
        UpdateAnimation();

        // Check if animation is complete
        if (_progress >= 1.0f)
        {
            CompleteAnimation();
        }
    }

    /// <summary>
    /// Update all visual elements based on current progress.
    /// </summary>
    private void UpdateAnimation()
    {
        float t = _progress;

        // Apply easing for smooth animation
        float easeT = EaseInOut(t);

        switch (_currentPhase)
        {
            case AnimPhase.Disappear:
                UpdateDisappearAnimation(easeT);
                break;
            case AnimPhase.Appear:
                UpdateAppearAnimation(easeT);
                break;
        }
    }

    /// <summary>
    /// Update the disappear animation state.
    /// </summary>
    private void UpdateDisappearAnimation(float t)
    {
        // Top ring descends from ColumnHeight to 0
        if (_topRing != null)
        {
            _topRing.Position = new Vector2(0, -ColumnHeight * (1.0f - t));
        }

        // Light column shrinks as top ring descends
        if (_lightColumn != null)
        {
            float columnHeight = ColumnHeight * (1.0f - t);
            _lightColumn.Size = new Vector2(_lightColumn.Size.X, columnHeight);
            _lightColumn.Position = new Vector2(_lightColumn.Position.X, -columnHeight);
            // Fade out as it shrinks
            _lightColumn.Modulate = new Color(1, 1, 1, (1.0f - t) * LightColor.A);
        }

        // Fade out target (player)
        if (_target != null && IsInstanceValid(_target))
        {
            float alpha = 1.0f - t;
            _target.Modulate = new Color(_originalModulate.R, _originalModulate.G, _originalModulate.B, alpha);

            // Emit signal when player should be fully hidden (at 50% progress)
            if (t >= 0.5f && t < 0.55f)
            {
                EmitSignal(SignalName.PlayerShouldHide);
            }
        }

        // Particle intensity decreases
        if (_particles != null)
        {
            _particles.AmountRatio = 1.0f - (t * 0.5f);
        }

        // Light intensity follows animation
        if (_pointLight != null)
        {
            _pointLight.Energy = 2.0f * (1.0f - t * 0.7f);
        }

        // Ring opacity pulses
        UpdateRingOpacity(1.0f - t * 0.3f);
    }

    /// <summary>
    /// Update the appear animation state.
    /// </summary>
    private void UpdateAppearAnimation(float t)
    {
        // Top ring ascends from 0 to ColumnHeight
        if (_topRing != null)
        {
            _topRing.Position = new Vector2(0, -ColumnHeight * t);
        }

        // Light column grows as top ring ascends
        if (_lightColumn != null)
        {
            float columnHeight = ColumnHeight * t;
            _lightColumn.Size = new Vector2(_lightColumn.Size.X, columnHeight);
            _lightColumn.Position = new Vector2(_lightColumn.Position.X, -columnHeight);
            // Fade in as it grows, then fade out at end
            float columnAlpha;
            if (t < 0.5f)
                columnAlpha = t * 2.0f;
            else
                columnAlpha = (1.0f - t) * 2.0f;
            _lightColumn.Modulate = new Color(1, 1, 1, columnAlpha * LightColor.A);
        }

        // Fade in target (player)
        if (_target != null && IsInstanceValid(_target))
        {
            float alpha = t;
            _target.Modulate = new Color(_originalModulate.R, _originalModulate.G, _originalModulate.B, alpha);

            // Emit signal when player should start showing (at 50% progress)
            if (t >= 0.5f && t < 0.55f)
            {
                EmitSignal(SignalName.PlayerShouldShow);
            }
        }

        // Particle intensity peaks in middle
        if (_particles != null)
        {
            float particleRatio;
            if (t < 0.5f)
                particleRatio = t * 2.0f;
            else
                particleRatio = (1.0f - t) * 2.0f;
            _particles.AmountRatio = particleRatio;
        }

        // Light intensity follows animation
        if (_pointLight != null)
        {
            float lightEnergy;
            if (t < 0.5f)
                lightEnergy = t * 4.0f;
            else
                lightEnergy = (1.0f - t) * 4.0f;
            _pointLight.Energy = lightEnergy;
        }

        // Ring opacity pulses
        float ringOpacity = 0.7f + 0.3f * Mathf.Sin(t * Mathf.Pi);
        UpdateRingOpacity(ringOpacity);
    }

    /// <summary>
    /// Update the opacity of portal rings.
    /// </summary>
    private void UpdateRingOpacity(float opacity)
    {
        if (_bottomRing != null)
        {
            _bottomRing.Modulate = new Color(1, 1, 1, opacity);
        }
        if (_topRing != null)
        {
            _topRing.Modulate = new Color(1, 1, 1, opacity);
        }
    }

    /// <summary>
    /// Complete the current animation.
    /// </summary>
    private void CompleteAnimation()
    {
        string finishedPhase = _currentPhase == AnimPhase.Disappear ? "disappear" : "appear";

        // Restore target visibility based on animation type
        if (_target != null && IsInstanceValid(_target))
        {
            if (_currentPhase == AnimPhase.Disappear)
            {
                _target.Modulate = new Color(_originalModulate.R, _originalModulate.G, _originalModulate.B, 0.0f);
            }
            else
            {
                _target.Modulate = _originalModulate;
            }
        }

        _currentPhase = AnimPhase.Idle;
        SetEffectVisible(false);

        LogToFile($"[TeleportEffect] Animation completed: {finishedPhase}");
        EmitSignal(SignalName.AnimationFinished, finishedPhase);
    }

    /// <summary>
    /// Create the portal ring nodes.
    /// </summary>
    private void CreatePortalRings()
    {
        // Bottom ring (at feet level)
        _bottomRing = CreateRingNode("BottomRing");
        _bottomRing.Position = Vector2.Zero;
        AddChild(_bottomRing);

        // Top ring (moves during animation)
        _topRing = CreateRingNode("TopRing");
        _topRing.Position = new Vector2(0, -ColumnHeight);
        AddChild(_topRing);
    }

    /// <summary>
    /// Create a single ring node with concentric circles.
    /// </summary>
    private Node2D CreateRingNode(string ringName)
    {
        var ringContainer = new Node2D();
        ringContainer.Name = ringName;

        // Create multiple concentric rings using Line2D
        for (int i = 0; i < RingCount; i++)
        {
            var ring = new Line2D();
            ring.Name = $"Ring{i}";
            ring.Width = RingThickness - i * 0.5f;
            ring.DefaultColor = new Color(PortalColor.R, PortalColor.G, PortalColor.B, 1.0f - (i * 0.2f));
            ring.JointMode = Line2D.LineJointMode.Round;
            ring.EndCapMode = Line2D.LineCapMode.Round;
            ring.BeginCapMode = Line2D.LineCapMode.Round;

            // Create circular points
            float radius = PortalRadius - (i * 8.0f);
            var points = new Vector2[33]; // 32 segments + 1 to close
            int segments = 32;
            for (int j = 0; j <= segments; j++)
            {
                float angle = ((float)j / segments) * Mathf.Tau;
                points[j] = new Vector2(
                    Mathf.Cos(angle) * radius,
                    Mathf.Sin(angle) * radius * 0.4f  // Ellipse for perspective
                );
            }
            ring.Points = points;

            ringContainer.AddChild(ring);
        }

        return ringContainer;
    }

    /// <summary>
    /// Create the light column between portals.
    /// </summary>
    private void CreateLightColumn()
    {
        _lightColumn = new ColorRect();
        _lightColumn.Name = "LightColumn";
        _lightColumn.Color = LightColor;
        _lightColumn.Size = new Vector2(PortalRadius * 1.2f, ColumnHeight);
        _lightColumn.Position = new Vector2(-PortalRadius * 0.6f, -ColumnHeight);

        // Add some transparency gradient effect via modulate
        _lightColumn.Modulate = new Color(1, 1, 1, 0.6f);

        AddChild(_lightColumn);
    }

    /// <summary>
    /// Create particle effects for sparkles.
    /// </summary>
    private void CreateParticles()
    {
        _particles = new GpuParticles2D();
        _particles.Name = "Particles";
        _particles.Emitting = true;
        _particles.Amount = 40;
        _particles.Lifetime = 1.0f;
        _particles.OneShot = false;
        _particles.Explosiveness = 0.1f;
        _particles.Randomness = 0.5f;

        // Create process material
        var material = new ParticleProcessMaterial();
        material.EmissionShape = ParticleProcessMaterial.EmissionShapeEnum.Sphere;
        material.EmissionSphereRadius = PortalRadius;
        material.Direction = new Vector3(0, -1, 0);
        material.Spread = 30.0f;
        material.InitialVelocityMin = 20.0f;
        material.InitialVelocityMax = 60.0f;
        material.Gravity = new Vector3(0, -20, 0);
        material.ScaleMin = 0.5f;
        material.ScaleMax = 1.5f;
        material.Color = ParticleColor;

        _particles.ProcessMaterial = material;

        // Create a simple texture (small circle)
        var texture = new GradientTexture2D();
        var gradient = new Gradient();
        gradient.Offsets = new float[] { 0.0f, 0.3f, 0.7f, 1.0f };
        gradient.Colors = new Color[]
        {
            ParticleColor,
            new Color(ParticleColor.R, ParticleColor.G, ParticleColor.B, 0.8f),
            new Color(ParticleColor.R, ParticleColor.G, ParticleColor.B, 0.4f),
            new Color(ParticleColor.R, ParticleColor.G, ParticleColor.B, 0.0f)
        };
        texture.Gradient = gradient;
        texture.Width = 16;
        texture.Height = 16;
        texture.Fill = GradientTexture2D.FillEnum.Radial;
        texture.FillFrom = new Vector2(0.5f, 0.5f);

        _particles.Texture = texture;

        AddChild(_particles);
    }

    /// <summary>
    /// Create a point light for the glow effect.
    /// </summary>
    private void CreatePointLight()
    {
        _pointLight = new PointLight2D();
        _pointLight.Name = "PointLight";
        _pointLight.Color = PortalColor;
        _pointLight.Energy = 2.0f;
        _pointLight.ShadowEnabled = false;

        // Create gradient texture for the light
        var texture = new GradientTexture2D();
        var gradient = new Gradient();
        gradient.Offsets = new float[] { 0.0f, 0.3f, 0.7f, 1.0f };
        gradient.Colors = new Color[]
        {
            new Color(1, 1, 1, 1),
            new Color(1, 1, 1, 0.6f),
            new Color(1, 1, 1, 0.2f),
            new Color(1, 1, 1, 0)
        };
        texture.Gradient = gradient;
        texture.Width = 256;
        texture.Height = 256;
        texture.Fill = GradientTexture2D.FillEnum.Radial;
        texture.FillFrom = new Vector2(0.5f, 0.5f);

        _pointLight.Texture = texture;
        _pointLight.TextureScale = 2.0f;

        AddChild(_pointLight);
    }

    /// <summary>
    /// Set the visibility of all effect components.
    /// </summary>
    private void SetEffectVisible(bool visibleState)
    {
        if (_bottomRing != null)
            _bottomRing.Visible = visibleState;
        if (_topRing != null)
            _topRing.Visible = visibleState;
        if (_lightColumn != null)
            _lightColumn.Visible = visibleState;
        if (_particles != null)
        {
            _particles.Visible = visibleState;
            _particles.Emitting = visibleState;
        }
        if (_pointLight != null)
            _pointLight.Visible = visibleState;
    }

    /// <summary>
    /// Easing function for smooth animation (ease in-out cubic).
    /// </summary>
    private static float EaseInOut(float t)
    {
        if (t < 0.5f)
        {
            return 4.0f * t * t * t;
        }
        else
        {
            float f = (2.0f * t) - 2.0f;
            return 0.5f * f * f * f + 1.0f;
        }
    }

    /// <summary>
    /// Check if the effect is currently playing.
    /// </summary>
    public bool IsPlaying()
    {
        return _currentPhase != AnimPhase.Idle;
    }

    /// <summary>
    /// Get the current animation phase as string.
    /// </summary>
    public string GetCurrentPhase()
    {
        return _currentPhase switch
        {
            AnimPhase.Idle => "idle",
            AnimPhase.Disappear => "disappear",
            AnimPhase.Appear => "appear",
            _ => "unknown"
        };
    }

    /// <summary>
    /// Log message to file logger if available.
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
