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
    // Diagnostic logging (disabled by default, enable for debugging)
    // =========================================================================

    /// <summary>
    /// Enable verbose diagnostic logging for glow effect creation and updates.
    /// Set to true in code or via reflection to debug glow visibility issues.
    /// </summary>
    private static bool _diagnosticLogging = false;

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
    /// Alpha values follow a steep Gaussian-like falloff so that the glow is
    /// concentrated near the beam core and fades smoothly outward, producing
    /// a continuous volumetric effect (not discrete blobs). The additive blending
    /// causes overlapping layers to build up brightness in the center.
    /// Z-index 0 keeps glow visible above floor/walls. The weapon sprite at
    /// z_index=1 renders on top of the glow, which is the correct layering order.
    /// </summary>
    private static readonly GlowLayerDef[] GlowLayers = new[]
    {
        new GlowLayerDef(6.0f, 0.6f, 0),    // Core boost — tight bright halo around beam
        new GlowLayerDef(14.0f, 0.15f, 0),  // Inner glow — visible soft aura
        new GlowLayerDef(28.0f, 0.05f, 0),  // Mid glow — subtle extended scatter
        new GlowLayerDef(48.0f, 0.02f, 0),  // Outer glow — barely perceptible atmospheric haze
    };

    // =========================================================================
    // Endpoint glow configuration
    // =========================================================================

    /// <summary>
    /// Energy of the endpoint PointLight2D.
    /// Higher than flashlight_effect.gd scatter (0.4) to make laser dot clearly
    /// visible as a glowing point at the hit location.
    /// </summary>
    private const float EndpointGlowEnergy = 0.7f;

    /// <summary>
    /// Texture scale of the endpoint PointLight2D. Small scale for a tight dot,
    /// similar to flashlight scatter but smaller since laser dot is subtler.
    /// </summary>
    private const float EndpointGlowTextureScale = 0.35f;

    /// <summary>
    /// Size of the circular glow texture in pixels.
    /// Matches flashlight_effect.gd scatter light texture (512x512).
    /// </summary>
    private const int GlowTextureSize = 512;

    // =========================================================================
    // Dust particle configuration
    // =========================================================================

    /// <summary>
    /// Number of dust mote particles along the beam. High count with tiny
    /// particles creates the subtle shimmer of laser light on atmospheric dust,
    /// rather than the discrete blob effect that fewer large particles produce.
    /// </summary>
    private const int DustParticleAmount = 80;

    /// <summary>
    /// Lifetime of each dust particle in seconds. Shorter lifetime keeps
    /// particles flickering and refreshing, simulating brief dust glints.
    /// </summary>
    private const float DustParticleLifetime = 0.8f;

    /// <summary>
    /// Size of the dust mote texture in pixels. Small size (6px) ensures
    /// particles appear as tiny specks rather than visible orbs. Combined with
    /// scale 0.3-0.8x, final rendered size is 2-5 pixels — matching real-world
    /// appearance of dust catching laser light.
    /// </summary>
    private const int DustTextureSize = 6;

    /// <summary>
    /// Vertical half-extent of the dust emission box (how far from beam center
    /// particles can spawn, in pixels). Small value keeps dust motes close to
    /// the beam, reinforcing the laser line rather than scattering around it.
    /// </summary>
    private const float DustEmissionHalfHeight = 2.0f;

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

        if (_diagnosticLogging)
            GD.Print($"[LaserGlowEffect] Creating glow for {parent.Name}, color=({laserColor.R:F2},{laserColor.G:F2},{laserColor.B:F2},{laserColor.A:F2})");

        // Shared additive blending material for all glow layers
        var additiveMaterial = new CanvasItemMaterial();
        additiveMaterial.BlendMode = CanvasItemMaterial.BlendModeEnum.Add;

        // Shared width curve for soft falloff at beam start/end
        // Tight ramp (5%/95%) gives a crisp laser-like beam
        var widthCurve = new Curve();
        widthCurve.AddPoint(new Vector2(0.0f, 0.0f)); // Start thin
        widthCurve.AddPoint(new Vector2(0.05f, 1.0f)); // Reach full width quickly
        widthCurve.AddPoint(new Vector2(0.95f, 1.0f)); // Stay full width
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

            if (_diagnosticLogging)
                GD.Print($"[LaserGlowEffect]   Layer {i}: width={layer.Width}px, alpha={layer.Alpha:F2}, z_index={layer.ZIndex}");
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

        if (_diagnosticLogging)
            GD.Print($"[LaserGlowEffect] Created {GlowLayers.Length} glow layers + endpoint light + dust particles for {parent.Name}");
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
        // Build a color ramp: gentle fade in → subtle peak → fade out
        // Low peak alpha (0.4) ensures particles are subtle accents, not blobs
        var colorRamp = new Gradient();
        colorRamp.SetColor(0, new Color(1.0f, 1.0f, 1.0f, 0.0f)); // start transparent
        colorRamp.AddPoint(0.2f, new Color(1.0f, 1.0f, 1.0f, 0.4f));  // fade in
        colorRamp.AddPoint(0.5f, new Color(1.0f, 1.0f, 1.0f, 0.4f));  // subtle peak
        colorRamp.AddPoint(0.8f, new Color(1.0f, 1.0f, 1.0f, 0.3f));  // begin fade
        colorRamp.SetColor(1, new Color(1.0f, 1.0f, 1.0f, 0.0f)); // end transparent

        // Particle process material
        _dustMaterial = new ParticleProcessMaterial
        {
            EmissionShape = ParticleProcessMaterial.EmissionShapeEnum.Box,
            EmissionBoxExtents = new Vector3(100.0f, DustEmissionHalfHeight, 0.0f),
            Direction = new Vector3(0.0f, -1.0f, 0.0f),
            Spread = 180.0f,
            InitialVelocityMin = 1.0f,
            InitialVelocityMax = 4.0f,
            Gravity = new Vector3(0.0f, 0.0f, 0.0f),
            ScaleMin = 0.3f,
            ScaleMax = 0.8f,
            ColorRamp = new GradientTexture1D { Gradient = colorRamp },
            LifetimeRandomness = 0.5f,
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
            ZIndex = 0,
            Visible = true,
            // Use local coordinates so particles move with the parent node.
            // Without this, particles use global coordinates and lag behind
            // when the weapon/player moves (Issue #694).
            LocalCoords = true
        };

        parent.AddChild(_dustParticles);

        if (_diagnosticLogging)
            GD.Print($"[LaserGlowEffect] Dust particles created: amount={DustParticleAmount}, lifetime={DustParticleLifetime}s, texture={DustTextureSize}px");
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
    /// Creates a tiny pinpoint texture for dust mote particles.
    /// The texture is a small bright speck with rapid exponential falloff,
    /// simulating a tiny dust particle catching laser light. At 6px with
    /// 0.3-0.8x scale, these render as 2-5 pixel specks.
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

                // Sharp pinpoint with rapid cubic falloff
                float alpha;
                if (normalizedDist <= 0.15f)
                {
                    alpha = 0.5f; // Tiny bright center
                }
                else if (normalizedDist <= 0.5f)
                {
                    // Cubic falloff for rapid dimming
                    float t = (normalizedDist - 0.15f) / 0.35f;
                    alpha = 0.5f * (1.0f - t * t * t);
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
