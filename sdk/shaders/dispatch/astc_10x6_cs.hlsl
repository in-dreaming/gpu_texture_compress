// ASTC 10x6 Compute Shader Dispatch
#define ASTC_BLOCK_W 10
#define ASTC_BLOCK_H 6
#include "common/gtc_interface.hlsl"
#include "compress/astc.hlsl"

RWStructuredBuffer<uint4> OutputBlocks : register(u0);

[numthreads(8, 8, 1)]
void MainCS(uint3 DTid : SV_DispatchThreadID) {
    if (DTid.x >= (uint)BlocksX || DTid.y >= (uint)BlocksY) return;

    float4 pixels[ASTC_BLOCK_W * ASTC_BLOCK_H];
    [unroll] for (int py = 0; py < ASTC_BLOCK_H; py++)
        [unroll] for (int px = 0; px < ASTC_BLOCK_W; px++) {
            int2 coord = int2(DTid.x * ASTC_BLOCK_W + px, DTid.y * ASTC_BLOCK_H + py);
            coord = min(coord, int2(TexWidth - 1, TexHeight - 1));
            pixels[py * ASTC_BLOCK_W + px] = SourceTexture.Load(int3(coord, 0));
        }

    uint blockIndex = DTid.y * BlocksX + DTid.x;
    OutputBlocks[blockIndex] = compress_astc(pixels, ASTC_BLOCK_W * ASTC_BLOCK_H);
}
