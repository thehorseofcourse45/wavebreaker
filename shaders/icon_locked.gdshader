shader_type canvas_item;
// Locked-state treatment for unlockable icons: fully desaturated and darkened,
// so "not earned yet" reads at a glance and the colour art is the reward.
//
// One shader for every tile (each locked icon gets its own material instance and
// flips `locked` to 0 when earned) instead of shipping a grey copy of every PNG.

uniform float locked : hint_range(0.0, 1.0) = 1.0;
uniform float darkness = 0.32;

void fragment() {
	vec4 col = texture(TEXTURE, UV) * COLOR;   // COLOR carries modulate
	float grey = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	col.rgb = mix(col.rgb, vec3(grey) * darkness, locked);
	COLOR = col;
}
