#include <flutter/runtime_effect.glsl>

uniform vec2 uTextureSize; // Indices 0, 1 (Placeholder automatically overwritten by Flutter engine)
uniform vec2 uSize;        // Indices 2, 3 (Real widget size: width, height)
uniform float uCornerRadius; // Index 4
uniform float uDistance;   // Index 5 (Max refraction strength at top, in physical pixels)
uniform vec2 uOffset;      // Indices 6, 7 (Widget screen position offset)
uniform vec2 uScreenSize;  // Indices 8, 9 (Full screen resolution)
uniform sampler2D uTexture;

out vec4 fragColor;

// Signed Distance Function for a Rounded Box (Negative inside, positive outside)
float SD_RBox(vec2 position, vec2 halfSize, float cornerRadius) {
    position = abs(position) - halfSize + cornerRadius;
    return length(max(position, vec2(0.0))) + min(max(position.x, position.y), 0.0) - cornerRadius;
}

// Silky-smooth Golden Spiral (Vogel) blur - Zero grid or pixelation artifacts
vec4 smoothBlur(vec2 uv, vec2 screenSize) {
    vec4 color = texture(uTexture, uv) * 0.16;
    float radius = 5.0;
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

    // 1. Convert to local coordinates
    vec2 localCoord = fragCoord - uOffset;
    vec2 coord = localCoord - uSize * 0.5;
    vec2 rr_size = uSize * 0.5;
    float cornerRadius = max(uCornerRadius, 1.0);

    // 2. SDF to clip outside the rounded box
    float sdf = SD_RBox(coord, rr_size, cornerRadius);
    if (sdf > 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // 3. Full-widget glass distortion (tilted glass panel):
    //    - Top of widget → maximum upward refraction (shows content from above)
    //    - Bottom of widget → zero refraction (straight through)
    //    This creates ONE continuous glass surface instead of two separate edge bands.
    float normalizedY = localCoord.y / uSize.y; // 0 = top, 1 = bottom

    // Smooth ease-out so the top edge has peak distortion and it fades naturally
    float refractionT = 1.0 - normalizedY;
    refractionT = refractionT * refractionT; // Quadratic ease-in (stronger at top)

    // Horizontal curvature: slight outward lens distortion on left/right sides
    float normalizedX = (localCoord.x / uSize.x - 0.5) * 2.0; // -1..+1

    vec2 distortion = vec2(
        normalizedX * refractionT * uDistance * 0.25 / uScreenSize.x,
        -refractionT * uDistance / uScreenSize.y
    );

    // 4. Chromatic aberration + sample with Vogel blur
    vec2 baseUv = fragCoord / uScreenSize;
    vec2 uvR = clamp(baseUv + distortion * 1.05, 0.001, 0.999);
    vec2 uvG = clamp(baseUv + distortion * 1.00, 0.001, 0.999);
    vec2 uvB = clamp(baseUv + distortion * 0.95, 0.001, 0.999);

    float r = smoothBlur(uvR, uScreenSize).r;
    float g = smoothBlur(uvG, uScreenSize).g;
    float b = smoothBlur(uvB, uScreenSize).b;
    float a = smoothBlur(uvG, uScreenSize).a;

    vec4 m_color = vec4(r, g, b, a);

    // 5. Subtle top specular highlight (simulates light hitting the glass from above)
    float topHighlight = refractionT * 0.10;
    m_color.rgb += vec3(topHighlight);

    fragColor = m_color;
}
