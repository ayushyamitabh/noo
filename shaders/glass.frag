#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

// "True glass" backdrop filter, run through ImageFilter.shader. The engine
// fills the first vec2 with the size of the backdrop region and binds the
// first sampler to the pixels behind the widget.
uniform vec2 uSize;
uniform float uRadius;      // corner radius in px (clamped to half the short side)
uniform float uBevel;       // width of the curved glass edge in px
uniform float uRefraction;  // max edge displacement in px
uniform float uRim;         // strength of the specular edge highlight
uniform float uFrost;       // soft-diffusion radius in px
uniform sampler2D uTex;

out vec4 fragColor;

float sdRoundBox(vec2 p, vec2 hs, float r) {
  vec2 q = abs(p) - hs + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec3 tap(vec2 px) {
  vec2 uv = clamp(px / uSize, vec2(0.002), vec2(0.998));
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uTex, uv).rgb;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 hs = uSize * 0.5;
  vec2 p = frag - hs;
  float r = min(uRadius, min(hs.x, hs.y));

  float d = sdRoundBox(p, hs, r);
  float depth = max(-d, 0.0);

  vec2 e = vec2(1.0, 0.0);
  vec2 n = vec2(
    sdRoundBox(p + e.xy, hs, r) - sdRoundBox(p - e.xy, hs, r),
    sdRoundBox(p + e.yx, hs, r) - sdRoundBox(p - e.yx, hs, r)
  );
  n = n / max(length(n), 1e-4);

  // Convex bevel: strongest at the rim, falling off quadratically inward.
  float t = clamp(1.0 - depth / max(uBevel, 1.0), 0.0, 1.0);
  float bulge = t * t;
  float disp = uRefraction * bulge;

  // Sample from further inside so the rim magnifies/bends the content, with
  // a slight per-channel split for chromatic dispersion.
  vec3 col;
  col.r = tap(frag - n * disp * 1.00).r;
  col.g = tap(frag - n * disp * 1.07).g;
  col.b = tap(frag - n * disp * 1.14).b;

  // Cheap two-ring diffusion so text/photos behind don't fight the icons.
  vec2 c = frag - n * disp * 1.07;
  vec3 soft = (tap(c + vec2(uFrost, 0.0)) + tap(c - vec2(uFrost, 0.0)) +
               tap(c + vec2(0.0, uFrost)) + tap(c - vec2(0.0, uFrost))) * 0.25;
  vec3 soft2 = (tap(c + vec2(uFrost, uFrost) * 1.7) +
                tap(c - vec2(uFrost, uFrost) * 1.7) +
                tap(c + vec2(uFrost, -uFrost) * 1.7) +
                tap(c - vec2(uFrost, -uFrost) * 1.7)) * 0.25;
  col = mix(col, (soft + soft2) * 0.5, 0.7);

  // Specular rim lit from the top-left, softer bounce from the opposite side.
  vec2 light = normalize(vec2(-0.55, -0.83));
  float facing = max(dot(n, light), 0.0) + 0.45 * max(dot(n, -light), 0.0);
  float rim = exp(-depth / 1.4) * facing;
  float glow = exp(-depth / max(uBevel * 0.8, 1.0)) * (0.35 + 0.65 * facing);
  col += uRim * (rim + 0.12 * glow);

  float a = clamp(0.5 - d, 0.0, 1.0);
  fragColor = vec4(col * a, a);
}
