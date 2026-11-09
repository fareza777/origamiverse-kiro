// Stylized paper sea: banded, gently moving folds of color under the floating islands.
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform vec3 color_a : source_color = vec3(0.62, 0.83, 0.9);
uniform vec3 color_b : source_color = vec3(0.85, 0.94, 0.95);
uniform float band_scale = 0.22;
uniform float speed = 0.12;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.35 + TIME * 0.6) * 0.12 + cos(wpos.z * 0.28 + TIME * 0.45) * 0.1;
}

void fragment() {
	vec2 p = wpos.xz * band_scale;
	float n = vnoise(p + vec2(TIME * speed, TIME * speed * 0.6)) * 0.6 + vnoise(p * 2.3 - TIME * speed) * 0.4;
	float bands = floor(n * 5.0) / 5.0;
	float dist = length(wpos.xz) * 0.012;
	vec3 col = mix(color_a, color_b, bands);
	col = mix(col, color_b, clamp(dist, 0.0, 0.6));
	ALBEDO = col;
	ROUGHNESS = 0.7;
	SPECULAR = 0.3;
}
