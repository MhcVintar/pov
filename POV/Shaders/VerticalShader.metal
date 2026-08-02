#include <metal_stdlib>

using namespace metal;

uint verticalMapX(float outX, float inWidth, float outWidth) {
    float normalizedOutX = (outX / outWidth - 0.5) * 2;
    float inX = outX - (outWidth - inWidth) / 2;
    float offset = pow(normalizedOutX, 2) * sign(normalizedOutX) * ((inWidth - outWidth) / 2);
    return uint(inX + offset);
}

uint verticalMapY(float outY, float inHeight, float outHeight) {
    float normalizedOutY = (outY / outHeight - 0.5) * 2;
    float inY = outY - (outHeight - inHeight) / 2;
    float offset = pow(normalizedOutY, 2) * sign(normalizedOutY) * ((outHeight - inHeight) / 2);
    return uint(inY - offset);
}

kernel void vertical(texture2d<half, access::read> inputY [[texture(0)]],
                     texture2d<half, access::read> inputUV [[texture(1)]],
                     texture2d<half, access::write> outputY [[texture(2)]],
                     texture2d<half, access::write> outputUV [[texture(3)]],
                     uint2 gid [[thread_position_in_grid]]) {
    // Compute input coords
    uint inputXCoord = verticalMapX(float(gid.x),
                                    float(inputY.get_width()),
                                    float(outputY.get_width()));
    uint inputYCoord = verticalMapY(float(gid.y),
                                    float(inputY.get_height()),
                                    float(outputY.get_height()));
    uint2 inputCoords = uint2(inputXCoord, inputYCoord);

    // Sample Y plane
    half yValue = inputY.read(inputCoords).r;
    outputY.write(half4(yValue, 0, 0, 1), gid);

    // Sample UV plane (only for even coordinates)
    if (gid.x % 2 == 0 && gid.y % 2 == 0) {
        uint2 chromaInputCoords = inputCoords / 2;
        uint2 chromaOutputCoords = gid / 2;
        half2 uvValues = inputUV.read(chromaInputCoords).rg;
        outputUV.write(half4(uvValues.r, uvValues.g, 0, 1), chromaOutputCoords);
    }
}
