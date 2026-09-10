#include <flutter/runtime_effect.glsl>

uniform vec2 uTextureSize; // Indices 0, 1 (Placeholder automatically overwritten by Flutter engine)
uniform vec2 uSize;        // Indices 2, 3 (Real widget size: width, height)
uniform float uCornerRadius; // Index 4
uniform float uDistance;   // Index 5 (Extent of the 3D refraction)
uniform vec2 uOffset;      // Indices 6, 7 (Widget screen position offset)
uniform vec2 uScreenSize;  // Indices 8, 9 (Full screen resolution)
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

// Silky-smooth Golden Spiral (Vogel) blur - Zero grid or pixelation artifacts
vec4 smoothBlur(vec2 uv, vec2 screenSize) {
    vec4 color = texture(uTexture, uv) * 0.16;
    float radius = 5.0; // Smooth blur radius in physical pixels

    float angle = 0.0;
    for (int i = 1; i <= 12; i++) {
        angle += 2.39996323; // Golden angle (137.5 degrees)
        float r = sqrt(float(i) / 12.0) * radius;
        vec2 offset = vec2(cos(angle), sin(angle)) * r / screenSize;
        color += texture(uTexture, uv + offset) * (0.12 - float(i) * 0.006);
    }

    return color;
}

void main() {
    // In BackdropFilter, FlutterFragCoord().xy is the GLOBAL screen coordinate.
    vec2 fragCoord = FlutterFragCoord().xy;
    
    // 1. Convert to local coordinates for the SDF
    vec2 localCoord = fragCoord - uOffset;
    vec2 coord = localCoord - uSize * 0.5;
    
    vec2 rr_size = uSize * 0.5;
    float cornerRadius = min(max(uCornerRadius, 1.0), min(rr_size.x, rr_size.y));
    
    // 2. SDF for the rounded box (outer clipping)
    float sdf = SD_RBox(coord, rr_size, cornerRadius);
    if (sdf > 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    
    // Default flat normal and zero distortion for the center
    vec3 n1 = vec3(0.0, 0.0, 1.0);
    float z2_z1 = 0.0;
    
    // 3. Compute 3D Normal for the Bevel (Ray-Tracing)
    // bevelWidth is capped to cornerRadius so it NEVER exceeds the corner radius
    // (eliminates the 45-degree medial axis seams and side triangle artifacts)
    float bevelWidth = cornerRadius;
    
    if (sdf > -bevelWidth) {
        vec2 e = vec2(1.0, 0.0);
        float dx = SD_RBox(coord + e.xy, rr_size, cornerRadius) - SD_RBox(coord - e.xy, rr_size, cornerRadius);
        float dy = SD_RBox(coord + e.yx, rr_size, cornerRadius) - SD_RBox(coord - e.yx, rr_size, cornerRadius);
        vec2 n2d = normalize(vec2(dx, dy));
        if (length(vec2(dx, dy)) == 0.0) n2d = vec2(0.0);
        
        // Depth parameter:
        // x = 0.0 at the inner boundary (sdf = -bevelWidth)
        // x = R at the outer rim (sdf = 0.0)
        float R = bevelWidth;
        float x = sdf + R; 
        float factor = clamp(x / R, 0.0, 1.0); // 0.0 at center, 1.0 at outer rim
        
        // 3D dome / bevel profile
        float z = sqrt(max(0.0, R * R - x * x));
        n1 = normalize(vec3(n2d * factor, z / R));

        // Refraction strength:
        // Maximum at the outer rim (factor = 1.0) where the glass curves down,
        // and smoothly drops to EXACTLY ZERO at the center (factor = 0.0).
        // This ensures the top and bottom bevels smoothly meet at 0 without any cut or line in the middle!
        z2_z1 = factor * uDistance;
    }
    
    // 4. Calculate 3D Refraction using Snell's Law
    float refractionStrength = 1.0; 
    vec3 n = normalize(vec3(n1.xy * refractionStrength, -1.0));
    float ior = max(n1.z, 0.01);
    vec3 wo = normalize(refract(vec3(0.0, 0.0, -1.0), n, ior));
    
    // Distortion vector in Screen UV coordinates
    vec2 distortion = wo.xy * z2_z1 / uScreenSize;
    
    // UVs for the implicit full-screen texture in BackdropFilter
    vec2 baseUv = fragCoord / uScreenSize;

    vec2 uvR = baseUv + distortion * 1.05;
    vec2 uvG = baseUv + distortion * 1.00;
    vec2 uvB = baseUv + distortion * 0.95;
    
    // Clamp to valid texture bounds
    uvR = clamp(uvR, 0.001, 0.999);
    uvG = clamp(uvG, 0.001, 0.999);
    uvB = clamp(uvB, 0.001, 0.999);
    
    // Sample with multi-tap GLSL blur and chromatic aberration offsets
    float r = smoothBlur(uvR, uScreenSize).r;
    float g = smoothBlur(uvG, uScreenSize).g;
    float b = smoothBlur(uvB, uScreenSize).b;
    float a = smoothBlur(uvG, uScreenSize).a;
    
    vec4 m_color = vec4(r, g, b, a);
    
    // Clean, vibrant color blending + subtle edge specular highlight along the curved glass rims
    float g_fBlend = mix(0.0, 1.0, n1.z);
    float highlightIntensity = 0.12;
    float edgeHighlight = (1.0 - g_fBlend) * highlightIntensity;
    m_color.rgb += vec3(edgeHighlight);
    
    fragColor = m_color;
}
