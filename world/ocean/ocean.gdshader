// Flat-shaded low-poly ocean with gentle waves (W02), see-through and
// tinted by depth (W08): clear turquoise over the shallows, deep blue over
// deep water. The waves move the vertices; the normals come from
// screen-space derivatives, so every triangle is lit flat. The depth under
// the surface comes from the depth buffer, which both renderers have.
// The weather (W09) sets how far the waves have moved (wind makes them
// faster and a little higher; ocean.gd keeps the phase so a change of
// speed doesn't jump them) and rain rings on the surface.
shader_type spatial;
render_mode cull_disabled, depth_draw_always;

uniform vec4 shallow_colour : source_color = vec4(0.35, 0.85, 0.80, 1.0);
uniform vec4 water_colour : source_color = vec4(0.10, 0.52, 0.66, 1.0);
uniform vec4 deep_colour : source_color = vec4(0.03, 0.20, 0.40, 1.0);
uniform vec4 crest_colour : source_color = vec4(0.30, 0.74, 0.80, 1.0);
// Seen from below (W08's underwater view).
uniform vec4 underside_colour : source_color = vec4(0.45, 0.75, 0.85, 1.0);
// Depth (vertical, metres) at which the water is fully deep_colour;
// water_colour comes at a quarter of it.
uniform float deep_depth = 20.0;
// How quickly the water hides what's under it, per metre seen through.
uniform float clarity = 0.18;
// The clearest the water gets, so the surface always shows.
uniform float min_alpha = 0.25;
uniform float wave_height = 0.35;
uniform float wave_length = 14.0;
// How far the waves have moved: time times their speed (ocean.gd).
uniform float wave_phase = 0.0;
// Rain on the water, 0 to 1: rings where drops land.
uniform float rain = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying float height;
varying vec2 world_xz;

float waves(vec2 p, float phase) {
	float k = 6.2831853 / wave_length;
	return sin(dot(p, vec2(0.8, 0.6)) * k + phase)
		+ 0.6 * sin(dot(p, vec2(-0.5, 0.9)) * k * 1.7 + phase * 1.3)
		+ 0.3 * sin(dot(p, vec2(0.2, -1.0)) * k * 2.9 + phase * 1.9);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Rain rings: one spreading ring at a time in some of the 1.2 m cells,
// each at its own moment, as many cells as it's raining hard.
float rings(vec2 p, float t) {
	vec2 cell = floor(p / 1.2);
	float h = hash(cell);
	if (h > rain) {
		return 0.0;
	}
	vec2 centre = (cell + 0.3 + 0.4 * vec2(hash(cell + 7.1), hash(cell + 3.7))) * 1.2;
	float age = fract(t * 1.3 + h * 17.0);
	float ring = 1.0 - smoothstep(0.0, 0.035, abs(length(p - centre) - age * 0.5));
	return ring * (1.0 - age);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_xz = world.xz;
	height = waves(world.xz, wave_phase) / 1.9;
	VERTEX.y += height * wave_height;
}

void fragment() {
	NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	ROUGHNESS = 0.45;
	SPECULAR = 0.3;
	if (!FRONT_FACING) {
		// From under the water: a bright, mostly opaque ceiling.
		NORMAL = -NORMAL;
		ALBEDO = underside_colour.rgb;
		ALPHA = 0.8;
	} else {
		// What's behind this pixel, back in view space.
		float raw = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(SCREEN_UV, raw) * 2.0 - 1.0;
#else
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
#endif
		vec4 behind = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		behind.xyz /= behind.w;
		float floor_y = (INV_VIEW_MATRIX * vec4(behind.xyz, 1.0)).y;
		float surface_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
		float d = clamp((surface_y - floor_y) / deep_depth, 0.0, 1.0);
		vec3 tint = d < 0.25 ? mix(shallow_colour.rgb, water_colour.rgb, d / 0.25)
			: mix(water_colour.rgb, deep_colour.rgb, (d - 0.25) / 0.75);
		ALBEDO = mix(tint, crest_colour.rgb, clamp(height * 0.5 + 0.5, 0.0, 1.0) * 0.35);
		if (rain > 0.0) {
			ALBEDO = mix(ALBEDO, vec3(0.85, 0.92, 0.95), rings(world_xz, TIME) * 0.5);
		}
		float through = max(length(behind.xyz) - length(VERTEX), 0.0);
		ALPHA = clamp(1.0 - exp(-through * clarity), min_alpha, 1.0);
	}
}
