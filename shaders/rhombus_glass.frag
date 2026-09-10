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
    
    // 3. Subtle interior zoom (5% magnification for realistic glass lens thickness)
    // Pulls sampling UVs slightly towards the center of the widget
    vec2 zoomDisplacement = -(coord / uScreenSize) * 0.05;

    // 4. 3D Bevel on the curved outer rim
    vec3 n1 = vec3(0.0, 0.0, 1.0);
    float z2_z1 = 0.0;
    float smoothFactor = 0.0;
    
    float bevelWidth = min(rr_size.y * 0.35, min(cornerRadius, 36.0));
    
    if (sdf > -bevelWidth) {
        vec2 e = vec2(1.0, 0.0);
        float dx = SD_RBox(coord + e.xy, rr_size, cornerRadius) - SD_RBox(coord - e.xy, rr_size, cornerRadius);
        float dy = SD_RBox(coord + e.yx, rr_size, cornerRadius) - SD_RBox(coord - e.yx, rr_size, cornerRadius);
        vec2 n2d = normalize(vec2(dx, dy));
        if (length(vec2(dx, dy)) == 0.0) n2d = vec2(0.0);
        
        float R = bevelWidth;
        float x = sdf + R; 
        float factor = clamp(x / R, 0.0, 1.0);
        smoothFactor = smoothstep(0.0, 1.0, factor);
        
        float z = sqrt(max(0.0, 1.0 - smoothFactor * smoothFactor));
        n1 = normalize(vec3(n2d * smoothFactor, z));

        z2_z1 = smoothFactor * uDistance;
    }
    
    // 5. 3D Refraction on the rim using Snell's Law
    const float ior = 0.75; 
    vec3 n = normalize(vec3(n1.xy, -1.0));
    vec3 wo = normalize(refract(vec3(0.0, 0.0, -1.0), n, ior));
    vec2 rimDistortion = wo.xy * z2_z1 / uScreenSize;
    
    // Combined displacement: interior zoom + 3D rim refraction
    vec2 totalDisplacement = zoomDisplacement + rimDistortion;

    // UV coordinates on the full screen texture
    vec2 baseUv = fragCoord / uScreenSize;

    // Chromatic aberration (color dispersion across the glass)
    vec2 uvR = clamp(baseUv + totalDisplacement * 1.03, 0.001, 0.999);
    vec2 uvG = clamp(baseUv + totalDisplacement * 1.00, 0.001, 0.999);
    vec2 uvB = clamp(baseUv + totalDisplacement * 0.97, 0.001, 0.999);
    
    // Sample texture (hardware-blurred by ImageFilter.compose)
    float r = texture(uTexture, uvR).r;
    float g = texture(uTexture, uvG).g;
    float b = texture(uTexture, uvB).b;
    float a = texture(uTexture, uvG).a;
    
    vec4 m_color = vec4(r, g, b, a);
    
    // Clean edge specular highlight on the 3D rim
    float highlightIntensity = 0.16;
    float edgeHighlight = smoothFactor * highlightIntensity;
    m_color.rgb += vec3(edgeHighlight);
    
    fragColor = m_color;
}
