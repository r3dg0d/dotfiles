// green-crt.glsl — subtle monochrome-green CRT look for Ghostty.
// Loaded via `custom-shader = shaders/green-crt.glsl` in config.ghostty;
// comment out that line to disable this shader entirely (theme colors
// still apply on their own). Runs as a single Shadertoy-style pass over
// the already-rendered terminal texture (iChannel0) — one texel fetch
// plus one small offset fetch for the glow, kept cheap on purpose.

// ---- tunable constants -------------------------------------------------
const float SCANLINE_INTENSITY = 0.12;   // 0 = off, higher = darker lines
const float SCANLINE_COUNT_MUL = 1.0;    // scanline density multiplier
const float GLOW_STRENGTH      = 0.18;   // 0 = off, phosphor bloom amount
const float VIGNETTE_STRENGTH  = 0.35;   // 0 = off, edge darkening amount
const float CURVATURE_AMOUNT   = 0.020;  // 0 = off, barrel-warp amount
const float BRIGHTNESS         = 1.05;   // overall output multiplier

vec2 crtCurve(vec2 uv) {
    // Cheap barrel distortion around the center, softened by CURVATURE_AMOUNT.
    vec2 centered = uv * 2.0 - 1.0;
    float r2 = dot(centered, centered);
    centered *= 1.0 + CURVATURE_AMOUNT * r2;
    return centered * 0.5 + 0.5;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;
    vec2 curvedUv = crtCurve(uv);

    // Outside the curved bounds: render black instead of sampling garbage.
    if (curvedUv.x < 0.0 || curvedUv.x > 1.0 || curvedUv.y < 0.0 || curvedUv.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    vec3 color = texture(iChannel0, curvedUv).rgb;

    // Cheap phosphor glow: one extra sample softly added back in.
    vec3 glowSample = texture(iChannel0, curvedUv + vec2(0.0015, 0.0015)).rgb;
    color += glowSample * GLOW_STRENGTH * 0.5;

    // Fine scanlines.
    float scanline = sin(curvedUv.y * iResolution.y * 3.14159 * SCANLINE_COUNT_MUL);
    color *= 1.0 - SCANLINE_INTENSITY * (0.5 + 0.5 * scanline);

    // Faint vignette.
    vec2 fromCenter = curvedUv - 0.5;
    float vignette = 1.0 - VIGNETTE_STRENGTH * dot(fromCenter, fromCenter) * 2.0;
    color *= clamp(vignette, 0.0, 1.0);

    color *= BRIGHTNESS;

    fragColor = vec4(color, 1.0);
}
