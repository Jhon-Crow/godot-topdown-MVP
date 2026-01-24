# Compare gradient configurations

print("=== ROUND 5 (WORKING - Circular) ===")
r5_offsets = [0, 0.2, 0.35, 0.45, 0.55, 0.62, 0.68, 0.707, 1.0]
r5_colors = [
    (0.4, 0.03, 0.03, 1.0),
    (0.38, 0.025, 0.025, 1.0),
    (0.36, 0.022, 0.022, 0.95),
    (0.33, 0.018, 0.018, 0.8),
    (0.30, 0.014, 0.014, 0.5),
    (0.28, 0.01, 0.01, 0.25),
    (0.26, 0.008, 0.008, 0.08),
    (0.25, 0.005, 0.005, 0),
    (0.25, 0.005, 0.005, 0)
]

for i, (off, (r,g,b,a)) in enumerate(zip(r5_offsets, r5_colors)):
    gap = r5_offsets[i+1] - off if i < len(r5_offsets)-1 else 0
    print(f"  {off:0.3f}: RGB({r:.2f},{g:.3f},{b:.3f}) A={a:.2f}  [gap: {gap:.2f}]")

print("\n=== ROUND 8 (BROKEN - Rectangular) ===")
r8_offsets = [0, 0.55, 0.62, 0.68, 0.707, 1.0]
r8_colors = [
    (0.25, 0.02, 0.02, 0.95),
    (0.25, 0.02, 0.02, 0.85),
    (0.25, 0.02, 0.02, 0.5),
    (0.25, 0.02, 0.02, 0.15),
    (0.25, 0.02, 0.02, 0),
    (0.25, 0.02, 0.02, 0)
]

for i, (off, (r,g,b,a)) in enumerate(zip(r8_offsets, r8_colors)):
    gap = r8_offsets[i+1] - off if i < len(r8_offsets)-1 else 0
    print(f"  {off:0.3f}: RGB({r:.2f},{g:.3f},{b:.3f}) A={a:.2f}  [gap: {gap:.2f}]")

print("\n=== ROUND 9 (Current - Still rectangular?) ===")
r9_offsets = [0, 0.2, 0.35, 0.45, 0.55, 0.62, 0.68, 0.707, 1.0]
r9_colors = [
    (0.25, 0.02, 0.02, 1.0),
    (0.25, 0.02, 0.02, 0.98),
    (0.25, 0.02, 0.02, 0.92),
    (0.25, 0.02, 0.02, 0.75),
    (0.25, 0.02, 0.02, 0.5),
    (0.25, 0.02, 0.02, 0.25),
    (0.25, 0.02, 0.02, 0.08),
    (0.25, 0.02, 0.02, 0),
    (0.25, 0.02, 0.02, 0)
]

for i, (off, (r,g,b,a)) in enumerate(zip(r9_offsets, r9_colors)):
    gap = r9_offsets[i+1] - off if i < len(r9_offsets)-1 else 0
    print(f"  {off:0.3f}: RGB({r:.2f},{g:.3f},{b:.3f}) A={a:.2f}  [gap: {gap:.2f}]")

print("\n=== ANALYSIS ===")
print("Round 5: 9 offsets, varying RGB (0.4→0.25), varying alpha")
print("Round 8: 6 offsets, uniform RGB (0.25), BIG GAP at start (0→0.55)")
print("Round 9: 9 offsets, uniform RGB (0.25), same gaps as R5")
print("\nKey difference R5 vs R9:")
print("  - R5: RGB color fades 0.4→0.25 (bright to dark)")
print("  - R9: RGB is constant 0.25 (flat color)")
print("\nHypothesis: Uniform color might cause issues with visibility/blending")
