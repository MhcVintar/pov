#include <metal_stdlib>
using namespace metal;

float computeX(float tx, float inWidth, float outWidth) {
    const float x = (tx / outWidth - 0.5) * 2.0;
    const float sx = tx - (outWidth - inWidth) / 2.0;
    const float offset = pow(x, 2) * sign(x) * ((outWidth - inWidth) / 2.0);
    return sx - offset;
}

kernel void superview(texture2d<half, access::read> inputY [[texture(0)]],
                      texture2d<half, access::read> inputUV [[texture(1)]],
                      texture2d<half, access::write> outputY [[texture(2)]],
                      texture2d<half, access::write> outputUV [[texture(3)]],
                      uint2 gid [[thread_position_in_grid]]) {
    // Use your computeX function to apply the superview transformation
    const float transformedX = computeX(float(gid.x),
                                        float(inputY.get_width()),
                                        float(outputY.get_width()));
    
    // Sample Y plane
    uint2 inputCoord = uint2(uint(transformedX), gid.y);
    half yValue = inputY.read(inputCoord).r;
    
    // Sample UV plane (chroma is subsampled by 2)
    uint2 chromaCoord = uint2(inputCoord.x / 2, inputCoord.y / 2);
    half2 uvValues = inputUV.read(chromaCoord).rg;
    half uValue = uvValues.r;
    half vValue = uvValues.g;
    
    // Write Y plane
    outputY.write(half4(yValue, 0, 0, 1), gid);
    
    // Write UV plane (only for even coordinates since chroma is subsampled)
    if (gid.x % 2 == 0 && gid.y % 2 == 0) {
        uint2 chromaOutputCoord = uint2(gid.x / 2, gid.y / 2);
        if (chromaOutputCoord.x < outputUV.get_width() && chromaOutputCoord.y < outputUV.get_height()) {
            outputUV.write(half4(uValue, vValue, 0, 1), chromaOutputCoord);
        }
    }
}

kernel void downscale(texture2d<half, access::sample> inputY [[texture(0)]],
                      texture2d<half, access::sample> inputUV [[texture(1)]],
                      texture2d<half, access::write> outputY [[texture(2)]],
                      texture2d<half, access::write> outputUV [[texture(3)]],
                      sampler textureSampler [[sampler(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    // Calculate normalized coordinates for sampling
    float2 coord = (float2(gid) + 0.5) / float2(outputY.get_width(), outputY.get_height());
    
    // Sample Y plane
    half yValue = inputY.sample(textureSampler, coord).r;
    outputY.write(half4(yValue, 0, 0, 1), gid);
    
    // Sample UV plane (only for even coordinates)
    if (gid.x % 2 == 0 && gid.y % 2 == 0) {
        uint2 uvCoord = gid / 2;
        if (uvCoord.x < outputUV.get_width() && uvCoord.y < outputUV.get_height()) {
            half2 uvValues = inputUV.sample(textureSampler, coord).rg;
            outputUV.write(half4(uvValues.r, uvValues.g, 0, 1), uvCoord);
        }
    }
}
