#include "common/gtc_interface.hlsl"
#include "compress/astc_4x4_hdr.hlsl"

RWStructuredBuffer<uint4> OutputBlocks : register(u0);

[numthreads(8, 8, 1)]
void MainCS(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= (uint)BlocksX || DTid.y >= (uint)BlocksY)
        return;

    uint blockX = DTid.x;
    uint blockY = DTid.y;
    uint blockIndex = blockY * (uint)BlocksX + blockX;

    // Load 4x4 pixels
    float4 pixels[16];
    float texelPosX = float(blockX * 4);
    float texelPosY = float(blockY * 4);

    [unroll]
    for (int y = 0; y < 4; ++y)
    {
        [unroll]
        for (int x = 0; x < 4; ++x)
        {
            pixels[y * 4 + x] = SourceTexture.Load(int3(texelPosX + x, texelPosY + y, 0));
        }
    }

    // Compress HDR pixels
    uint4 block = compress_astc_4x4_hdr(pixels);

    // Store compressed block
    OutputBlocks[blockIndex] = block;
}
