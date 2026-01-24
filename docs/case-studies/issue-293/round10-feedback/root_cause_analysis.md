# ROOT CAUSE IDENTIFIED

## The Problem
Round 9 tried to match Round 5's offset distribution but used DIFFERENT alpha values.

## Round 5 Alpha (WORKED):
Offset: 0    0.2  0.35  0.45  0.55  0.62  0.68  0.707  1.0
Alpha:  1.0  1.0  0.95  0.8   0.5   0.25  0.08  0     0

Note: Alpha STAYS at 1.0 from 0 to 0.2, then drops significantly at each step.

## Round 9 Alpha (BROKEN):
Offset: 0    0.2   0.35  0.45  0.55  0.62  0.68  0.707  1.0
Alpha:  1.0  0.98  0.92  0.75  0.5   0.25  0.08  0     0

Note: Alpha drops very slightly (0.98, 0.92) which creates intermediate steps
that may not render well, creating visible bands/edges.

## THE FIX
Match Round 5's alpha EXACTLY:
- Keep 0-0.2 at full alpha 1.0 (no fade)
- Then significant drops: 0.95, 0.8, 0.5, 0.25, 0.08
- Keep uniform color 0.25 (flat matte from Round 7)

This maintains:
✓ 9 offsets (smooth distribution)
✓ Flat matte color (owner requirement)
✓ Proven working alpha curve from Round 5
