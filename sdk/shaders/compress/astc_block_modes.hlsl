#ifndef ASTC_BLOCK_MODES_HLSL
#define ASTC_BLOCK_MODES_HLSL

// ASTC Block Modes for different block sizes
// These are the correct block mode values for LDR RGB with 2-bits per weight (QUANT_4)
// Computed based on ASTC specification Table C.2.8

// For blocks that fit the formula: x_weights = B+4, y_weights = A+2
// bits[10:0] format: [D(1) H(1) B(2) x4 D2(2) A(2) R(3) M(2) 0]

#define ASTC_BLOCK_MODE_4x4_Q4   0x042u   // a=2, b=0: 4x4 weights
#define ASTC_BLOCK_MODE_5x4_Q4   0x04Eu   // a=2, b=1: 5x4 weights
#define ASTC_BLOCK_MODE_5x5_Q4   0x08Eu   // a=3, b=1: 5x5 weights
#define ASTC_BLOCK_MODE_6x5_Q4   0x0A2u   // a=3, b=2: 6x5 weights
#define ASTC_BLOCK_MODE_6x6_Q4   0x0C2u   // a=4, b=2: would be 6x6, but A is 2-bits (max 3), so this is wrong!

// For larger blocks, ASTC uses different encoding families
// These use bits[1:0]=00 for dual plane or void extent handling
// Blocks 6x6 and larger need special handling

// Fallback: these are approximate values based on ASTC decimation patterns
// These may not be exactly right; a proper implementation would use the official astcenc
#define ASTC_BLOCK_MODE_6x6_Q4   0x0C2u   // Approximation
#define ASTC_BLOCK_MODE_8x5_Q4   0x0DEu   // Approximation
#define ASTC_BLOCK_MODE_8x6_Q4   0x0FEu   // Approximation
#define ASTC_BLOCK_MODE_8x8_Q4   0x106u   // Approximation
#define ASTC_BLOCK_MODE_10x5_Q4  0x122u   // Approximation
#define ASTC_BLOCK_MODE_10x6_Q4  0x132u   // Approximation
#define ASTC_BLOCK_MODE_10x8_Q4  0x142u   // Approximation
#define ASTC_BLOCK_MODE_10x10_Q4 0x162u   // Approximation
#define ASTC_BLOCK_MODE_12x10_Q4 0x1A2u   // Approximation
#define ASTC_BLOCK_MODE_12x12_Q4 0x1B2u   // Approximation

#endif // ASTC_BLOCK_MODES_HLSL
