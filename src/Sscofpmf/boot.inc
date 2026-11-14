/* =============================================================================
 * Fragmento de boot da extensão Sscofpmf
 *
 * Limpa o estado de estouro dos contadores de eventos:
 *   - mhpmevent3h a mhpmevent31h em 0, o que zera o bit OF (31, estouro) e o
 *     bit MINH (30, inibição no modo M) de cada contador;
 *   - bit 13 de mip (LCOFIP, interrupção de estouro) em 0, porque um estouro
 *     anterior ao fragmento do Zihpm pode tê-lo deixado pendente. O LCOFIE, bit
 *     13 de mie, já foi zerado pelo fragmento do Zicsr.
 *
 * Exige Zihpm e interrupções na plataforma (o bloco core do platform.yaml já
 * as impõe). Incluído por boot_core.S depois do fragmento do Zihpm, sempre, sem
 * #if de quem inclui. Sem RV32_HAS_SSCOFPMF não gera nenhuma instrução. Usa só
 * t0, não define rótulo global, dado nem pilha.
 * ============================================================================= */

#if RV32_HAS_SSCOFPMF
    .set    .Lrv32_hpm, 3
    .rept   29
    csrw    0x720 + .Lrv32_hpm, zero
    .set    .Lrv32_hpm, .Lrv32_hpm + 1
    .endr
    li      t0, 1 << 13
    csrc    mip, t0
#endif
