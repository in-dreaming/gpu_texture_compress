#include "common/gtc_interface.hlsl"
#include "compress/astc_10x8_hdr.hlsl"

RWStructuredBuffer<uint4> OutputBlocks : register(u0);

[numthreads(8, 8, 1)]
void MainCS(uint3 DTid : SV_DispatchThreadID) {
    if (DTid.x >= (uint)BlocksX || DTid.y >= (uint)BlocksY) return;

    float4 pixels[80];
    [unroll] for (int py = 0; py < 8; py++)
        [unroll] for (int px = 0; px < 10; px++) {
            int2 coord = int2((int)DTid.x * 10 + px, (int)DTid.y * 8 + py);
            coord = min(coord, int2(TexWidth - 1, TexHeight - 1));
            pixels[py * 10 + px] = SourceTexture.Load(int3(coord, 0));
        }

    uint blockIndex = DTid.y * BlocksX + DTid.x;
    OutputBlocks[blockIndex] = compress_astc_10x8_hdr(pixels);
}
