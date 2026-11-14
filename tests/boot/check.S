/* =============================================================================
 * Programa de verificação dos fragmentos de boot no Spike
 *
 * Suja o estado que cada extensão ligada em boot_config.h deve limpar, inclui os
 * fragmentos na ordem do contrato, confere o estado que eles deixam e termina
 * pelo tohost do HTIF (1 passa, (código << 1) | 1 falha). Os códigos de falha
 * estão em docs/pt-br/contracts/04-contrato-de-boot.md.
 * ============================================================================= */

#include "boot_config.h"

/* Falha com o código \code se t0 é diferente de zero. */
    .macro  expect_zero code
    beqz    t0, 9f
    li      t1, \code
    j       fail
9:
    .endm

/* Dá um valor sujo ao registrador de sentinela \reg. */
    .macro  sentinel reg, value
    li      \reg, \value
    .endm

    .section .text.init, "ax"
    .globl  _start
_start:
#if RV32_HAS_ZICSR
    lla     t0, dirty_trap
    csrw    mtvec, t0
    li      t0, -1
    csrw    mscratch, t0
    li      t0, 0x888
    csrw    mie, t0
#if RV32_HAS_SSCOFPMF
    li      t0, 0x20080
#else
    li      t0, 0x20088
#endif
    csrw    mstatus, t0
#endif
#if RV32_HAS_ZICNTR || RV32_HAS_ZIHPM
    li      t0, -1
    csrw    mcountinhibit, t0
#endif
#if RV32_HAS_ZICNTR
    li      t0, 0xFFFFFFF0
    csrw    mcycle, t0
    csrw    minstret, t0
    li      t0, 0x1234
    csrw    mcycleh, t0
    csrw    minstreth, t0
#endif
#if RV32_HAS_ZIHPM
    li      t0, 0xDEADBEEF
    .set    .Ldirty, 3
    .rept   29
    csrw    0xB00 + .Ldirty, t0
    csrw    0xB80 + .Ldirty, t0
    csrw    0x320 + .Ldirty, t0
    .set    .Ldirty, .Ldirty + 1
    .endr
#endif
#if RV32_HAS_SSCOFPMF
    li      t0, 0xC0000000
    .set    .Ldirty, 3
    .rept   29
    csrw    0x720 + .Ldirty, t0
    .set    .Ldirty, .Ldirty + 1
    .endr
    li      t0, 1 << 13
    csrs    mip, t0
    csrs    mie, t0
#endif

    sentinel a0, 0x0A0A0A0A
    sentinel a1, 0x1B1B1B1B
    sentinel a2, 0x2C2C2C2C
    sentinel a3, 0x3D3D3D3D
    sentinel a4, 0x4E4E4E4E
    sentinel a5, 0x5F5F5F5F
    sentinel s0, 0x60606060
    sentinel s1, 0x71717171
#if !RV32_IS_E
    sentinel a6, 0x16161616
    sentinel a7, 0x17171717
    sentinel s2, 0x18181818
    sentinel s3, 0x19191919
    sentinel s4, 0x1A1A1A1A
    sentinel s5, 0x1B1B1B1B
    sentinel s6, 0x1C1C1C1C
    sentinel s7, 0x1D1D1D1D
    sentinel s8, 0x1E1E1E1E
    sentinel s9, 0x1F1F1F1F
    sentinel s10, 0x20202020
    sentinel s11, 0x21212121
    sentinel t3, 0x2323232A
    sentinel t4, 0x2424242B
    sentinel t5, 0x2525252C
    sentinel t6, 0x2626262D
#endif
    sentinel gp, 0x27272727
    sentinel tp, 0x28282828
    sentinel sp, 0x29292929
    sentinel ra, 0x2A2A2A2A

#include "Zicsr/boot.inc"
#include "Zicntr/boot.inc"
#include "Zihpm/boot.inc"
#include "Sscofpmf/boot.inc"
#include "Zifencei/boot.inc"

#if RV32_HAS_ZICSR
    csrr    t0, mstatus
    li      t1, 0x20088
    and     t0, t0, t1
    expect_zero 1
    csrr    t0, mie
    expect_zero 2
    csrr    t0, mscratch
    expect_zero 3
    csrr    t0, mtvec
    lla     t1, rv32_boot_trap
    xor     t0, t0, t1
    expect_zero 4
#endif
#if RV32_HAS_SSCOFPMF
    csrr    t0, mip
    li      t1, 1 << 13
    and     t0, t0, t1
    expect_zero 5
#endif
#if RV32_HAS_ZICNTR || RV32_HAS_ZIHPM
    csrr    t0, mcountinhibit
/* Só os bits que o fragmento ligado limpa: 0 e 2 do Zicntr, 3 a 31 do Zihpm. */
    li      t1, (RV32_HAS_ZICNTR * 5) | (RV32_HAS_ZIHPM * -8)
    and     t0, t0, t1
    expect_zero 6
#endif
#if RV32_HAS_ZICNTR
    csrr    t0, mcycleh
    expect_zero 7
    csrr    t0, minstreth
    expect_zero 8
    csrr    t0, mcycle
    srli    t0, t0, 12
    expect_zero 9
    csrr    t0, minstret
    srli    t0, t0, 12
    expect_zero 10
#endif
#if RV32_HAS_ZIHPM
    li      s1, 0
    .set    .Lcheck, 3
    .rept   29
    csrr    t0, 0xB00 + .Lcheck
    or      s1, s1, t0
    csrr    t0, 0xB80 + .Lcheck
    or      s1, s1, t0
    csrr    t0, 0x320 + .Lcheck
    or      s1, s1, t0
    .set    .Lcheck, .Lcheck + 1
    .endr
    mv      t0, s1
    expect_zero 11
#endif
#if RV32_HAS_SSCOFPMF
    li      s1, 0
    .set    .Lcheck, 3
    .rept   29
    csrr    t0, 0x720 + .Lcheck
    or      s1, s1, t0
    .set    .Lcheck, .Lcheck + 1
    .endr
    mv      t0, s1
    expect_zero 12
#endif

/* Nenhum registrador fora de t0 a t2 muda: confere cada sentinela. */
    .macro  keep reg, value
    li      t0, \value
    sub     t0, t0, \reg
    expect_zero 20
    .endm
    keep    a0, 0x0A0A0A0A
    keep    a1, 0x1B1B1B1B
    keep    a2, 0x2C2C2C2C
    keep    a3, 0x3D3D3D3D
    keep    a4, 0x4E4E4E4E
    keep    a5, 0x5F5F5F5F
    keep    s0, 0x60606060
#if !RV32_IS_E
    keep    a6, 0x16161616
    keep    a7, 0x17171717
    keep    s2, 0x18181818
    keep    s3, 0x19191919
    keep    s4, 0x1A1A1A1A
    keep    s5, 0x1B1B1B1B
    keep    s6, 0x1C1C1C1C
    keep    s7, 0x1D1D1D1D
    keep    s8, 0x1E1E1E1E
    keep    s9, 0x1F1F1F1F
    keep    s10, 0x20202020
    keep    s11, 0x21212121
    keep    t3, 0x2323232A
    keep    t4, 0x2424242B
    keep    t5, 0x2525252C
    keep    t6, 0x2626262D
#endif
    keep    gp, 0x27272727
    keep    tp, 0x28282828
    keep    sp, 0x29292929
    keep    ra, 0x2A2A2A2A

pass:
    li      t1, 1
    j       finish

/* Tratador de trap sujo e tratador seguro do fragmento: qualquer trap falha. */
dirty_trap:
    li      t1, 30
    j       fail
    .balign 4
    .globl  rv32_boot_trap
rv32_boot_trap:
    li      t1, 31
fail:
    slli    t1, t1, 1
    ori     t1, t1, 1
finish:
    lla     t0, tohost
    sw      t1, 0(t0)
    sw      zero, 4(t0)
1:  j       1b

    .section .tohost, "aw", @progbits
    .balign 64
    .globl  tohost
tohost:
    .dword  0
    .globl  fromhost
fromhost:
    .dword  0
