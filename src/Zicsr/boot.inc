/* =============================================================================
 * Fragmento de boot da extensão Zicsr
 *
 * Deixa o estado de máquina em valores conhecidos, para que a aplicação parta
 * de um núcleo sem interrupção habilitada nem pendente e com um tratador seguro:
 *   - mstatus zerado (MIE e MPIE em 0, interrupções globais desligadas);
 *   - mie zerado (nenhuma fonte de interrupção habilitada);
 *   - mscratch zerado;
 *   - mtvec com BASE em rv32_boot_trap e MODE direto (bits 1 e 0 em 0);
 *   - mip zerado, com RV32_HAS_INTERRUPTS (o que o programa pode escrever em mip).
 *
 * Incluído por boot_core.S depois de boot_config.h, sempre, sem #if de quem
 * inclui. Sem RV32_HAS_ZICSR não gera nenhuma instrução. Usa só t0, não define
 * rótulo, dado nem pilha, e exige que rv32_boot_trap esteja alinhado a 4 bytes.
 * Com RV32_HAS_ACCESS_FAULTS não há nada a mais a inicializar, o mtvec já cobre.
 * ============================================================================= */

#if RV32_HAS_ZICSR
    csrw    mstatus, zero
    csrw    mie, zero
    csrw    mscratch, zero
    lla     t0, rv32_boot_trap
    csrw    mtvec, t0
#if RV32_HAS_INTERRUPTS
    csrw    mip, zero
#endif
#endif
