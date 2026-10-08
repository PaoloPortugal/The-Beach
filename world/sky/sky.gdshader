// The sky (W09): a gradient from the horizon up, the sun's disc and,
// opposite it, the moon's, and stars by night. DayNight sets every
// colour by the time of day and the weather; this only draws them.
shader_type sky;

uniform vec3 top_colour : source_color = vec3(0.32, 0.56, 0.86);
uniform vec3 horizon_colour : source_color = vec3(0.66, 0.8, 0.9);
// Toward the sun; the moon is opposite.
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_colour : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 moon_colour : source_color = vec3(0.86, 0.9, 1.0);
// 0 by day, 1 on a clear night.
uniform float stars = 0.0;
// How much the sun and moon show through the cloud: 1 clear.
uniform float discs = 1.0;

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = EYEDIR;
	// Up from the horizon; below it, the horizon's colour (the sea hides it).
	float up = clamp(d.y, 0.0, 1.0);
	vec3 c = mix(horizon_colour, top_colour, 1.0 - exp(-up * 6.0));

	// Sun: a disc with a soft glow, low-poly plain.
	vec3 sun = normalize(sun_direction);
	float s = dot(d, sun);
	c += sun_colour * (smoothstep(0.9990, 0.9993, s) * 1.2 + pow(max(s, 0.0), 60.0) * 0.25) * discs;
	// Moon: a pale disc where the sun isn't.
	float m = dot(d, -sun);
	c = mix(c, moon_colour, smoothstep(0.9993, 0.9995, m) * discs);

	// Stars: one in a few hundred direction cells, fading at the horizon.
	if (stars > 0.0 && d.y > 0.0) {
		vec3 p = d * 160.0;
		vec3 cell = floor(p);
		float h = hash(cell);
		if (h > 0.994) {
			vec3 centre = cell + 0.5 + (vec3(hash(cell + 1.7), hash(cell + 4.1), hash(cell + 9.3)) - 0.5) * 0.6;
			float star = smoothstep(0.22, 0.05, length(p - centre));
			c += vec3(star * stars * smoothstep(0.0, 0.25, d.y) * (0.5 + 0.5 * hash(cell + 2.3)));
		}
	}
	COLOR = c;
}
