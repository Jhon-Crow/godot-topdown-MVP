using Godot;

namespace GodotTopDownTemplate.Weapons;

/// <summary>
/// Creates and manages glow effects for laser sights.
///
/// Provides three visual components:
/// 1. Multi-layered volumetric glow aura — multiple Line2D nodes with additive
///    blending at progressively wider widths and lower opacities, creating a
///    smooth radial falloff that looks like realistic laser scatter (Issue #654).
/// 2. Endpoint glow — a PointLight2D with pixel-perfect circular texture at the
///    laser hit point (Issue #652).
/// 3. Dust particle animation — a GpuParticles2D with box emission stretched along
///    the beam, simulating the laser being visible through atmospheric dust
///    (Issue #654).
///
/// All effects match the laser's color and use a "fake glow" approach compatible
/// with the gl_compatibility renderer, since WorldEnvironment glow is not
/// available in that rendering mode.
///
/// Usage:
///   _laserGlow = new LaserGlowEffect();
///   _laserGlow.Create(this, laserColor);
///   // In _Process: _laserGlow.Update(Vector2.Zero, endPoint);
///   // Cleanup:     _laserGlow.Cleanup();
/// </summary>
public class LaserGlowEffect
{
    // =========================================================================
    // Glow layer configuration
    // =========================================================================

    /// <summary>
    /// Definition for one glow layer (width in pixels, alpha opacity).
    /// Layers are stacked with additive blending to produce volumetric falloff.
    /// </summary>
    private struct GlowLayerDef
    {
        public float Width;
        public float Alpha;
        public int ZIndex;

        public GlowLayerDef(float width, float alpha, int zIndex)
        {
            Width = width;
            Alpha = alpha;
            ZIndex = zIndex;
        }
    }

    /// <summary>
    /// Glow layers from innermost (bright, narrow) to outermost (dim, wide).
    /// The additive blending causes overlapping layers to build up brightness
    /// in the center while maintaining a smooth gradient toward the edges.
    /// </summary>
    private static readonly GlowLayerDef[] GlowLayers = new[]
    {
        new GlowLayerDef(4.0f, 0.6f, -1),   // Core boost — bright narrow halo
        new GlowLayerDef(12.0f, 0.25f, -2),  // Inner glow — close aura
        new GlowLayerDef(24.0f, 0.12f, -3),  // Mid glow — extended scatter
        new GlowLayerDef(40.0f, 0.05f, -4),  // Outer glow — wide atmospheric haze
    };

    // =========================================================================
    // Endpoint glow configuration
    // =========================================================================

    /// <summary>
    /// Energy of the endpoint PointLight2D.
    /// Matches the scatter light energy used in flashlight_effect.gd (0.4).
    /// </summary>
    private const float EndpointGlowEnergy = 0.4f;

    /// <summary>
    /// Texture scale of the endpoint PointLight2D. Small scale for a tight dot,
    /// similar to flashlight scatter but smaller since laser dot is subtler.
    /// </summary>
    private const float EndpointGlowTextureScale = 0.3f;

    /// <summary>
    /// Size of the circular glow texture in pixels.
    /// Matches flashlight_effect.gd scatter light texture (512x512).
    /// </summary>
    private const int GlowTextureSize = 512;

    // =========================================================================
    // Dust particle configuration
    // =========================================================================

    /// <summary>
    /// Number of dust mote particles along the beam.
    /// </summary>
    private const int DustParticleAmount = 24;

    /// <summary>
    /// Lifetime of each dust particle in seconds.
    /// </summary>
    private const float DustParticleLifetime = 1.0f;

    /// <summary>
    /// Size of the dust mote texture in pixels (small soft circle).
    /// </summary>
    private const int DustTextureSize = 16;

    /// <summary>
    /// Vertical half-extent of the dust emission box (how far from beam center
    /// particles can spawn, in pixels).
    /// </summary>
    private const float DustEmissionHalfHeight = 3.0f;

    // =========================================================================
    // Node references
    // =========================================================================

    /// <summary>
    /// The multi-layered glow Line2D nodes (one per layer).
    /// </summary>
    private Line2D?[]? _glowLines;

    /// <summary>
    /// The PointLight2D at the laser endpoint for residual glow effect.
    /// </summary>
    private PointLight2D? _endpointGlow;

    /// <summary>
    /// Dust particle emitter along the beam.
    /// </summary>
    private GpuParticles2D? _dustParticles;

    /// <summary>
    /// The ParticleProcessMaterial for the dust emitter (cached for updates).
    /// </summary>
    private ParticleProcessMaterial? _dustMaterial;

    /// <summary>
    /// The parent node that owns this glow effect.
    /// </summary>
    private Node2D? _parent;

    /// <summary>
    /// Creates the glow effect nodes and adds them as children of the parent.
    /// Call this right after CreateLaserSight() in each weapon.
    /// </summary>
    /// <param name="parent">The weapon node to attach glow nodes to.</param>
    /// <param name="laserColor">The color of the laser (glow will match).</param>
    public void Create(Node2D parent, Color laserColor)
    {
        _parent = parent;

        // Shared additive blending material for all glow layers
        var additiveMaterial = new CanvasItemMaterial();
        additiveMaterial.BlendMode = CanvasItemMaterial.BlendModeEnum.Add;

        // Shared width curve for soft falloff at beam start/end
        var widthCurve = new Curve();
        widthCurve.AddPoint(new Vector2(0.0f, 0.0f)); // Start thin
        widthCurve.AddPoint(new Vector2(0.1f, 1.0f));  // Reach full width quickly
        widthCurve.AddPoint(new Vector2(0.9f, 1.0f));  // Stay full width
        widthCurve.AddPoint(new Vector2(1.0f, 0.0f));  // End thin

        // Create multi-layered glow lines
        _glowLines = new Line2D[GlowLayers.Length];
        for (int i = 0; i < GlowLayers.Length; i++)
        {
            var layer = GlowLayers[i];
            var line = new Line2D
            {
                Name = $"LaserGlow_{i}",
                Width = layer.Width,
                DefaultColor = new Color(laserColor.R, laserColor.G, laserColor.B, layer.Alpha),
                BeginCapMode = Line2D.LineCapMode.Round,
                EndCapMode = Line2D.LineCapMode.Round,
                ZIndex = layer.ZIndex,
                WidthCurve = widthCurve,
                Material = additiveMaterial
            };
            line.AddPoint(Vector2.Zero);
            line.AddPoint(Vector2.Right * 500.0f);
            parent.AddChild(line);
            _glowLines[i] = line;
        }

        // Create endpoint glow (PointLight2D with circular radial gradient)
        // Uses a pixel-perfect circular texture to avoid the square artifact
        // that GradientTexture2D produces with radial fill.
        _endpointGlow = new PointLight2D
        {
            Name = "LaserEndpointGlow",
            Color = new Color(laserColor.R, laserColor.G, laserColor.B, 1.0f),
            Energy = EndpointGlowEnergy,
            ShadowEnabled = false,
            TextureScale = EndpointGlowTextureScale,
            Texture = CreateCircularGlowTexture(),
            Visible = true
        };
        parent.AddChild(_endpointGlow);

        // Create dust particle emitter along the beam
        CreateDustParticles(parent, laserColor);
    }

    /// <summary>
    /// Updates the glow effect positions to match the current laser sight.
    /// Call this from UpdateLaserSight() in each weapon after updating the main laser.
    /// </summary>
    /// <param name="startPoint">Start point of the laser (local coordinates, usually Vector2.Zero).</param>
    /// <param name="endPoint">End point of the laser (local coordinates, from raycast).</param>
    public void Update(Vector2 startPoint, Vector2 endPoint)
    {
        // Sync all glow layers with main laser
        if (_glowLines != null)
        {
            foreach (var line in _glowLines)
            {
                if (line != null)
                {
                    line.SetPointPosition(0, startPoint);
                    line.SetPointPosition(1, endPoint);
                }
            }
        }

        // Move endpoint glow to the laser hit point
        if (_endpointGlow != null)
        {
            _endpointGlow.Position = endPoint;
        }

        // Update dust particle emitter position, rotation, and extent
        UpdateDustParticles(startPoint, endPoint);
    }

    /// <summary>
    /// Sets visibility of the glow effect.
    /// Call this when the laser sight visibility changes.
    /// </summary>
    /// <param name="visible">Whether the glow should be visible.</param>
    public void SetVisible(bool visible)
    {
        if (_glowLines != null)
        {
            foreach (var line in _glowLines)
            {
                if (line != null)
                {
                    line.Visible = visible;
                }
            }
        }

        if (_endpointGlow != null)
        {
            _endpointGlow.Visible = visible;
        }

        if (_dustParticles != null)
        {
            _dustParticles.Visible = visible;
            _dustParticles.Emitting = visible;
        }
    }

    /// <summary>
    /// Removes and frees the glow effect nodes.
    /// Call this when the weapon is being destroyed or laser sight is removed.
    /// </summary>
    public void Cleanup()
    {
        if (_glowLines != null)
        {
            foreach (var line in _glowLines)
            {
                if (line != null && GodotObject.IsInstanceValid(line))
                {
                    line.QueueFree();
                }
            }
            _glowLines = null;
        }

        if (_endpointGlow != null && GodotObject.IsInstanceValid(_endpointGlow))
        {
            _endpointGlow.QueueFree();
            _endpointGlow = null;
        }

        if (_dustParticles != null && GodotObject.IsInstanceValid(_dustParticles))
        {
            _dustParticles.QueueFree();
            _dustParticles = null;
        }

        _dustMaterial = null;
        _parent = null;
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /// <summary>
    /// Creates the dust particle emitter (GpuParticles2D) that spawns small
    /// glowing motes along the laser beam, simulating dust catching the light.
    /// The emission box is stretched along the beam direction and updated each
    /// frame in <see cref="UpdateDustParticles"/>.
    /// </summary>
    private void CreateDustParticles(Node2D parent, Color laserColor)
    {
        // Build a color ramp: fade in → full brightness → fade out
        var colorRamp = new Gradient();
        colorRamp.SetColor(0, new Color(1.0f, 1.0f, 1.0f, 0.0f)); // start transparent
        colorRamp.AddPoint(0.15f, new Color(1.0f, 1.0f, 1.0f, 0.8f)); // fade in
        colorRamp.AddPoint(0.5f, new Color(1.0f, 1.0f, 1.0f, 1.0f));  // full brightness
        colorRamp.AddPoint(0.85f, new Color(1.0f, 1.0f, 1.0f, 0.8f)); // begin fade
        colorRamp.SetColor(1, new Color(1.0f, 1.0f, 1.0f, 0.0f)); // end transparent

        // Particle process material
        _dustMaterial = new ParticleProcessMaterial
        {
            EmissionShape = ParticleProcessMaterial.EmissionShapeEnum.Box,
            EmissionBoxExtents = new Vector3(100.0f, DustEmissionHalfHeight, 0.0f),
            Direction = new Vector3(0.0f, -1.0f, 0.0f),
            Spread = 180.0f,
            InitialVelocityMin = 3.0f,
            InitialVelocityMax = 10.0f,
            Gravity = new Vector3(0.0f, 0.0f, 0.0f),
            ScaleMin = 0.5f,
            ScaleMax = 1.5f,
            ColorRamp = new GradientTexture1D { Gradient = colorRamp },
            LifetimeRandomness = 0.3f,
        };

        // Additive blending material for particles
        var particleMaterial = new CanvasItemMaterial();
        particleMaterial.BlendMode = CanvasItemMaterial.BlendModeEnum.Add;

        _dustParticles = new GpuParticles2D
        {
            Name = "LaserDustParticles",
            ProcessMaterial = _dustMaterial,
            Amount = DustParticleAmount,
            Lifetime = DustParticleLifetime,
            Explosiveness = 0.0f,
            Randomness = 0.5f,
            Emitting = true,
            Texture = CreateDustTexture(laserColor),
            Material = particleMaterial,
            ZIndex = -1,
            Visible = true
        };

        parent.AddChild(_dustParticles);
    }

    /// <summary>
    /// Updates the dust particle emitter to follow the laser beam.
    /// Positions at beam midpoint, rotates to beam angle, and stretches
    /// the emission box to cover the beam length.
    /// </summary>
    private void UpdateDustParticles(Vector2 startPoint, Vector2 endPoint)
    {
        if (_dustParticles == null || _dustMaterial == null)
            return;

        var beamVector = endPoint - startPoint;
        var beamLength = beamVector.Length();

        if (beamLength < 1.0f)
        {
            _dustParticles.Visible = false;
            return;
        }

        _dustParticles.Visible = true;
        _dustParticles.Position = (startPoint + endPoint) / 2.0f;
        _dustParticles.Rotation = beamVector.Angle();
        _dustMaterial.EmissionBoxExtents = new Vector3(beamLength / 2.0f, DustEmissionHalfHeight, 0.0f);
    }

    /// <summary>
    /// Creates a small soft circular texture for dust mote particles.
    /// The texture is a white circle with smooth alpha falloff, tinted
    /// by the laser color.
    /// </summary>
    private static ImageTexture CreateDustTexture(Color laserColor)
    {
        var image = Image.CreateEmpty(DustTextureSize, DustTextureSize, false, Image.Format.Rgba8);
        float center = DustTextureSize / 2.0f;
        float maxRadius = center;

        for (int y = 0; y < DustTextureSize; y++)
        {
            for (int x = 0; x < DustTextureSize; x++)
            {
                float dx = x - center;
                float dy = y - center;
                float distance = Mathf.Sqrt(dx * dx + dy * dy);
                float normalizedDist = distance / maxRadius;

                // Soft circular falloff
                float alpha;
                if (normalizedDist <= 0.3f)
                {
                    alpha = 1.0f; // Bright core
                }
                else if (normalizedDist <= 0.8f)
                {
                    alpha = Mathf.Lerp(1.0f, 0.0f, (normalizedDist - 0.3f) / 0.5f);
                }
                else
                {
                    alpha = 0.0f;
                }

                image.SetPixel(x, y, new Color(laserColor.R, laserColor.G, laserColor.B, alpha));
            }
        }

        return ImageTexture.CreateFromImage(image);
    }

    /// <summary>
    /// Creates a pixel-perfect circular glow texture for the endpoint PointLight2D.
    /// Unlike GradientTexture2D (which produces a square artifact), this generates
    /// each pixel based on its Euclidean distance from the center, guaranteeing
    /// a perfectly round glow. Follows the same gradient pattern as the flashlight
    /// scatter light in flashlight_effect.gd (Issue #644).
    /// </summary>
    /// <returns>An ImageTexture with a circular radial gradient.</returns>
    private static ImageTexture CreateCircularGlowTexture()
    {
        var image = Image.CreateEmpty(GlowTextureSize, GlowTextureSize, false, Image.Format.Rgba8);
        float center = GlowTextureSize / 2.0f;
        float maxRadius = center;

        for (int y = 0; y < GlowTextureSize; y++)
        {
            for (int x = 0; x < GlowTextureSize; x++)
            {
                float dx = x - center;
                float dy = y - center;
                float distance = Mathf.Sqrt(dx * dx + dy * dy);
                float normalizedDist = distance / maxRadius;

                // Compute brightness based on distance from center
                // Matches flashlight_effect.gd gradient pattern:
                // Bright core, smooth falloff, zero by 55% radius
                float brightness;
                if (normalizedDist <= 0.1f)
                {
                    // Bright center core
                    brightness = Mathf.Lerp(1.0f, 0.8f, normalizedDist / 0.1f);
                }
                else if (normalizedDist <= 0.25f)
                {
                    brightness = Mathf.Lerp(0.8f, 0.4f, (normalizedDist - 0.1f) / 0.15f);
                }
                else if (normalizedDist <= 0.4f)
                {
                    brightness = Mathf.Lerp(0.4f, 0.1f, (normalizedDist - 0.25f) / 0.15f);
                }
                else if (normalizedDist <= 0.55f)
                {
                    // Fade to zero
                    brightness = Mathf.Lerp(0.1f, 0.0f, (normalizedDist - 0.4f) / 0.15f);
                }
                else
                {
                    // Beyond 55% radius — fully transparent
                    brightness = 0.0f;
                }

                image.SetPixel(x, y, new Color(brightness, brightness, brightness, 1.0f));
            }
        }

        var texture = ImageTexture.CreateFromImage(image);
        return texture;
    }
}
