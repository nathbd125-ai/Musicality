#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uStrength;
uniform float uChromaticAberration;
uniform float uTime;
uniform vec2 uOffset;
uniform vec2 uScreenSize;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 pos = FlutterFragCoord().xy; // Absolute screen pixel coordinates in BackdropFilter

    // 1. Calculate local position inside the widget
    vec2 localPos = pos - uOffset;

    // 2. Local UV coordinates for the widget (0.0 to 1.0)
    vec2 uv = localPos / uSize;
    
    // 3. Global UV coordinates for sampling the full screen background texture
    vec2 baseUv = pos / uScreenSize;

    // Animate the glass using uTime
    float t = uTime * 0.5; 

    // Simulate glass unevenness using smooth sine waves flowing over time
    vec2 smoothNoise = vec2(
        sin(uv.y * 10.0 + t) + cos(uv.x * 8.0 - t),
        cos(uv.x * 12.0 + t) - sin(uv.y * 9.0 - t)
    ) * 0.5;
    
    // Glass edge distortion (calculée par rapport à l'objet, donc on garde 'uv')
    vec2 center = vec2(0.5, 0.5);
    vec2 dir = uv - center;
    float dist = length(dir);
    float d = dist * 2.0;
    float edgeDistortion = d * d * d;
    
    vec2 offset = smoothNoise * uStrength + (dir * edgeDistortion * uStrength * 0.5);
    
    // Chromatic aberration
    float rOffset = uChromaticAberration;
    float gOffset = uChromaticAberration * 0.5;
    float bOffset = -uChromaticAberration;

    // Scale UV slightly towards center to avoid sampling outside bounds (black edges)
    vec2 scaledUv = (baseUv - 0.5) * 0.99 + 0.5;
    
    vec2 uvR = scaledUv + offset * (1.0 + rOffset);
    vec2 uvG = scaledUv + offset * (1.0 + gOffset);
    vec2 uvB = scaledUv + offset * (1.0 + bOffset);
    
    // Aggressive clamp to ensure we NEVER hit the black padding created by Flutter's BackdropFilter
    float r = texture(uTexture, clamp(uvR, 0.01, 0.99)).r;
    float g = texture(uTexture, clamp(uvG, 0.01, 0.99)).g;
    float b = texture(uTexture, clamp(uvB, 0.01, 0.99)).b;
    
    vec4 baseColor = vec4(r, g, b, 1.0);
    
    // Add dynamic luminous reflection on the peaks
    float highlight = max(0.0, sin((uv.y + uv.x) * 20.0 + t * 2.0) * 0.04);
    baseColor.rgb += highlight;
    
    fragColor = baseColor;
}
