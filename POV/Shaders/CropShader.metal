#include <metal_stdlib>

using namespace metal;

kernel void crop(texture2d<half, access::sample> inputY [[texture(0)]],
                 texture2d<half, access::sample> inputUV [[texture(1)]],
                 texture2d<half, access::write> outputY [[texture(2)]],
                 texture2d<half, access::write> outputUV [[texture(3)]],
                 uint2 gid [[thread_position_in_grid]]) {
    // Compute offset
    uint offsetX = (inputY.get_width() - outputY.get_width()) / 2;
    uint offsetY = (inputY.get_height() - outputY.get_height()) / 2;
    uint2 offset = uint2(offsetX, offsetY);
    
    // Sample Y plane
    uint2 inputCoords = gid + offset;
    half yValue = inputY.read(inputCoords).r;
    outputY.write(half4(yValue, 0, 0, 1), gid);

    // Sample UV plane (only for even coordinates)
    if (gid.x % 2 == 0 && gid.y % 2 == 0) {
        uint2 chromaOutputCoords = gid / 2;
        uint2 chromaInputCoord = inputCoords / 2;
        half2 uvValues = inputUV.read(chromaInputCoord).rg;
        outputUV.write(half4(uvValues.r, uvValues.g, 0, 1), chromaOutputCoords);
    }
}
