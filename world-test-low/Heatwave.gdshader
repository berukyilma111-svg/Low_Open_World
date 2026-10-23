shader_type canvas_item;

global uniform float heatwave_intensity;
global uniform float heatwave_frequency;
global uniform float heatwave_speed;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    // 1. Declare UV variable first so it can be used in the math below
    vec2 uv = SCREEN_UV;
    
    // 2. Calculate the base noise
    float wave1 = sin(uv.y * heatwave_frequency - TIME * heatwave_speed);
    float wave2 = sin(uv.x * (heatwave_frequency * 0.7) - TIME * (heatwave_speed * 1.2));
    float organic_noise = wave1 * wave2;
    
    // 3. Apply the distortion (Keep this multiplier small for visual fidelity)
    float distort_strength = 0.005; 
    uv.x += organic_noise * heatwave_intensity * distort_strength;
    uv.y += (organic_noise * heatwave_intensity * distort_strength * 0.3);
    
    COLOR = texture(screen_texture, uv);
}