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
    vec2 pos = FlutterFragCoord().xy;
    vec2 uv = pos / uSize;
    
    // Animate the glass using uTime
    float t = uTime * 0.5; 
    
    // Simulate glass unevenness using smooth sine waves flowing over time
    vec2 smoothNoise = vec2(
        sin(uv.y * 10.0 + t) + cos(uv.x * 8.0 - t),
        cos(uv.x * 12.0 + t) - sin(uv.y * 9.0 - t)
    ) * 0.5;
    
    // Glass edge distortion
    vec2 center = vec2(0.5, 0.5);
    vec2 dir = uv - center;
    float dist = length(dir);
    float edgeDistortion = pow(dist * 2.0, 3.0); 
    
    vec2 offset = smoothNoise * uStrength + (dir * edgeDistortion * uStrength * 0.5);
    
    // Chromatic aberration
    float rOffset = uChromaticAberration;
    float gOffset = uChromaticAberration * 0.5;
    float bOffset = -uChromaticAberration;
    
    vec2 globalCoord = pos + uOffset;
    vec2 baseUv = globalCoord / uScreenSize;
    
    // Scale UV slightly towards center to avoid sampling outside bounds (black edges)
    vec2 scaledUv = (baseUv - 0.5) * 0.92 + 0.5;
    
    vec2 uvR = scaledUv + offset * (1.0 + rOffset);
    vec2 uvG = scaledUv + offset * (1.0 + gOffset);
    vec2 uvB = scaledUv + offset * (1.0 + bOffset);
    
    // Aggressive clamp to ensure we NEVER hit the black padding created by Flutter's BackdropFilter
    float r = texture(uTexture, clamp(uvR, 0.05, 0.95)).r;
    float g = texture(uTexture, clamp(uvG, 0.05, 0.95)).g;
    float b = texture(uTexture, clamp(uvB, 0.05, 0.95)).b;
    
    vec4 baseColor = vec4(r, g, b, 1.0);
    
    // Add dynamic luminous reflection on the peaks
    float highlight = max(0.0, sin(uv.y * 20.0 + uv.x * 20.0 + t * 2.0) * 0.04);
    baseColor.rgb += highlight;
    
    fragColor = baseColor;
}
