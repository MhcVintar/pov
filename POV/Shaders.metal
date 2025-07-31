//
//  Shaders.metal
//  POV
//
//  Created by Miha Vintar on 31. 7. 25.
//

#include <metal_stdlib>
using namespace metal;

float computeX(float tx, float inWidth, float outWidth) {
    const float x = (tx / outWidth - 0.5) * 2.0;
    const float sx = tx - (outWidth -  inWidth) / 2.0;
    const float offset = pow(x, 2) * sign(x) * ((outWidth - inWidth) / 2.0);
    return sx - offset;
}

kernel void superview(texture2d<float, access::sample> inTexture [[texture(0)]],
                            texture2d<float, access::write> outTexture [[texture(1)]],
                            sampler texSampler [[sampler(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
    const float inX = computeX(float(gid.x),
                               float(inTexture.get_width()),
                               float(outTexture.get_width()));

    outTexture.write(inTexture.read(uint2(inX, gid.y)), gid);
}
