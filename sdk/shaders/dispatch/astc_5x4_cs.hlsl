// ASTC 5x4 Compute Shader Dispatch
#include "common/gtc_interface.hlsl"
#include "compress/astc_5x4.hlsl"

RWStructuredBuffer<uint4> OutputBlocks : register(u0);

[numthreads(8, 8, 1)]
void MainCS(uint3 DTid : SV_DispatchThreadID) {
    if (DTid.x >= (uint)BlocksX || DTid.y >= (uint)BlocksY) return;

    float4 pixels[20];
    [unroll] for (int py = 0; py < 4; py++)
        [unroll] for (int px = 0; px < 5; px++) {
            int2 coord = int2((int)DTid.x * 5 + px, (int)DTid.y * 4 + py);
            coord = min(coord, int2(TexWidth - 1, TexHeight - 1));
            pixels[py * 5 + px] = SourceTexture.Load(int3(coord, 0));
        }

    uint blockIndex = DTid.y * BlocksX + DTid.x;
    OutputBlocks[blockIndex] = compress_astc_5x4(pixels);
}
