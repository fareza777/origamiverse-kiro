// OrigamiVerse paper shader. Two-sided paper with procedural fibers and assignment-aware crease lines.
// Mesh contract (OVPaperMesh): UV = sheet coordinates, UV2 = barycentric (x, y), COLOR.rgb = crease code
// of the edge opposite corner 0/1/2. Codes: 0 none, 0.25 facet, 0.5 valley, 0.75 mountain, 1.0 boundary/cut.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec3 front_color : source_color = vec3(0.96, 0.94, 0.89);
uniform vec3 back_color : source_color = vec3(0.86, 0.36, 0.30);
uniform float grain_strength : hint_range(0.0, 0.4) = 0.08;
uniform float grain_scale = 28.0;
uniform float fiber_strength : hint_range(0.0, 0.4) = 0.05;
uniform float crease_width : hint_range(0.2, 4.0) = 1.3;
uniform float crease_strength : hint_range(0.0, 1.0) = 0.32;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.25;
uniform float show_assignment = 0.0;
uniform vec3 valley_color : source_color = vec3(0.17, 0.42, 0.95);
uniform vec3 mountain_color : source_color = vec3(0.93, 0.27, 0.22);
uniform float paper_roughness : hint_range(0.0, 1.0) = 0.82;
uniform float paper_specular : hint_range(0.0, 1.0) = 0.25;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float sheen : hint_range(0.0, 1.0) = 0.12;
uniform float uv_scale = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float emission_amount = 0.0;

varying vec3 v_codes;
varying vec2 v_bary;

void vertex() {
	v_codes = COLOR.rgb;
	v_bary = UV2;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float line_mask(float d, float w) {
	return 1.0 - smoothstep(0.0, w, d);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 base = FRONT_FACING ? front_color : back_color;
	// Paper grain: two octaves of value noise plus long fibers (noise stretched along one axis).
	float g = vnoise(uv * grain_scale) * 0.65 + vnoise(uv * grain_scale * 2.7 + 13.1) * 0.35;
	float fib = vnoise(vec2(uv.x * grain_scale * 0.35, uv.y * grain_scale * 6.0) + 7.3);
	fib = smoothstep(0.62, 0.95, fib);
	base *= 1.0 + (g - 0.5) * grain_strength - fib * fiber_strength;

	// Crease lines from barycentric distance to each edge.
	vec3 b3 = vec3(v_bary.x, v_bary.y, 1.0 - v_bary.x - v_bary.y);
	vec3 fw = max(fwidth(b3), vec3(1e-5)) * crease_width;
	float darken = 0.0;
	vec3 colored = vec3(0.0);
	float colored_w = 0.0;
	for (int i = 0; i < 3; i++) {
		float code = v_codes[i];
		if (code < 0.12) {
			continue;
		}
		float m = line_mask(b3[i], fw[i]);
		if (code > 0.9) {
			darken = max(darken, m * edge_strength);
		} else if (code > 0.37) {
			bool mountain = code > 0.62;
			darken = max(darken, m * crease_strength);
			if (show_assignment > 0.5) {
				colored += (mountain ? mountain_color : valley_color) * m;
				colored_w = max(colored_w, m);
			}
		}
	}
	vec3 col = base * tint * (1.0 - darken);
	col = mix(col, colored, clamp(colored_w * 0.9, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = paper_roughness;
	SPECULAR = paper_specular;
	METALLIC = metallic_amount;
	// Soft sheen on grazing angles reads as paper fuzz without extra passes.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = col * (fres * sheen + emission_amount);
}
