using Godot;

namespace GodotTopDownTemplate.Weapons;

/// <summary>
/// Creates and manages glow effects for laser sights.
/// Adds a subtle aura (wider semi-transparent Line2D with additive blending)
/// around the laser beam, and a small residual glow (PointLight2D) at the
/// laser endpoint. All effects match the laser's color.
///
/// This uses a "fake glow" approach compatible with the gl_compatibility renderer,
/// since WorldEnvironment glow is not available in that rendering mode.
///
/// The endpoint glow uses a pixel-perfect circular texture (via Image) to avoid
/// the square artifact that GradientTexture2D produces. The approach follows the
/// flashlight scatter light pattern from flashlight_effect.gd (Issue #644).
///
/// Usage:
///   _laserGlow = new LaserGlowEffect();
///   _laserGlow.Create(this, laserColor);
///   // In _Process: _laserGlow.Update(Vector2.Zero, endPoint);
///   // Cleanup:     _laserGlow.Cleanup();
/// </summary>
public class LaserGlowEffect
{
    /// <summary>
    /// Width of the glow aura line in pixels. Wide enough to be visible around
    /// the 2px laser but not so wide as to look unrealistic.
    /// </summary>
    private const float GlowLineWidth = 8.0f;

    /// <summary>
    /// Alpha (opacity) of the glow line. Visible but still subtle.
    /// </summary>
    private const float GlowAlpha = 0.35f;

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

    /// <summary>
    /// The wider, semi-transparent Line2D that creates the glow aura around the laser.
    /// </summary>
    private Line2D? _glowLine;

    /// <summary>
    /// The PointLight2D at the laser endpoint for residual glow effect.
    /// </summary>
    private PointLight2D? _endpointGlow;

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

        // Create the glow aura line (wider, semi-transparent, additive blending)
        _glowLine = new Line2D
        {
            Name = "LaserGlow",
            Width = GlowLineWidth,
            DefaultColor = new Color(laserColor.R, laserColor.G, laserColor.B, GlowAlpha),
            BeginCapMode = Line2D.LineCapMode.Round,
            EndCapMode = Line2D.LineCapMode.Round,
            ZIndex = -1 // Behind the main laser line
        };

        // Width curve for soft falloff from center — thicker in the middle, thin at edges
        var widthCurve = new Curve();
        widthCurve.AddPoint(new Vector2(0.0f, 0.0f)); // Start thin
        widthCurve.AddPoint(new Vector2(0.1f, 1.0f));  // Reach full width quickly
        widthCurve.AddPoint(new Vector2(0.9f, 1.0f));  // Stay full width
        widthCurve.AddPoint(new Vector2(1.0f, 0.0f));  // End thin
        _glowLine.WidthCurve = widthCurve;

        // Additive blending for soft, realistic glow
        var glowMaterial = new CanvasItemMaterial();
        glowMaterial.BlendMode = CanvasItemMaterial.BlendModeEnum.Add;
        _glowLine.Material = glowMaterial;

        _glowLine.AddPoint(Vector2.Zero);
        _glowLine.AddPoint(Vector2.Right * 500.0f);

        parent.AddChild(_glowLine);

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
    }

    /// <summary>
    /// Updates the glow effect positions to match the current laser sight.
    /// Call this from UpdateLaserSight() in each weapon after updating the main laser.
    /// </summary>
    /// <param name="startPoint">Start point of the laser (local coordinates, usually Vector2.Zero).</param>
    /// <param name="endPoint">End point of the laser (local coordinates, from raycast).</param>
    public void Update(Vector2 startPoint, Vector2 endPoint)
    {
        // Sync glow line points with main laser
        if (_glowLine != null)
        {
            _glowLine.SetPointPosition(0, startPoint);
            _glowLine.SetPointPosition(1, endPoint);
        }

        // Move endpoint glow to the laser hit point
        if (_endpointGlow != null)
        {
            _endpointGlow.Position = endPoint;
        }
    }

    /// <summary>
    /// Sets visibility of the glow effect.
    /// Call this when the laser sight visibility changes.
    /// </summary>
    /// <param name="visible">Whether the glow should be visible.</param>
    public void SetVisible(bool visible)
    {
        if (_glowLine != null)
        {
            _glowLine.Visible = visible;
        }

        if (_endpointGlow != null)
        {
            _endpointGlow.Visible = visible;
        }
    }

    /// <summary>
    /// Removes and frees the glow effect nodes.
    /// Call this when the weapon is being destroyed or laser sight is removed.
    /// </summary>
    public void Cleanup()
    {
        if (_glowLine != null && GodotObject.IsInstanceValid(_glowLine))
        {
            _glowLine.QueueFree();
            _glowLine = null;
        }

        if (_endpointGlow != null && GodotObject.IsInstanceValid(_endpointGlow))
        {
            _endpointGlow.QueueFree();
            _endpointGlow = null;
        }

        _parent = null;
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
