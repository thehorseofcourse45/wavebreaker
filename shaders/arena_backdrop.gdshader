shader_type canvas_item;
// Procedural arena backdrop: a tech grid, a radial vignette and a faint
// scanline, so the game needs no art files for its atmosphere.
//
// GL Compatibility has NO glow post-process (that is Forward+/Mobile only), so
// everything that would be a bloom pass lives in shaders like this one.
//
// One shader, two jobs:
//   * the arena backdrop (overlay = 0): opaque, drawn behind Floor at z -20
//   * the HUD's low-health warning (overlay = 1): alpha follows the vignette so
//     only the SCREEN EDGES tint, and `intensity` (or the node's modulate) is
//     what the HUD animates.
//
// All geometry is in the rect's own local pixels; UV is used only for the
// radial falloff so the overlay variant works at any size.

uniform vec2 size = vec2(3200.0, 2200.0);
uniform vec4 base_color : source_color = vec4(0.055, 0.062, 0.09, 1.0);
uniform vec4 grid_color : source_color = vec4(0.2, 0.55, 0.62, 1.0);
uniform float grid_spacing = 64.0;
uniform float grid_width = 1.5;
uniform float grid_alpha = 0.42;
uniform float vignette = 0.7;
// Falloff radius in the rect's own pixels, NOT uv: a uv-based vignette on the
// arena backdrop is computed against the whole 3200x2200 rect, so at the arena
// centre (where the camera lives) it is effectively invisible. In pixels it
// darkens toward the arena's edges and corners, which is where it reads.
uniform float vignette_radius = 1100.0;
uniform float scan_alpha = 0.04;
uniform float intensity = 1.0;
uniform float overlay = 0.0;

void fragment() {
	vec2 p = UV * size;
	// Grid: a thin line per cell, a brighter one every fourth cell.
	vec2 cell = abs(fract(p / grid_spacing + 0.5) - 0.5) * grid_spacing;
	float minor = 1.0 - smoothstep(0.0, grid_width, min(cell.x, cell.y));
	vec2 major_cell = abs(fract(p / (grid_spacing * 4.0) + 0.5) - 0.5) * (grid_spacing * 4.0);
	float major = 1.0 - smoothstep(0.0, grid_width * 1.8, min(major_cell.x, major_cell.y));
	float grid = clamp(minor * 0.55 + major, 0.0, 1.0) * grid_alpha;
	// Radial falloff from the centre of the rect: darkens the far corners.
	float d = length(p - size * 0.5) / max(vignette_radius, 1.0);
	float vig = smoothstep(0.35, 1.0, d) * vignette;
	// Static scanline (no TIME uniform: a still backdrop, and the screenshot
	// mode then needs no frozen-flag dance).
	float scan = step(0.5, fract(p.y / 4.0)) * scan_alpha;
	vec3 col = mix(base_color.rgb, grid_color.rgb, grid * intensity);
	col = mix(col, base_color.rgb * 0.3, vig * intensity);
	COLOR = vec4(col + scan * intensity, mix(1.0, vig * intensity, overlay));
}
