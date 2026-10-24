shader_type sky;

// Blind executor: draws whatever DayScript / NightScript hand it. They send a "from" and a "to"
// sky plus how far along the blend is; nothing here knows the time, season or weather.

group_uniforms sky_state;
uniform vec3 from_top : source_color = vec3(0.02, 0.11, 0.39);
uniform vec3 from_horizon : source_color = vec3(0.13, 0.12, 0.38);
uniform vec3 to_top : source_color = vec3(0.02, 0.11, 0.39);
uniform vec3 to_horizon : source_color = vec3(0.13, 0.12, 0.38);
uniform float sky_blend : hint_range(0.0, 1.0) = 0.0;
uniform float horizon_sharpness : hint_range(0.5, 12.0, 0.1) = 3.0;

group_uniforms sun_disc;
uniform vec3 sun_disc_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_angular_size : hint_range(0.001, 0.05, 0.001) = 0.012;
uniform float sun_edge_softness : hint_range(0.0, 0.02, 0.0005) = 0.004;
uniform float sun_corona_size : hint_range(0.01, 0.5, 0.01) = 0.09;
uniform float sun_corona_intensity : hint_range(0.0, 2.0, 0.01) = 0.6;
uniform vec3 sun_low_tint : source_color = vec3(1.0, 0.45, 0.2);
uniform float sun_intensity = 0.0;
// Fed by DayScript once a minute: x = midday glare, y = corona scale (distance, heat shimmer, haze), z = haze
uniform vec3 sun_state = vec3(0.0, 1.0, 0.0);

group_uniforms moon;
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform vec3 moon_disc_color : source_color = vec3(0.85, 0.87, 0.92);
uniform float moon_angular_size : hint_range(0.001, 0.05, 0.001) = 0.009;
uniform float moon_edge_softness : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float moon_corona_size : hint_range(1.0, 4.0, 0.1) = 1.6;
uniform float moon_corona_intensity : hint_range(0.0, 2.0, 0.01) = 0.35;
uniform float moon_phase : hint_range(0.0, 1.0, 0.001) = 0.5;

// The sun's height comes straight from the light, so a low sun is crisp and tinted and a high
// sun is soft and white without the scripts sending anything.
vec3 apply_sun(vec3 col, vec3 dir) {
	if (!LIGHT0_ENABLED) return col;
	float glare = sun_state.x;
	float soft = smoothstep(0.05, 0.25, LIGHT0_DIRECTION.y);
	vec3 disc_col = mix(sun_low_tint, sun_disc_color, smoothstep(0.0, 0.3 + 0.3 * sun_state.z, LIGHT0_DIRECTION.y));
	if (glare > 0.0) {
		// Midday glare whitens the sky around the sun
		float toward = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		toward *= toward * toward;
		col = mix(col, disc_col, glare * 0.15 * toward * toward);
	}
	float corona_size = sun_corona_size * sun_state.y * (1.0 + glare);
	float d = distance(dir, LIGHT0_DIRECTION);
	if (d > max(2.0 * corona_size, 3.0 * sun_angular_size)) return col;

	float energy = clamp(LIGHT0_ENERGY, 0.0, 1.5);
	float edge = mix(sun_edge_softness, 0.8 * sun_angular_size, soft);
	float disc = 1.0 - smoothstep(sun_angular_size - edge, sun_angular_size + edge * 0.5, d);
	float bloom = max(1.0 - d / (3.0 * sun_angular_size), 0.0);
	bloom *= bloom * soft * energy;
	float crisp = max(1.0 - d / corona_size, 0.0);
	float tail = max(1.0 - d / (2.0 * corona_size), 0.0);
	tail *= tail * tail;
	float corona = mix(crisp * crisp * crisp, tail * tail, soft) * sun_corona_intensity * energy;
	// Painted over the sky, so a low red sun really shows red
	return mix(col, disc_col, disc) + disc_col * (corona + bloom);
}

vec3 draw_moon(vec3 dir) {
	float glow_radius = moon_angular_size * moon_corona_size;
	float d = distance(dir, moon_direction);
	if (d > glow_radius) return vec3(0.0);

	vec3 r = normalize(cross(moon_direction, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
	vec3 u = cross(r, moon_direction);
	vec3 local = dir - moon_direction * dot(dir, moon_direction);
	float x = dot(local, r) / moon_angular_size;
	float y = dot(local, u) / moon_angular_size;
	float z = sqrt(max(0.0, 1.0 - x * x - y * y));

	float lit = smoothstep(-0.05, 0.05, -x * sin(moon_phase * TAU) - z * cos(moon_phase * TAU));
	float mask = 1.0 - smoothstep(moon_angular_size * (1.0 - moon_edge_softness), moon_angular_size, d);
	float corona = pow(1.0 - d / glow_radius, 3.0) * moon_corona_intensity * lit;
	// Washes out as the sun climbs toward midday
	float opacity = 1.0 - smoothstep(0.2, 0.8, sun_intensity);
	return moon_disc_color * (mask * lit + corona) * opacity;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 top = mix(from_top, to_top, sky_blend);
	vec3 col = mix(top, mix(from_horizon, to_horizon, sky_blend), pow(1.0 - abs(dir.y), horizon_sharpness));
	if (dir.y < 0.0) {
		col = mix(col, top, min(-dir.y * 2.0, 1.0));
	} else if (!AT_CUBEMAP_PASS) {
		col = apply_sun(col, dir) + draw_moon(dir);
		col = min(col, vec3(1.0));
	}
	COLOR = col;
}
