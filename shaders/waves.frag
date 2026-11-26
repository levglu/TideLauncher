#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    vec4 colTop;
    vec4 colBottom;
    vec4 colWave;
};

const float PI = 3.14159265;

// Шёлковая лента: множество тонких линий, разведённых по ширине,
// ширина меняет знак вдоль x — лента «перекручивается».
vec2 ribbon(vec2 p, float base, float amp, float freq, float speed, float phase,
            float twistF, float twistS, float spread) {
    float c = base
        + amp * sin(p.x * freq + time * speed + phase)
        + amp * 0.5 * sin(p.x * freq * 1.9 - time * speed * 0.6 + phase * 2.1);
    float w = spread * sin(p.x * twistF + time * twistS + phase * 0.7);
    float lines = 0.0;
    const int N = 26;
    for (int i = 0; i < N; i++) {
        float t = float(i) / float(N - 1);
        float y = c + w * (t - 0.5);
        float d = p.y - y;
        float k = 0.6 + 0.4 * sin(t * PI);
        lines += exp(-d * d / 0.000006) * k;
    }
    float glowW = w * w * 0.25 + 0.0016;
    float glow = exp(-(p.y - c) * (p.y - c) / glowW);
    return vec2(lines, glow);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = vec2(uv.x * aspect, uv.y);

    // фон: светлее в центре-сверху, темнее к краям и низу
    vec3 col = mix(colTop.rgb, colBottom.rgb, smoothstep(0.05, 1.0, uv.y));
    float rad = length((uv - vec2(0.55, 0.38)) * vec2(1.0, 1.4));
    col *= 1.06 - 0.28 * smoothstep(0.1, 1.1, rad);
    // широкие светлые полупрозрачные «листы» в верхней части
    float s1 = uv.y - (0.02 + 0.55 * pow(abs(uv.x - 0.35), 1.6) + 0.03 * sin(uv.x * 3.0 + time * 0.05));
    col += colWave.rgb * smoothstep(0.08, 0.0, abs(s1)) * 0.07;
    col += colWave.rgb * smoothstep(0.0, -0.25, s1) * 0.06;

    vec2 a = ribbon(p, 0.60, 0.060, 1.15, 0.090, 0.0, 0.85, 0.050, 0.17);
    vec2 b = ribbon(p, 0.66, 0.050, 0.95, -0.070, 2.3, 1.10, -0.040, 0.12);
    vec2 c = ribbon(p, 0.53, 0.035, 1.55, 0.055, 4.1, 1.40, 0.060, 0.07);

    float edge = smoothstep(-0.05, 0.35, uv.x) * smoothstep(1.05, 0.65, uv.x) * 0.55 + 0.45;
    vec3 wave = colWave.rgb;
    col += wave * (a.y * 0.14 + b.y * 0.10 + c.y * 0.07);
    col += wave * (a.x * 0.09 + b.x * 0.07 + c.x * 0.05) * edge;

    // мягкое боке
    vec2 g = p * vec2(9.0, 6.0) + vec2(time * 0.02, -time * 0.035);
    vec2 id = floor(g);
    vec2 f = fract(g) - 0.5;
    float h = hash(id);
    if (h > 0.86) {
        vec2 o = vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5;
        float r = 0.10 + 0.18 * hash(id + 1.3);
        float d = length(f - o * 0.5);
        float tw = 0.5 + 0.5 * sin(time * (0.6 + h) + h * 40.0);
        col += wave * smoothstep(r, r * 0.3, d) * 0.10 * tw * (1.0 - uv.y * 0.3);
    }

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
