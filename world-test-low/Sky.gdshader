shader_type sky;
render_mode use_half_res_pass;

group_uniforms base_gradient;
uniform vec3 top_color : source_color = vec3(0.02, 0.11, 0.39);
uniform vec3 horizon_color : source_color = vec3(0.13, 0.12, 0.38);
uniform vec3 ground_color : source_color = vec3(0.02, 0.11, 0.39);
uniform float horizon_sharpness : hint_range(0.5, 12.0, 0.1) = 3.0;

group_uniforms sun_disc;
uniform vec3 sun_disc_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_angular_size : hint_range(0.001, 0.05, 0.001) = 0.012;
uniform float sun_edge_softness : hint_range(0.0, 0.02, 0.0005) = 0.004;
uniform float sun_corona_size : hint_range(0.01, 0.5, 0.01) = 0.09;
uniform float sun_corona_intensity : hint_range(0.0, 2.0, 0.01) = 0.6;
uniform float sun_intensity = 0.0;

group_uniforms stars;
uniform float star_coverage : hint_range(0.0, 0.2, 0.001) = 0.015;
uniform float star_max_size : hint_range(0.05, 0.9, 0.01) = 0.35;

group_uniforms moon;
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform vec3 moon_disc_color : source_color = vec3(0.85, 0.87, 0.92);
uniform float moon_angular_size : hint_range(0.001, 0.05, 0.001) = 0.009;
uniform float moon_edge_softness : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float moon_corona_size : hint_range(1.0, 4.0, 0.1) = 1.6;
uniform float moon_corona_intensity : hint_range(0.0, 2.0, 0.01) = 0.35;
uniform float moon_phase : hint_range(0.0, 1.0, 0.001) = 0.5;

group_uniforms airglow;
uniform vec3 airglow_color : source_color = vec3(0.10, 0.35, 0.30);
uniform float airglow_intensity : hint_range(0.0, 2.0, 0.01) = 0.0;
uniform float airglow_band_height : hint_range(0.01, 1.0, 0.01) = 0.18;
uniform float airglow_sharpness : hint_range(0.5, 8.0, 0.1) = 2.5;
uniform float elapsed_time = 0.0;

group_uniforms weather;
uniform vec3 weather_top_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 weather_horizon_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float weather_weight : hint_range(0.0, 1.0, 0.001) = 0.0;

uniform sampler2D cloud_noise_texture;
uniform float cloud_displacement = 0.0;

vec3 draw_sun(vec3 dir) {
float d = distance(dir, LIGHT0_DIRECTION);
float disc = 1.0 - smoothstep(sun_angular_size - sun_edge_softness, sun_angular_size, d);
float corona = pow(1.0 - clamp(d / sun_corona_size, 0.0, 1.0), 3.0) * sun_corona_intensity * clamp(LIGHT0_ENERGY, 0.0, 1.5);
return sun_disc_color * (disc + corona);
}

vec3 draw_moon(vec3 dir) {
float glow_radius = moon_angular_size * moon_corona_size;
float d = distance(dir, moon_direction);
if (d > glow_radius) return vec3(0.0);

vec3 f = normalize(moon_direction);
vec3 r = normalize(cross(f, vec3(0.0, 1.0, 0.0)));
if (length(r) < 0.001) r = normalize(cross(f, vec3(1.0, 0.0, 0.0)));
vec3 u = cross(r, f);

vec3 local = dir - f * dot(dir, f);
float x = dot(local, r) / max(moon_angular_size, 0.0001);
float y = dot(local, u) / max(moon_angular_size, 0.0001);
float z = sqrt(max(0.0, 1.0 - x * x - y * y));

vec3 sun_local = vec3(-sin(moon_phase * TAU), 0.0, -cos(moon_phase * TAU));
float ndotl = x * sun_local.x + z * sun_local.z;
float lit = smoothstep(-0.05, 0.05, ndotl);

float edge_soft = moon_angular_size * moon_edge_softness;
float mask = 1.0 - smoothstep(moon_angular_size - edge_soft, moon_angular_size, d);
float corona = pow(1.0 - clamp(d / glow_radius, 0.0, 1.0), 3.0) * moon_corona_intensity * lit;

// Progressive atmospheric washout curve tied to sun intensity:
// Stays fully opaque (1.0) during night and twilight, 
// then smoothly fades out completely as the sun approaches midday glare.
float moon_opacity = 1.0 - smoothstep(0.2, 0.8, sun_intensity);

return moon_disc_color * (mask * lit + corona) * moon_opacity;
}

// Reusable hash for procedural stars/constellations later
float hash(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

// --- FIXED STARFIELD (World-Space Coordinates) ---
vec3 draw_stars(vec3 dir) {
    // --- NIGHT ONLY ---
    float night = 1.0 - smoothstep(0.05, 0.2, sun_intensity);
    if (night <= 0.0) return vec3(0.0);

    // --- CONVERT TO SPHERICAL COORDINATES (World-Space) ---
    float theta = acos(dir.y);      // Polar angle [0, π]
    float phi   = atan(dir.z, dir.x); // Azimuthal angle [-π, π]
    if (phi < 0.0) phi += TAU;      // Normalize to [0, 2π]

    // --- FIXED STAR POSITIONS (Predefined, Not Random) ---
    // Use a Fibonacci sphere algorithm for even distribution
    const float golden_ratio = 1.61803398875;
    const int total_stars = 500; // Adjust for density (500 = sparse, 2000 = dense)

    // Calculate the closest star's angular distance
    float closest_dist = 1.0;
    for (int i = 0; i < 50; i++) { // Check 50 nearest stars (performance-friendly)
        float star_theta = acos(1.0 - 2.0 * float(i) / float(total_stars));
        float star_phi   = float(i) * TAU * golden_ratio;
        float dist = distance(vec2(phi, theta), vec2(star_phi, star_theta));
        if (dist < closest_dist) closest_dist = dist;
    }

    // --- RENDER STAR IF CLOSE ENOUGH ---
    float star_size = 0.02; // Angular size (adjust for brightness)
    if (closest_dist > star_size) return vec3(0.0);

    // --- INTENSITY & COLOR (Fixed, No Randomization) ---
    float intensity = smoothstep(star_size, 0.0, closest_dist) * night;
    vec3 color = vec3(0.95, 0.90, 0.85); // Warm white (realistic star color)

    return color * intensity * 0.8; // Brightness clamped to realistic levels
}

vec3 draw_airglow(vec3 dir) {
if (airglow_intensity <= 0.0) return vec3(0.0);
float t = elapsed_time;

// Green airglow: decays smoothly across the continuous dusk-to-dawn progression
float green_band = pow(1.0 - clamp(abs(dir.y) / airglow_band_height, 0.0, 1.0), airglow_sharpness);
float green_decay = clamp(1.0 - (t / TAU), 0.2, 1.0);
vec3 green_glow = vec3(0.12, 0.42, 0.32) * green_band * green_decay;

// Red airglow: peaks post-sunset and around midnight, cleanly fading out toward dawn
float red_band = pow(1.0 - clamp(abs(dir.y) / (airglow_band_height * 1.4), 0.0, 1.0), airglow_sharpness * 0.75);
float red_peak = max(0.0, sin(t * 2.0)) * 0.9;
vec3 red_glow = vec3(0.65, 0.18, 0.08) * red_band * red_peak;

// Gravity waves: fluid wave progression across night slots
float gravity_waves = 1.0 + 0.3 * sin(dir.x * 12.0 + t * 2.0) * cos(dir.z * 12.0 - t * 1.5);

return (green_glow + red_glow) * airglow_intensity * gravity_waves;
}

vec2 parallax_uv(vec2 uv, vec3 dir) {
    if (cloud_displacement <= 0.0) return uv;
    vec2 offset = dir.xz * cloud_displacement;
    vec2 delta = offset / 4.0;
    vec2 current_uv = uv;
    for (int i = 0; i < 4; i++) {
        float height = texture(cloud_noise_texture, current_uv).a;
        if (height < float(i) / 4.0) break;
        current_uv += delta;
    }
    return current_uv;
}

void sky() {
vec3 dir = EYEDIR;
vec3 col = mix(
    mix(top_color, weather_top_color, weather_weight),
    mix(horizon_color, weather_horizon_color, weather_weight),
    pow(1.0 - abs(dir.y), horizon_sharpness));

// --- SSDM CLOUDS (4 lines) ---
if (cloud_displacement > 0.0) {
    vec2 uv = vec2(0.5 + 0.5 * atan(dir.z, dir.x) / PI, 0.5 - 0.5 * dir.y);
    vec2 displaced_uv = parallax_uv(uv, dir);
    col = mix(col, texture(cloud_noise_texture, displaced_uv).rgb, weather_weight);
}

if (dir.y < 0.0) {
col = mix(col, mix(ground_color, weather_horizon_color, weather_weight), clamp(-dir.y * 2.0, 0.0, 1.0));
}

if (!AT_CUBEMAP_PASS) {
    col += draw_airglow(dir) + draw_sun(dir) + draw_moon(dir) + draw_stars(dir);
    col = clamp(col, vec3(0.0), vec3(1.0));
}

COLOR = col;
}