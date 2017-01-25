// Copyright (c) 2016 Andreas Auernhammer. All rights reserved.
// Use of this source code is governed by a license that can be
// found in the LICENSE file.

// +build amd64,!gccgo,!appengine,!nacl

#include "textflag.h"

DATA ·sigma<>+0x00(SB)/4, $0x61707865
DATA ·sigma<>+0x04(SB)/4, $0x3320646e
DATA ·sigma<>+0x08(SB)/4, $0x79622d32
DATA ·sigma<>+0x0C(SB)/4, $0x6b206574
GLOBL ·sigma<>(SB), (NOPTR+RODATA), $16

DATA ·one<>+0x00(SB)/8, $1
DATA ·one<>+0x08(SB)/8, $0
GLOBL ·one<>(SB), (NOPTR+RODATA), $16

DATA ·rol16<>+0x00(SB)/8, $0x0504070601000302
DATA ·rol16<>+0x08(SB)/8, $0x0D0C0F0E09080B0A
GLOBL ·rol16<>(SB), (NOPTR+RODATA), $16

DATA ·rol8<>+0x00(SB)/8, $0x0605040702010003
DATA ·rol8<>+0x08(SB)/8, $0x0E0D0C0F0A09080B
GLOBL ·rol8<>(SB), (NOPTR+RODATA), $16

#define ROTL_SSE2(n, t, v) \
 	MOVO v, t; \
	PSLLL $n, t; \
	PSRLL $(32-n), v; \
	PXOR t, v

#define CHACHA_QROUND_SSE2(v0 , v1 , v2 , v3 , t0) \
    PADDL v1, v0; \
	PXOR v0, v3; \
	ROTL_SSE2(16, t0, v3); \
	PADDL v3, v2; \
	PXOR v2, v1; \
	ROTL_SSE2(12, t0, v1); \
	PADDL v1, v0; \
	PXOR v0, v3; \
	ROTL_SSE2(8, t0, v3); \
	PADDL v3, v2; \
	PXOR v2, v1; \
	ROTL_SSE2(7, t0, v1)
    
#define CHACHA_QROUND_SSSE3(v0 , v1 , v2 , v3 , t0, r16, r8) \
    PADDL v1, v0; \
	PXOR v0, v3; \
	PSHUFB r16, v3; \
	PADDL v3, v2; \
	PXOR v2, v1; \
	ROTL_SSE2(12, t0, v1); \
	PADDL v1, v0; \
	PXOR v0, v3; \
	PSHUFB r8, v3; \
	PADDL v3, v2; \
	PXOR v2, v1; \
	ROTL_SSE2(7, t0, v1)

#define CHACHA_SHUFFLE(v1, v2, v3) \
    PSHUFL $0x39, v1, v1; \
	PSHUFL $0x4E, v2, v2; \
	PSHUFL $0x93, v3, v3

#define XOR(dst, src, off, v0 , v1 , v2 , v3 , t0) \
	MOVOU 0+off(src), t0; \
	PXOR v0, t0; \
	MOVOU t0, 0+off(dst); \
	MOVOU 16+off(src), t0; \
	PXOR v1, t0; \
	MOVOU t0, 16+off(dst); \
	MOVOU 32+off(src), t0; \
	PXOR v2, t0; \
	MOVOU t0, 32+off(dst); \
	MOVOU 48+off(src), t0; \
	PXOR v3, t0; \
	MOVOU t0, 48+off(dst)

// func xorKeyStreamSSE2(dst, src []byte, block, state *[64]byte, rounds int) int
TEXT ·xorKeyStreamSSE2(SB),4,$0-80
	MOVQ dst_base+0(FP), DI
	MOVQ src_base+24(FP), SI
	MOVQ src_len+32(FP), CX
    MOVQ block+48(FP), BX
    MOVQ state+56(FP), AX
	MOVQ rounds+64(FP), DX

    MOVOU 0(AX), X0
    MOVOU 16(AX), X1
    MOVOU 32(AX), X2
    MOVOU 48(AX), X3
    MOVOU ·one<>(SB), X15

    CMPQ CX, $64
    JBE between_0_and_64

at_least_128:
    MOVO X0, X4
    MOVO X1, X5
    MOVO X2, X6
    MOVO X3, X7    
    MOVO X0, X8
    MOVO X1, X9
    MOVO X2, X10
    MOVO X3, X11
    PADDQ X15, X11

    MOVQ DX, R8
chacha_loop_128:
    CHACHA_QROUND_SSE2(X4, X5, X6, X7, X12)
    CHACHA_QROUND_SSE2(X8, X9, X10, X11, X12)
    CHACHA_SHUFFLE(X5, X6, X7)
    CHACHA_SHUFFLE(X9, X10, X11)
    CHACHA_QROUND_SSE2(X4, X5, X6, X7, X12)
    CHACHA_QROUND_SSE2(X8, X9, X10, X11, X12)
    CHACHA_SHUFFLE(X7, X6, X5)
    CHACHA_SHUFFLE(X11, X10, X9)
    SUBQ $2, R8
    JA chacha_loop_128

    PADDL X0, X4
    PADDL X1, X5
    PADDL X2, X6
    PADDL X3, X7
    PADDQ X15, X3
    PADDL X0, X8
    PADDL X1, X9
    PADDL X2, X10
    PADDL X3, X11
    PADDQ X15, X3

    CMPQ CX, $128
    JB less_than_128

    XOR(DI, SI, 0, X4, X5, X6, X7, X12)
    XOR(DI, SI, 64, X8, X9, X10, X11, X12)
    ADDQ $128, SI
    ADDQ $128, DI
    SUBQ $128, CX
    CMPQ CX, $64
    JA at_least_128
    
    TESTQ CX, CX
    JZ done
    JMP between_0_and_64

less_than_128:
    XOR(DI, SI, 0, X4, X5, X6, X7, X12)
    ADDQ $64, SI
    ADDQ $64, DI
    SUBQ $64, CX
    MOVO X8, X4
    MOVO X9, X5
    MOVO X10, X6
    MOVO X11, X7
    JMP less_than_64

between_0_and_64:
    MOVO X0, X4
    MOVO X1, X5
    MOVO X2, X6
    MOVO X3, X7
    MOVQ DX, R8 
chacha_final_loop_64:
    CHACHA_QROUND_SSE2(X4, X5, X6, X7, X12)
    CHACHA_SHUFFLE(X5, X6, X7)
    CHACHA_QROUND_SSE2(X4, X5, X6, X7, X12)
    CHACHA_SHUFFLE(X7, X6, X5)
    SUBQ $2, R8
    JA chacha_final_loop_64
    
    PADDL X0, X4
    PADDL X1, X5
    PADDL X2, X6
    PADDL X3, X7
    PADDQ X15, X3
    CMPQ CX, $64
    JB less_than_64

    XOR(DI, SI, 0, X4, X5, X6, X7, X12)
    SUBQ $64, CX
    JMP done

less_than_64:
    MOVOU X4, 0(BX)
    MOVOU X5, 16(BX)
    MOVOU X6, 32(BX)
    MOVOU X7, 48(BX)
    XORQ R11, R11
    XORQ R12, R12
    MOVQ CX, BP
xor_loop:
    MOVB 0(SI), R11
    MOVB 0(BX), R12
    XORQ R11, R12
    MOVB R12, 0(DI)
    INCQ SI
    INCQ BX
    INCQ DI
    DECQ BP
    JA xor_loop

done:
    MOVOU X3, 48(AX)
    MOVQ CX, ret+72(FP)
    RET

// func xorKeyStreamSSSE3(dst, src []byte, block, state *[64]byte, rounds int) int
TEXT ·xorKeyStreamSSSE3(SB),4,$0-80
	MOVQ dst_base+0(FP), DI
	MOVQ src_base+24(FP), SI
	MOVQ src_len+32(FP), CX
    MOVQ block+48(FP), BX
    MOVQ state+56(FP), AX
	MOVQ rounds+64(FP), DX

    MOVOU 0(AX), X0
    MOVOU 16(AX), X1
    MOVOU 32(AX), X2
    MOVOU 48(AX), X3
    MOVOU ·rol16<>(SB), X13
    MOVOU ·rol8<>(SB), X14
    MOVOU ·one<>(SB), X15

    CMPQ CX, $64
    JBE between_0_and_64

at_least_128:
    MOVO X0, X4
    MOVO X1, X5
    MOVO X2, X6
    MOVO X3, X7    
    MOVO X0, X8
    MOVO X1, X9
    MOVO X2, X10
    MOVO X3, X11
    PADDQ X15, X11

    MOVQ DX, R8
chacha_loop_128:
    CHACHA_QROUND_SSSE3(X4, X5, X6, X7, X12, X13, X14)
    CHACHA_QROUND_SSSE3(X8, X9, X10, X11, X12, X13, X14)
    CHACHA_SHUFFLE(X5, X6, X7)
    CHACHA_SHUFFLE(X9, X10, X11)
    CHACHA_QROUND_SSSE3(X4, X5, X6, X7, X12, X13, X14)
    CHACHA_QROUND_SSSE3(X8, X9, X10, X11, X12, X13, X14)
    CHACHA_SHUFFLE(X7, X6, X5)
    CHACHA_SHUFFLE(X11, X10, X9)
    SUBQ $2, R8
    JA chacha_loop_128

    PADDL X0, X4
    PADDL X1, X5
    PADDL X2, X6
    PADDL X3, X7
    PADDQ X15, X3
    PADDL X0, X8
    PADDL X1, X9
    PADDL X2, X10
    PADDL X3, X11
    PADDQ X15, X3

    CMPQ CX, $128
    JB less_than_128

    XOR(DI, SI, 0, X4, X5, X6, X7, X12)
    XOR(DI, SI, 64, X8, X9, X10, X11, X12)
    ADDQ $128, SI
    ADDQ $128, DI
    SUBQ $128, CX
    CMPQ CX, $64
    JA at_least_128
    
    TESTQ CX, CX
    JZ done
    JMP between_0_and_64

less_than_128:
    XOR(DI, SI, 0, X4, X5, X6, X7, X12)
    ADDQ $64, SI
    ADDQ $64, DI
    SUBQ $64, CX
    MOVO X8, X4
    MOVO X9, X5
    MOVO X10, X6
    MOVO X11, X7
    JMP less_than_64

between_0_and_64:
    MOVO X0, X4
    MOVO X1, X5
    MOVO X2, X6
    MOVO X3, X7
    MOVQ DX, R8 
chacha_final_loop_64:
    CHACHA_QROUND_SSSE3(X4, X5, X6, X7, X12, X13, X14)
    CHACHA_SHUFFLE(X5, X6, X7)
    CHACHA_QROUND_SSSE3(X4, X5, X6, X7, X12, X13, X14)
    CHACHA_SHUFFLE(X7, X6, X5)
    SUBQ $2, R8
    JA chacha_final_loop_64
    
    PADDL X0, X4
    PADDL X1, X5
    PADDL X2, X6
    PADDL X3, X7
    PADDQ X15, X3
    CMPQ CX, $64
    JB less_than_64

    XOR(DI, SI, 0, X4, X5, X6, X7, X12)
    SUBQ $64, CX
    JMP done

less_than_64:
    MOVOU X4, 0(BX)
    MOVOU X5, 16(BX)
    MOVOU X6, 32(BX)
    MOVOU X7, 48(BX)
    XORQ R11, R11
    XORQ R12, R12
    MOVQ CX, BP
xor_loop:
    MOVB 0(SI), R11
    MOVB 0(BX), R12
    XORQ R11, R12
    MOVB R12, 0(DI)
    INCQ SI
    INCQ BX
    INCQ DI
    DECQ BP
    JA xor_loop

done:
    MOVOU X3, 48(AX)
    MOVQ CX, ret+72(FP)
    RET

// func supportsSSSE3() bool
TEXT ·supportsSSSE3(SB), NOSPLIT, $0-1
	XORQ AX, AX
    INCQ AX
	CPUID
	SHRQ $9, CX
	ANDQ $1, CX
	MOVB CX, ret+0(FP)
	RET

// func initialize(state *[64]byte, key *[32]byte, nonce *[16]byte)
TEXT ·initialize(SB), 4, $0-24
    MOVQ state+0(FP), DI
    MOVQ key+8(FP), AX
    MOVQ nonce+16(FP), BX

    MOVOU ·sigma<>(SB), X0
    MOVOU 0(AX), X1
    MOVOU 16(AX), X2
    MOVOU 0(BX), X3

    MOVOU X0, 0(DI)
    MOVOU X1, 16(DI)
    MOVOU X2, 32(DI)
    MOVOU X3, 48(DI)
    RET

// func hChaCha20SSE2(out *[32]byte, nonce *[16]byte, key *[32]byte)
TEXT ·hChaCha20SSE2(SB), 4, $0-24
    MOVQ out+0(FP), DI
    MOVQ nonce+8(FP), AX
    MOVQ key+16(FP), BX

    MOVOU ·sigma<>(SB), X0
    MOVOU 0(BX), X1
    MOVOU 16(BX), X2
    MOVOU 0(AX), X3

    MOVQ $20, CX
chacha_loop:
    CHACHA_QROUND_SSE2(X0, X1, X2, X3, X4)
    CHACHA_SHUFFLE(X1, X2, X3)
    CHACHA_QROUND_SSE2(X0, X1, X2, X3, X4)
    CHACHA_SHUFFLE(X3, X2, X1)
    SUBQ $2, CX
    JNZ chacha_loop

    MOVOU X0, 0(DI)
    MOVOU X3, 16(DI)
    RET

// func hChaCha20SSSE3(out *[32]byte, nonce *[16]byte, key *[32]byte)
TEXT ·hChaCha20SSSE3(SB), 4, $0-24
    MOVQ out+0(FP), DI
    MOVQ nonce+8(FP), AX
    MOVQ key+16(FP), BX

    MOVOU ·sigma<>(SB), X0
    MOVOU 0(BX), X1
    MOVOU 16(BX), X2
    MOVOU 0(AX), X3
    MOVOU ·rol16<>(SB), X5
    MOVOU ·rol8<>(SB), X6

    MOVQ $20, CX
chacha_loop:
    CHACHA_QROUND_SSSE3(X0, X1, X2, X3, X4, X5, X6)
    CHACHA_SHUFFLE(X1, X2, X3)
    CHACHA_QROUND_SSSE3(X0, X1, X2, X3, X4, X5, X6)
    CHACHA_SHUFFLE(X3, X2, X1)
    SUBQ $2, CX
    JNZ chacha_loop

    MOVOU X0, 0(DI)
    MOVOU X3, 16(DI)
    RET
