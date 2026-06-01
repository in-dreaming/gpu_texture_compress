#ifndef ASTC_BLOCK_MODES_HLSL
#define ASTC_BLOCK_MODES_HLSL

// ASTC Block Modes for different block sizes
// Block mode bits encode the WEIGHT GRID size + WEIGHT QUANTIZATION METHOD,
// NOT the pixel block size (the block size is fixed by the format).
//
// Formula (Table C.2.8 row 1, dual-plane=0, single-precision):
//   bits[1:0] = R[2:1]     (top two bits of weight quant range index)
//   bits[3:2] = 00         (must be zero for layout 1)
//   bit[4]    = R[0]
//   bits[6:5] = A          where Y_GRIDS = A + 2
//   bits[8:7] = B          where X_GRIDS = B + 4
//   bit[9]    = H          (high-precision flag)
//   bit[10]   = D          (dual-plane flag)
//
// For QUANT_4 (range 0..3, 2 bits/weight, weight_quantmethod=2):
//   r = (weight_quantmethod % 6) + 2 = 4
//   r = R2 R1 R0 = 100b -> R[2:1]=10, R[0]=0
//   bits[1:0] = 10, bit[4] = 0
// => For ANY 4x4 weight grid + QUANT_4: 0x042
//    (Y_GRIDS=4 -> A=2 -> bits[6:5]=10, X_GRIDS=4 -> B=0)
//
// All non-4x4 block sizes using a 4x4 weight grid share the SAME block mode
// (0x042). The previous file had per-format constants that were invalid layouts.

#define ASTC_BLOCK_MODE_4x4_Q4   0x042u   // 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_5x4_Q4   0x042u   // 5x4 block, 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_5x5_Q4   0x042u   // 5x5 block, 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_6x5_Q4   0x042u   // 6x5 block, 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_6x6_Q4   0x042u   // 6x6 block, 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_8x5_Q4   0x042u   // 8x5 block, 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_8x6_Q4   0x042u   // 8x6 block, 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_8x8_Q4   0x042u   // 8x8 block, 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_10x5_Q4  0x042u   // 10x5 block, 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_10x6_Q4  0x042u   // 10x6 block, 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_10x8_Q4  0x042u   // 10x8 block, 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_10x10_Q4 0x042u   // 10x10 block, 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_12x10_Q4 0x042u   // 12x10 block, 4x4 grid, QUANT_4
#define ASTC_BLOCK_MODE_12x12_Q4 0x042u   // 12x12 block, 4x4 grid, QUANT_4

#endif // ASTC_BLOCK_MODES_HLSL
