#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uCornerRadius;
uniform float uDistance; // Extent of the 3D refraction (e.g. 100.0)
uniform vec2 uOffset;
uniform vec2 uScreenSize;
uniform sampler2D uTexture;

out vec4 fragColor;

// Signed Distance Function for a Rounded Box (Negative inside, positive outside)
float SD_RBox(vec2 position, vec2 halfSize, float cornerRadius) {
    position = abs(position) - halfSize + cornerRadius;
    return length(max(position, vec2(0.0))) + min(max(position.x, position.y), 0.0) - cornerRadius;
}

// Blend Screen for Specular Highlights on the glass curves
vec4 BlendScreen(vec4 dst, vec4 src, float opacity) {
    vec4 screen = vec4(1.0) - (vec4(1.0) - dst) * (vec4(1.0) - src);
    return mix(dst, screen, opacity);
}

// Fast 9-tap blur
vec4 blur(vec2 uv, vec2 resolution) {
    vec4 color = vec4(0.0);
    vec2 off1 = vec2(1.3846153846) / resolution;
    vec2 off2 = vec2(3.2307692308) / resolution;
    
    color += texture(uTexture, uv) * 0.2270270270;
    color += texture(uTexture, uv + (vec2(1.0, 0.0) * off1)) * 0.3162162162;
    color += texture(uTexture, uv - (vec2(1.0, 0.0) * off1)) * 0.3162162162;
    color += texture(uTexture, uv + (vec2(0.0, 1.0) * off1)) * 0.3162162162;
    color += texture(uTexture, uv - (vec2(0.0, 1.0) * off1)) * 0.3162162162;
    return color;
}

void main() {
    // In BackdropFilter, FlutterFragCoord().xy is the GLOBAL screen coordinate.
    vec2 fragCoord = FlutterFragCoord().xy;
    
    // 1. Convert to local coordinates for the SDF
    vec2 localCoord = fragCoord - uOffset;
    vec2 coord = localCoord - uSize * 0.5;
    
    vec2 rr_size = uSize * 0.5;
    float cornerRadius = max(uCornerRadius, 1.0);
    
    // 2. SDF for the rounded box
    float sdf = SD_RBox(coord, rr_size, cornerRadius);
    
    // Default flat normal and distortion
    vec3 n1 = vec3(0.0, 0.0, 1.0);
    float z2_z1 = 0.0;
    
    // 3. Compute 3D Normal for the Bevel (Ray-Tracing)
    float bevelWidth = min(cornerRadius, min(rr_size.x, rr_size.y));
    
    if (sdf > -bevelWidth && sdf <= 0.0) {
        vec2 e = vec2(1.0, 0.0);
        float dx = SD_RBox(coord + e.xy, rr_size, cornerRadius) - SD_RBox(coord - e.xy, rr_size, cornerRadius);
        float dy = SD_RBox(coord + e.yx, rr_size, cornerRadius) - SD_RBox(coord - e.yx, rr_size, cornerRadius);
        vec2 n2d = normalize(vec2(dx, dy));
        if (length(vec2(dx, dy)) == 0.0) n2d = vec2(0.0);
        
        float x = sdf + bevelWidth; 
        float R = bevelWidth;
        float z = sqrt(max(0.0, R*R - x*x));
        n1 = normalize(vec3(n2d * (x / R), z / R));
        z2_z1 = abs(sdf) / R * uDistance;
    }
    
    // 4. Calculate 3D Refraction using Snell's Law
    float refractionStrength = 1.0; 
    vec3 n = normalize(vec3(n1.xy * refractionStrength, -1.0));
    float ior = max(n1.z, 0.01);
    vec3 wo = normalize(refract(vec3(0.0, 0.0, -1.0), n, ior));
    
    // Distortion vector
    vec2 distortion = wo.xy * z2_z1 / uSize;
    
    // UVs for the implicit full-screen texture in BackdropFilter
    // fragCoord is ALREADY global, so we just divide by uScreenSize!
    vec2 uv = fragCoord / uScreenSize;
    vec2 uvR = uv + distortion * 1.05;
    vec2 uvG = uv + distortion * 1.00;
    vec2 uvB = uv + distortion * 0.95;
    
    // Clamp to valid texture bounds
    uvR = clamp(uvR, 0.0, 1.0);
    uvG = clamp(uvG, 0.0, 1.0);
    uvB = clamp(uvB, 0.0, 1.0);
    
    // Pass uScreenSize for the blur resolution since the implicit texture is full screen
    float r = blur(uvR, uScreenSize).r;
    float g = blur(uvG, uScreenSize).g;
    float b = blur(uvB, uScreenSize).b;
    float a = blur(uvG, uScreenSize).a;
    
    vec4 m_color = vec4(r, g, b, a);
    
    // Compute blending
    float g_fBlend = mix(0.0, 1.0, n1.z);
    float saturationBoost = mix(1.5, 1.0, g_fBlend);
    float luma = dot(m_color.rgb, vec3(0.299, 0.587, 0.114));
    m_color.rgb = mix(vec3(luma), m_color.rgb, saturationBoost);
    
    float highlightIntensity = 0.5;
    m_color = BlendScreen(m_color, vec4(1.0 - g_fBlend), highlightIntensity);
    m_color.rgb *= mix(1.0, g_fBlend, 0.3);
    
    // Discard pixels outside the widget (local coord out of bounds)
    // Actually we don't need this if ClipRRect handles it, but just in case:
    if (sdf > 0.0) {
        m_color.a = 0.0;
    }
    
    fragColor = m_color;
}
