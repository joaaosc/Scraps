#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 scrapsRim(float2 position, half4 color, float progress, float2 size) {
    float2 centered = position / max(size, float2(1.0)) - 0.5;
    float angle = atan2(centered.y, centered.x);
    float sweep = progress * 6.2831853 - 3.1415927;
    float band = pow(max(0.0, cos(angle - sweep)), 16.0);
    float envelope = sin(clamp(progress, 0.0, 1.0) * 3.1415927);
    half alpha = color.a * half(envelope);
    half3 rgb = min(half3(1.0), color.rgb / max(color.a, half(0.001)) + half3(band * 0.55));
    return half4(rgb * alpha, alpha);
}
