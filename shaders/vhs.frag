#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uShift;
uniform float uNoise;
uniform sampler2D uTexture;

out vec4 fragColor;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;

    // 1. Tremor horizontal proporcional ao ruído
    float jitter = (rand(vec2(uTime, uv.y)) - 0.5) * (uNoise * 0.03);
    uv.x += jitter;

    // 2. Aberração Cromática dinâmica
    float r = texture(uTexture, uv + vec2(uShift, 0.0)).r;
    float g = texture(uTexture, uv).g;
    float b = texture(uTexture, uv - vec2(uShift, 0.0)).b;
    vec3 color = vec3(r, g, b);

    // 3. Scanlines
    float scanline = sin(uv.y * uSize.y * 1.5) * 0.08;
    color -= scanline;

    // 4. Chuvisco dinâmico
    float noise = (rand(uv + fract(uTime)) - 0.5) * uNoise;
    color += noise;

    // 5. Vinheta
    float vignette = smoothstep(0.9, 0.3, length(uv - 0.5));
    color *= mix(0.7, 1.0, vignette);

    fragColor = vec4(color, 1.0);
}
