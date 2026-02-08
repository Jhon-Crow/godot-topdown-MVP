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
/// Usage:
///   _laserGlow = new LaserGlowEffect();
///   _laserGlow.Create(this, laserColor);
///   // In _Process: _laserGlow.Update(Vector2.Zero, endPoint);
///   // Cleanup:     _laserGlow.Cleanup();
/// </summary>
public class LaserGlowEffect
{
    /// <summary>
    /// Width multiplier for the glow line relative to the main laser width.
    /// A 6x multiplier creates a subtle but visible aura around the 2px laser.
    /// </summary>
    private const float GlowWidthMultiplier = 6.0f;

    /// <summary>
    /// Alpha (opacity) of the glow line. Low alpha for a subtle, realistic effect.
    /// </summary>
    private const float GlowAlpha = 0.15f;

    /// <summary>
    /// Energy of the endpoint PointLight2D. Low energy for a subtle dot.
    /// Matches the scatter light energy used in flashlight_effect.gd (0.4).
    /// </summary>
    private const float EndpointGlowEnergy = 0.4f;

    /// <summary>
    /// Texture scale of the endpoint PointLight2D. Small scale for a tight dot.
    /// </summary>
    private const float EndpointGlowTextureScale = 0.5f;

    /// <summary>
    /// Base width of the main laser line (matches all weapon CreateLaserSight methods).
    /// </summary>
    private const float BaseLaserWidth = 2.0f;

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
            Width = BaseLaserWidth * GlowWidthMultiplier,
            DefaultColor = new Color(laserColor.R, laserColor.G, laserColor.B, GlowAlpha),
            BeginCapMode = Line2D.LineCapMode.Round,
            EndCapMode = Line2D.LineCapMode.Round,
            ZIndex = -1 // Behind the main laser line
        };

        // Additive blending for soft, realistic glow
        var glowMaterial = new CanvasItemMaterial();
        glowMaterial.BlendMode = CanvasItemMaterial.BlendModeEnum.Add;
        _glowLine.Material = glowMaterial;

        _glowLine.AddPoint(Vector2.Zero);
        _glowLine.AddPoint(Vector2.Right * 500.0f);

        parent.AddChild(_glowLine);

        // Create endpoint glow (PointLight2D with radial gradient)
        _endpointGlow = new PointLight2D
        {
            Name = "LaserEndpointGlow",
            Color = new Color(laserColor.R, laserColor.G, laserColor.B, 1.0f),
            Energy = EndpointGlowEnergy,
            ShadowEnabled = false, // No wall shadows needed for a tiny decorative glow
            TextureScale = EndpointGlowTextureScale,
            Texture = CreateRadialGlowTexture(),
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
    /// Creates a radial gradient texture for the endpoint glow.
    /// Follows the same pattern as flashlight_effect.gd _create_scatter_light_texture().
    /// Uses an early-fadeout design where the gradient reaches zero at 55% radius.
    /// </summary>
    /// <returns>A radial GradientTexture2D suitable for PointLight2D.</returns>
    private static GradientTexture2D CreateRadialGlowTexture()
    {
        var gradient = new Gradient();
        // Bright center core
        gradient.SetColor(0, new Color(1.0f, 1.0f, 1.0f, 1.0f));
        // Smooth falloff
        gradient.AddPoint(0.1f, new Color(0.8f, 0.8f, 0.8f, 1.0f));
        gradient.AddPoint(0.25f, new Color(0.4f, 0.4f, 0.4f, 1.0f));
        gradient.AddPoint(0.4f, new Color(0.1f, 0.1f, 0.1f, 1.0f));
        // Fade to zero by 55% — remaining 45% is pure black buffer
        gradient.AddPoint(0.5f, new Color(0.03f, 0.03f, 0.03f, 1.0f));
        gradient.AddPoint(0.55f, new Color(0.0f, 0.0f, 0.0f, 1.0f));
        gradient.SetColor(1, new Color(0.0f, 0.0f, 0.0f, 1.0f));

        var texture = new GradientTexture2D();
        texture.Gradient = gradient;
        texture.Width = 256;
        texture.Height = 256;
        texture.Fill = GradientTexture2D.FillEnum.Radial;
        texture.FillFrom = new Vector2(0.5f, 0.5f);
        texture.FillTo = new Vector2(0.5f, 0.0f);
        return texture;
    }
}
