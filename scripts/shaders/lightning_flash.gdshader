shader_type canvas_item;
// Lightning flash shader for Black Metal difficulty mode.
//
// Creates a screen-wide flash effect that illuminates everything when
// the player hits an enemy. Works with hint_screen_texture to blend
// the flash with the underlying rendered scene.
//
// Issue #1023: Thunder and lightning effects for Black Metal mode.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float brightness_boost : hint_range(1.0, 5.0) = 2.5;

void fragment() {
	// Sample the screen texture
	vec4 screen_color = texture(TEXTURE, UV);

	// Calculate the flash effect
	// The flash brightens everything on screen (additive-like blend)
	vec3 brightened = screen_color.rgb + flash_color * intensity * brightness_boost;

	// Apply the effect based on intensity
	// At intensity=0, output equals original screen
	// At intensity=1, output is heavily brightened
	COLOR.rgb = mix(screen_color.rgb, brightened, intensity);
	COLOR.a = screen_color.a;
}
