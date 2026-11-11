// Stylized paper sea: banded, gently moving folds of color under the floating islands.
// Noise comes from a tileable texture (OVPaperMesh.grain_texture): per-pixel hash noise on a full-screen
// plane cost ~25 ms per frame on an Adreno 610. Lighting is Lambert-only for the same reason.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec3 color_a : source_color = vec3(0.62, 0.83, 0.9);
uniform vec3 color_b : source_color = vec3(0.85, 0.94, 0.95);
uniform float band_scale = 0.22;
uniform float speed = 0.12;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.35 + TIME * 0.6) * 0.12 + cos(wpos.z * 0.28 + TIME * 0.45) * 0.1;
}

void fragment() {
	vec2 p = wpos.xz * band_scale * 0.0625;
	float n = texture(noise_tex, p + vec2(TIME * speed, TIME * speed * 0.6) * 0.0625).r * 0.6
		+ texture(noise_tex, p * 2.3 - TIME * speed * 0.0625).r * 0.4;
	float bands = floor(n * 5.0) / 5.0;
	float dist = length(wpos.xz) * 0.012;
	vec3 col = mix(color_a, color_b, bands);
	col = mix(col, color_b, clamp(dist, 0.0, 0.6));
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
