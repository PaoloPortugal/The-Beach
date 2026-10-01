// Flat-shaded low-poly ocean with gentle waves (W02). The waves move the
// vertices; the normals come from screen-space derivatives, so every
// triangle is lit flat. Plain enough for the Compatibility renderer.
shader_type spatial;

uniform vec4 water_colour : source_color = vec4(0.10, 0.52, 0.66, 1.0);
uniform vec4 crest_colour : source_color = vec4(0.30, 0.74, 0.80, 1.0);
uniform float wave_height = 0.35;
uniform float wave_length = 14.0;
uniform float wave_speed = 0.8;

varying float height;

float waves(vec2 p, float t) {
	float k = 6.2831853 / wave_length;
	return sin(dot(p, vec2(0.8, 0.6)) * k + t * wave_speed)
		+ 0.6 * sin(dot(p, vec2(-0.5, 0.9)) * k * 1.7 + t * wave_speed * 1.3)
		+ 0.3 * sin(dot(p, vec2(0.2, -1.0)) * k * 2.9 + t * wave_speed * 1.9);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	height = waves(world.xz, TIME) / 1.9;
	VERTEX.y += height * wave_height;
}

void fragment() {
	NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	ALBEDO = mix(water_colour.rgb, crest_colour.rgb, clamp(height * 0.5 + 0.5, 0.0, 1.0));
	ROUGHNESS = 0.45;
	SPECULAR = 0.3;
}
