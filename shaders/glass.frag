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
  // No y-flip on GLES: despite the ImageFilter.shader docs, the backdrop
  // texture is already upright there (a flip mirrored the content on the
  // Android emulator's OpenGLES Impeller backend).
  vec2 uv = clamp(px / uSize, vec2(0.002), vec2(0.998));
  return texture(uTex, uv).rgb;
}

// 28-tap golden-angle (Vogel) disc blur of the given radius in px.
vec3 blurTap(vec2 c, float radius) {
  vec3 sum = tap(c) * 0.5;
  float wsum = 0.5;
  for (int i = 0; i < 28; i++) {
    float fi = float(i) + 0.5;
    float rr = sqrt(fi / 28.0) * radius;
    float th = fi * 2.39996323;
    float w = 1.0 - 0.5 * (fi / 28.0);
    sum += tap(c + rr * vec2(cos(th), sin(th))) * w;
    wsum += w;
  }
  return sum / wsum;
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
  // The bevel can't reach past the shape's medial axis (the line of points
  // equidistant from two edges) - there the edge normal flips sign and the
  // displacement would fold back on itself, cancelling the bend out.
  float bev = min(uBevel, min(hs.x, hs.y) * 0.9);
  float t = clamp(1.0 - depth / max(bev, 1.0), 0.0, 1.0);
  float bulge = t * sqrt(t);
  float disp = uRefraction * 1.6 * bulge;

  // Apple-style glass: the backdrop is genuinely blurred (a golden-angle disc
  // of taps, uFrost px radius) *and* bent at the rim. The red/blue channels
  // are blurred around slightly deeper-displaced centres for dispersion.
  vec3 col;
  // The blur relaxes toward the rim (down to 30%) so the bent content stays
  // recognisable there - otherwise a big blur averages the refraction away.
  float rad = uFrost * mix(1.0, 0.3, bulge);
  col.r = blurTap(frag - n * disp * 1.00, rad).r;
  col.g = blurTap(frag - n * disp * 1.10, rad).g;
  col.b = blurTap(frag - n * disp * 1.20, rad).b;

  // Vibrancy: lift saturation and brightness a touch, as glass over content
  // does, so the fill reads as a lit material rather than a grey wash.
  float luma = dot(col, vec3(0.299, 0.587, 0.114));
  col = mix(vec3(luma), col, 1.3) * 1.04;

  // Specular rim lit from the top-left, softer bounce from the opposite side.
  vec2 light = normalize(vec2(-0.55, -0.83));
  float facing = max(dot(n, light), 0.0) + 0.45 * max(dot(n, -light), 0.0);
  float rim = exp(-depth / 1.4) * facing;
  float glow = exp(-depth / max(bev * 0.8, 1.0)) * (0.35 + 0.65 * facing);
  col += uRim * (rim + 0.12 * glow);

  float a = clamp(0.5 - d, 0.0, 1.0);
  fragColor = vec4(col * a, a);
}
