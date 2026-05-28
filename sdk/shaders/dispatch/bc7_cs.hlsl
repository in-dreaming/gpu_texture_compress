// dispatch/bc7_cs.hlsl - Compute shader entry point for BC7 compression
// Dispatches one thread per 4x4 block, loads RGBA from SourceTexture,
// calls pure compress_bc7() function (Mode 6 only).

#include "common/gtc_interface.hlsl"
#include "compress/bc7.hlsl"

RWStructuredBuffer<uint4> OutputBlocks : register(u0);

[numthreads(8, 8, 1)]
void MainCS(uint3 DTid : SV_DispatchThreadID) {
    if (DTid.x >= (uint)BlocksX || DTid.y >= (uint)BlocksY) return;

    float4 pixels[16];
    [unroll] for (int py = 0; py < 4; py++)
        [unroll] for (int px = 0; px < 4; px++) {
            int2 coord = int2(DTid.x * 4 + px, DTid.y * 4 + py);
            coord = min(coord, int2(TexWidth - 1, TexHeight - 1));
            pixels[py * 4 + px] = SourceTexture.Load(int3(coord, 0));
        }

    uint blockIndex = DTid.y * BlocksX + DTid.x;
    OutputBlocks[blockIndex] = compress_bc7(pixels);
}
