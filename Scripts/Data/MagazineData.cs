using Godot;
using System.Collections.Generic;
using System.Linq;

namespace GodotTopDownTemplate.Data;

/// <summary>
/// Data structure representing a single magazine with its current ammo count.
/// </summary>
[GlobalClass]
public partial class MagazineData : Resource
{
    /// <summary>
    /// Current number of bullets in this magazine.
    /// </summary>
    [Export]
    public int CurrentAmmo { get; set; }

    /// <summary>
    /// Maximum capacity of this magazine.
    /// </summary>
    [Export]
    public int MaxCapacity { get; set; }

    /// <summary>
    /// Creates a new magazine with specified ammo and capacity.
    /// </summary>
    /// <param name="currentAmmo">Current bullets in magazine.</param>
    /// <param name="maxCapacity">Maximum magazine capacity.</param>
    public MagazineData(int currentAmmo, int maxCapacity)
    {
        CurrentAmmo = currentAmmo;
        MaxCapacity = maxCapacity;
    }

    /// <summary>
    /// Default constructor for Godot serialization.
    /// </summary>
    public MagazineData() : this(0, 30)
    {
    }

    /// <summary>
    /// Returns true if the magazine is empty.
    /// </summary>
    public bool IsEmpty => CurrentAmmo <= 0;

    /// <summary>
    /// Returns true if the magazine is full.
    /// </summary>
    public bool IsFull => CurrentAmmo >= MaxCapacity;

    /// <summary>
    /// Returns the fill percentage of the magazine (0.0 to 1.0).
    /// </summary>
    public float FillPercent => MaxCapacity > 0 ? (float)CurrentAmmo / MaxCapacity : 0f;
}

/// <summary>
/// Manages a collection of magazines for a weapon.
/// Provides functionality for magazine swapping, selection, and tracking.
/// </summary>
public class MagazineInventory
{
    /// <summary>
    /// List of spare magazines (not including the currently loaded one).
    /// </summary>
    private readonly List<MagazineData> _spareMagazines = new();

    /// <summary>
    /// The currently loaded magazine (null if weapon is empty).
    /// </summary>
    public MagazineData? CurrentMagazine { get; private set; }

    /// <summary>
    /// Gets all spare magazines (not including current).
    /// </summary>
    public IReadOnlyList<MagazineData> SpareMagazines => _spareMagazines.AsReadOnly();

    /// <summary>
    /// Gets the total number of magazines (including current).
    /// </summary>
    public int TotalMagazineCount => (CurrentMagazine != null ? 1 : 0) + _spareMagazines.Count;

    /// <summary>
    /// Gets the total ammo across all spare magazines.
    /// </summary>
    public int TotalSpareAmmo => _spareMagazines.Sum(m => m.CurrentAmmo);

    /// <summary>
    /// Gets all magazines including the current one.
    /// Current magazine is first in the list if present.
    /// </summary>
    public IEnumerable<MagazineData> AllMagazines
    {
        get
        {
            if (CurrentMagazine != null)
            {
                yield return CurrentMagazine;
            }
            foreach (var mag in _spareMagazines)
            {
                yield return mag;
            }
        }
    }

    /// <summary>
    /// Initializes the magazine inventory with the specified number of magazines.
    /// </summary>
    /// <param name="magazineCount">Total number of magazines to create.</param>
    /// <param name="magazineSize">Capacity of each magazine.</param>
    /// <param name="fillAllMagazines">If true, all magazines start full. Otherwise, only the current is full.</param>
    public void Initialize(int magazineCount, int magazineSize, bool fillAllMagazines = true)
    {
        _spareMagazines.Clear();

        // Create the current magazine (always full at start)
        CurrentMagazine = new MagazineData(magazineSize, magazineSize);

        // Create spare magazines
        for (int i = 1; i < magazineCount; i++)
        {
            int ammo = fillAllMagazines ? magazineSize : 0;
            _spareMagazines.Add(new MagazineData(ammo, magazineSize));
        }
    }

    /// <summary>
    /// Swaps the current magazine with the spare magazine that has the most ammo.
    /// Returns the old magazine that was removed.
    /// </summary>
    /// <returns>The magazine that was removed (or null if no swap occurred).</returns>
    public MagazineData? SwapToFullestMagazine()
    {
        if (_spareMagazines.Count == 0)
        {
            return null;
        }

        // Find the magazine with the most ammo
        int maxAmmoIndex = 0;
        int maxAmmo = _spareMagazines[0].CurrentAmmo;

        for (int i = 1; i < _spareMagazines.Count; i++)
        {
            if (_spareMagazines[i].CurrentAmmo > maxAmmo)
            {
                maxAmmo = _spareMagazines[i].CurrentAmmo;
                maxAmmoIndex = i;
            }
        }

        // Don't swap if the best available magazine is empty
        if (maxAmmo <= 0)
        {
            return null;
        }

        // Get the magazine to swap in
        MagazineData newMagazine = _spareMagazines[maxAmmoIndex];
        _spareMagazines.RemoveAt(maxAmmoIndex);

        // Store old magazine in spares (if it exists)
        MagazineData? oldMagazine = CurrentMagazine;
        if (oldMagazine != null)
        {
            _spareMagazines.Add(oldMagazine);
        }

        // Set new current magazine
        CurrentMagazine = newMagazine;

        return oldMagazine;
    }

    /// <summary>
    /// Checks if there are any spare magazines with ammo available.
    /// </summary>
    public bool HasSpareAmmo => _spareMagazines.Any(m => m.CurrentAmmo > 0);

    /// <summary>
    /// Consumes one bullet from the current magazine.
    /// Returns true if a bullet was consumed.
    /// </summary>
    public bool ConsumeAmmo()
    {
        if (CurrentMagazine == null || CurrentMagazine.CurrentAmmo <= 0)
        {
            return false;
        }

        CurrentMagazine.CurrentAmmo--;
        return true;
    }

    /// <summary>
    /// Gets a formatted string showing all magazine ammo counts.
    /// Format: "30 | 25 | 10" where first number is current magazine.
    /// </summary>
    public string GetMagazineDisplayString()
    {
        var parts = new List<string>();

        if (CurrentMagazine != null)
        {
            parts.Add($"[{CurrentMagazine.CurrentAmmo}]");
        }

        // Sort spare magazines by ammo count (highest first) for display
        var sortedSpares = _spareMagazines.OrderByDescending(m => m.CurrentAmmo).ToList();
        foreach (var mag in sortedSpares)
        {
            parts.Add(mag.CurrentAmmo.ToString());
        }

        return string.Join(" | ", parts);
    }

    /// <summary>
    /// Gets an array of all magazine ammo counts.
    /// First element is current magazine, rest are spares sorted by ammo count (descending).
    /// </summary>
    public int[] GetMagazineAmmoCounts()
    {
        var counts = new List<int>();

        if (CurrentMagazine != null)
        {
            counts.Add(CurrentMagazine.CurrentAmmo);
        }

        // Sort spare magazines by ammo count (highest first)
        var sortedSpares = _spareMagazines.OrderByDescending(m => m.CurrentAmmo).ToList();
        foreach (var mag in sortedSpares)
        {
            counts.Add(mag.CurrentAmmo);
        }

        return counts.ToArray();
    }

    /// <summary>
    /// Adds a new magazine to the spare magazines.
    /// </summary>
    /// <param name="magazine">The magazine to add.</param>
    public void AddSpareMagazine(MagazineData magazine)
    {
        _spareMagazines.Add(magazine);
    }

    /// <summary>
    /// Adds a new magazine with specified ammo to the spare magazines.
    /// </summary>
    /// <param name="currentAmmo">Ammo in the new magazine.</param>
    /// <param name="maxCapacity">Max capacity of the magazine.</param>
    public void AddSpareMagazine(int currentAmmo, int maxCapacity)
    {
        _spareMagazines.Add(new MagazineData(currentAmmo, maxCapacity));
    }
}
