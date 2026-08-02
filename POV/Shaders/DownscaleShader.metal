#include <metal_stdlib>

using namespace metal;

kernel void downscale(texture2d<half, access::sample> inputY [[texture(0)]],
                      texture2d<half, access::sample> inputUV [[texture(1)]],
                      texture2d<half, access::write> outputY [[texture(2)]],
                      texture2d<half, access::write> outputUV [[texture(3)]],
                      sampler textureSampler [[sampler(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    // Compute normalized coordinates for sampling
    float2 coords = (float2(gid) + 0.5) / float2(outputY.get_width(), outputY.get_height());
    
    // Sample Y plane
    half yValue = inputY.sample(textureSampler, coords).r;
    outputY.write(half4(yValue, 0, 0, 1), gid);
    
    // Sample UV plane (only for even coordinates)
    if (gid.x % 2 == 0 && gid.y % 2 == 0) {
        half2 uvValues = inputUV.sample(textureSampler, coords).rg;
        outputUV.write(half4(uvValues.r, uvValues.g, 0, 1), gid / 2);
    }
}
