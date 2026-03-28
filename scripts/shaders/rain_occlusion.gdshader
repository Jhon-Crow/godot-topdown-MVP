shader_type canvas_item;
// Rain occlusion shader (Issue #1615).
// Discards rain particle fragments whose world position falls inside any
// registered building exclusion zone, so rain appears only outdoors.
// Supports up to MAX_ZONES rectangular zones (Rect2: x, y, width, height).
//
// Usage: set this as the ShaderMaterial on RainStreaks and RainSplashes nodes.
// Call rain_effect.gd to update zone uniforms whenever exclusion zones change.

// Maximum number of supported exclusion zones.
// Increase if more buildings are added; each zone costs 4 floats of uniform data.
const int MAX_ZONES = 8;

// Number of active exclusion zones (zones[0..zone_count-1] are used).
uniform int zone_count : hint_range(0, 8) = 0;

// Exclusion zone rectangles in world coordinates.
// Each vec4 encodes: (x_min, y_min, x_max, y_max).
// Unused entries are ignored (zone_count controls how many are tested).
uniform vec4 zones[8];

void fragment() {
	// WORLD_MATRIX is the 3x4 column-major matrix for this canvas item.
	// For particles, column 2 (index 2) holds the world-space translation.
	// .x = world X, .y = world Y.
	vec2 world_pos = WORLD_MATRIX[2].xy;

	// Test against each active exclusion zone.
	for (int i = 0; i < MAX_ZONES; i++) {
		if (i >= zone_count) {
			break;
		}
		vec4 zone = zones[i];
		// zone: (x_min, y_min, x_max, y_max)
		if (world_pos.x >= zone.x && world_pos.x <= zone.z &&
			world_pos.y >= zone.y && world_pos.y <= zone.w) {
			discard;
		}
	}

	// Outside all exclusion zones — keep the particle's default color.
	COLOR = COLOR;
}
