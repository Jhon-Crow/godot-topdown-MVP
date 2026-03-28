shader_type canvas_item;
// Rain occlusion shader (Issue #1615).
// Discards rain particle fragments whose world position falls inside any
// registered building exclusion zone, so rain appears only outdoors.
// Supports up to MAX_ZONES rectangular zones (Rect2: x, y, width, height).
//
// Usage: set this as the ShaderMaterial on RainStreaks and RainSplashes nodes.
// Call rain_effect.gd to update zone uniforms whenever exclusion zones change.
//
// Technical note: In Godot 4 canvas_item shaders, MODEL_MATRIX is available
// only in the vertex stage (not fragment). It contains the per-particle world
// transform (emitter_transform × particle_instance_transform), so
// MODEL_MATRIX[3].xy is the particle's center in world space. We pass this
// through a varying so the fragment stage can test it against exclusion zones.

// Maximum number of supported exclusion zones.
// Increase if more buildings are added; each zone costs 4 floats of uniform data.
const int MAX_ZONES = 8;

// Number of active exclusion zones (zones[0..zone_count-1] are used).
uniform int zone_count : hint_range(0, 8) = 0;

// Exclusion zone rectangles in world coordinates.
// Each vec4 encodes: (x_min, y_min, x_max, y_max).
// Unused entries are ignored (zone_count controls how many are tested).
uniform vec4 zones[8];

// Per-particle world-space center position passed from vertex to fragment.
// MODEL_MATRIX is a canvas_item vertex-stage-only built-in; this varying
// bridges it to the fragment stage for per-particle discard decisions.
varying vec2 particle_world_pos;

void vertex() {
	// MODEL_MATRIX in the vertex stage of a canvas_item shader applied to
	// GPUParticles2D is the combined (emitter_world × particle_instance)
	// transform for each individual particle — NOT the shared emitter matrix.
	// Column 3 of a 4x4 affine matrix is the translation, so [3].xy is the
	// particle center in world space.
	particle_world_pos = MODEL_MATRIX[3].xy;
}

void fragment() {
	// Test the particle's world-space center against each active exclusion zone.
	for (int i = 0; i < MAX_ZONES; i++) {
		if (i >= zone_count) {
			break;
		}
		vec4 zone = zones[i];
		// zone: (x_min, y_min, x_max, y_max)
		if (particle_world_pos.x >= zone.x && particle_world_pos.x <= zone.z &&
				particle_world_pos.y >= zone.y && particle_world_pos.y <= zone.w) {
			discard;
		}
	}

	// Outside all exclusion zones — keep the particle's default color.
	COLOR = COLOR;
}
