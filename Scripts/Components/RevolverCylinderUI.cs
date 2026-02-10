using Godot;
using GodotTopDownTemplate.Weapons;

namespace GodotTopDownTemplate.Components;

/// <summary>
/// HUD display for the revolver cylinder (Issue #691).
/// Shows 5 cylinder chamber slots arranged as: 2 left, 1 center (active), 2 right.
/// The active slot (where the hammer will strike on LMB) is highlighted and larger:
/// - Yellow: hammer is NOT cocked — pressing LMB will rotate the cylinder first.
/// - Red: hammer IS cocked — shot fires immediately without cylinder rotation.
/// Chambers with live rounds are shown as filled circles, empty chambers as outlines.
/// </summary>
public partial class RevolverCylinderUI : Control
{
    /// <summary>
    /// Reference to the revolver weapon for reading cylinder state.
    /// </summary>
    private Revolver? _revolver;

    /// <summary>
    /// Cached chamber states from the revolver.
    /// </summary>
    private bool[] _chamberStates = System.Array.Empty<bool>();

    /// <summary>
    /// Current chamber index (the one the hammer will hit).
    /// </summary>
    private int _currentChamberIndex;

    /// <summary>
    /// Whether the hammer is currently cocked.
    /// </summary>
    private bool _isHammerCocked;

    /// <summary>
    /// Number of chambers in the cylinder.
    /// </summary>
    private int _cylinderCapacity = 5;

    /// <summary>
    /// Base size of a chamber slot circle (radius in pixels).
    /// </summary>
    private const float SlotRadius = 8.0f;

    /// <summary>
    /// Size of the active (highlighted) chamber slot circle (radius in pixels).
    /// </summary>
    private const float ActiveSlotRadius = 11.0f;

    /// <summary>
    /// Spacing between slot centers (in pixels).
    /// </summary>
    private const float SlotSpacing = 28.0f;

    /// <summary>
    /// Color for filled chamber (has a live round).
    /// </summary>
    private static readonly Color FilledColor = new(0.85f, 0.85f, 0.85f, 1.0f);

    /// <summary>
    /// Color for empty chamber outline.
    /// </summary>
    private static readonly Color EmptyColor = new(0.5f, 0.5f, 0.5f, 0.6f);

    /// <summary>
    /// Color for active slot when hammer is NOT cocked (LMB will rotate cylinder first).
    /// </summary>
    private static readonly Color UncockedColor = new(1.0f, 0.9f, 0.2f, 1.0f); // Yellow

    /// <summary>
    /// Color for active slot when hammer IS cocked (instant shot).
    /// </summary>
    private static readonly Color CockedColor = new(1.0f, 0.2f, 0.2f, 1.0f); // Red

    /// <summary>
    /// Background color for the cylinder display panel.
    /// </summary>
    private static readonly Color BackgroundColor = new(0.0f, 0.0f, 0.0f, 0.4f);

    /// <summary>
    /// Connects to the given revolver and starts displaying its cylinder state.
    /// </summary>
    /// <param name="revolver">The revolver to display cylinder state for.</param>
    public void ConnectToRevolver(Revolver revolver)
    {
        // Disconnect from previous revolver if any
        DisconnectFromRevolver();

        _revolver = revolver;
        _cylinderCapacity = revolver.CylinderCapacity;

        // Connect to the CylinderStateChanged signal for live updates
        if (_revolver.HasSignal("CylinderStateChanged"))
        {
            _revolver.CylinderStateChanged += OnCylinderStateChanged;
        }

        // Initial state update
        UpdateCylinderState();
    }

    /// <summary>
    /// Disconnects from the current revolver.
    /// </summary>
    public void DisconnectFromRevolver()
    {
        if (_revolver != null && IsInstanceValid(_revolver))
        {
            _revolver.CylinderStateChanged -= OnCylinderStateChanged;
        }
        _revolver = null;
    }

    /// <summary>
    /// Called when the cylinder state changes (signal handler).
    /// </summary>
    private void OnCylinderStateChanged()
    {
        UpdateCylinderState();
    }

    /// <summary>
    /// Reads the current cylinder state from the revolver and triggers a redraw.
    /// </summary>
    private void UpdateCylinderState()
    {
        if (_revolver == null || !IsInstanceValid(_revolver))
        {
            return;
        }

        _chamberStates = _revolver.GetChamberStates();
        _currentChamberIndex = _revolver.CurrentChamberIndex;
        _isHammerCocked = _revolver.IsHammerCocked;
        _cylinderCapacity = _revolver.CylinderCapacity;

        QueueRedraw();
    }

    public override void _Draw()
    {
        if (_chamberStates.Length == 0)
        {
            return;
        }

        // Layout: arrange slots with the active (current) slot in the center.
        // Order: 2 slots to the left of center, center slot, 2 slots to the right.
        // The slots are arranged by their cylinder position relative to the current chamber.
        //
        // For a 5-chamber cylinder with current chamber at index C:
        // Display order (left to right): C-2, C-1, C (center), C+1, C+2

        int capacity = _chamberStates.Length;
        float totalWidth = (capacity - 1) * SlotSpacing + ActiveSlotRadius * 2;
        float panelPadding = 8.0f;
        float panelWidth = totalWidth + panelPadding * 2;
        float panelHeight = ActiveSlotRadius * 2 + panelPadding * 2;

        // Center point of this control
        Vector2 controlCenter = new(panelWidth / 2, panelHeight / 2);

        // Draw background panel
        DrawRect(new Rect2(0, 0, panelWidth, panelHeight), BackgroundColor);

        // Draw each slot
        // Center slot index in the display is capacity / 2 (e.g., 2 for 5 slots)
        int centerDisplayIndex = capacity / 2;

        for (int displayPos = 0; displayPos < capacity; displayPos++)
        {
            // Calculate the chamber index for this display position
            // displayPos 0 = leftmost, centerDisplayIndex = center (active), capacity-1 = rightmost
            int offset = displayPos - centerDisplayIndex;
            int chamberIndex = ((_currentChamberIndex + offset) % capacity + capacity) % capacity;

            bool isActive = displayPos == centerDisplayIndex;
            bool isOccupied = chamberIndex < _chamberStates.Length && _chamberStates[chamberIndex];

            // Calculate position
            float x = panelPadding + ActiveSlotRadius + displayPos * SlotSpacing;
            float y = controlCenter.Y;
            Vector2 pos = new(x, y);

            float radius = isActive ? ActiveSlotRadius : SlotRadius;

            if (isActive)
            {
                // Active slot: color depends on hammer state
                Color activeColor = _isHammerCocked ? CockedColor : UncockedColor;

                if (isOccupied)
                {
                    // Filled active slot
                    DrawCircle(pos, radius, activeColor);
                }
                else
                {
                    // Empty active slot — outline only
                    DrawArc(pos, radius, 0, Mathf.Tau, 32, activeColor, 2.0f);
                }
            }
            else
            {
                // Non-active slot
                if (isOccupied)
                {
                    // Filled slot (has live round)
                    DrawCircle(pos, radius, FilledColor);
                }
                else
                {
                    // Empty slot — outline only
                    DrawArc(pos, radius, 0, Mathf.Tau, 32, EmptyColor, 1.5f);
                }
            }
        }

        // Set the minimum size for layout
        CustomMinimumSize = new Vector2(panelWidth, panelHeight);
    }

    public override void _ExitTree()
    {
        DisconnectFromRevolver();
        base._ExitTree();
    }
}
