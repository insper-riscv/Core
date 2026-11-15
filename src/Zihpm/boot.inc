/* =============================================================================
 * Fragmento de boot da extensão Zihpm
 *
 * Deixa os 29 contadores de eventos (índices 3 a 31) em estado conhecido:
 *   - mhpmevent3 a mhpmevent31 em 0 (evento nenhum, o contador não conta);
 *   - mhpmcounter3 a mhpmcounter31 e as metades altas mhpmcounter3h a
 *     mhpmcounter31h em 0;
 *   - bits 3 a 31 de mcountinhibit em 0. Os bits 0 a 2 são do Zicntr.
 * Os seletores são zerados antes dos contadores, e a inibição só é liberada no
 * fim, para nenhum contador contar durante a limpeza.
 *
 * Um núcleo que implementa só parte dos contadores (hpm_counters) responde a
 * todos os 29 endereços: o índice sem contador lê zero e ignora a escrita, sem
 * exceção. O fragmento escreve os 29 índices sem consultar a quantidade.
 *
 * Incluído por boot_core.S depois do fragmento do Zicntr, sempre, sem #if de
 * quem inclui. Sem RV32_HAS_ZIHPM não gera nenhuma instrução. Usa só t0, não
 * define rótulo global (o símbolo .Lrv32_hpm é local do montador), dado nem pilha.
 * ============================================================================= */

#if RV32_HAS_ZIHPM
    .set    .Lrv32_hpm, 3
    .rept   29
    csrw    0x320 + .Lrv32_hpm, zero
    .set    .Lrv32_hpm, .Lrv32_hpm + 1
    .endr
    .set    .Lrv32_hpm, 3
    .rept   29
    csrw    0xB00 + .Lrv32_hpm, zero
    .set    .Lrv32_hpm, .Lrv32_hpm + 1
    .endr
    .set    .Lrv32_hpm, 3
    .rept   29
    csrw    0xB80 + .Lrv32_hpm, zero
    .set    .Lrv32_hpm, .Lrv32_hpm + 1
    .endr
    li      t0, -8
    csrc    mcountinhibit, t0
#endif
