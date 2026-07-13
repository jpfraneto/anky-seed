//
//  PaintingReveal.metal
//
//  The one rule of the reveal: show the final painting where the reveal map
//  is below progress, the underdrawing everywhere else, with a soft wet-edge
//  feather at the frontier — a few pixels of blended zone with brush noise,
//  so strokes arrive like wet pigment, not like a wipe.
//
//  RenderBox allows a single texture argument per shader, so the composite
//  is a ZStack: the underdrawing sits below, and this shader runs on the
//  FINAL painting layer, turning its alpha into the reveal mask (the reveal
//  map is the one texture argument).
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float brushNoise(float2 uv) {
    // Cheap deterministic value noise, layered twice for a fibrous feel.
    float n1 = fract(sin(dot(uv * 421.0, float2(12.9898, 78.233))) * 43758.5453);
    float n2 = fract(sin(dot(uv * 133.0, float2(63.726, 10.873))) * 24634.6345);
    return (n1 * 0.65 + n2 * 0.35) - 0.5;
}

[[ stitchable ]] half4 paintingRevealMask(
    float2 position,
    SwiftUI::Layer layer,
    texture2d<half> revealMap,
    float4 bounds,
    float progress,
    float featherAmount
) {
    half4 color = layer.sample(position);
    if (bounds.z <= 0.0 || bounds.w <= 0.0) {
        return color;
    }
    float2 uv = float2((position.x - bounds.x) / bounds.z,
                       (position.y - bounds.y) / bounds.w);

    constexpr sampler linearSampler(address::clamp_to_edge, filter::linear);
    float mapValue = float(revealMap.sample(linearSampler, uv).r);

    // Perturb the frontier so the wet edge reads as bristle, not geometry.
    float feather = max(featherAmount, 0.002);
    float perturbed = mapValue + brushNoise(uv) * feather * 1.6;

    // t = 1 where the paint has arrived (map below progress).
    float t = 1.0 - smoothstep(progress - feather, progress + feather * 0.25, perturbed);

    // Premultiplied: the final layer fades in per-pixel over the underdrawing.
    return color * half4(half(t));
}
