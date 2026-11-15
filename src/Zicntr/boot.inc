/* =============================================================================
 * Fragmento de boot da extensão Zicntr
 *
 * Deixa os contadores de máquina zerados e contando:
 *   - mcycle, mcycleh, minstret e minstreth em 0;
 *   - bits 0 (CY) e 2 (IR) de mcountinhibit em 0, os dois contadores correm
 *     a partir do fim do fragmento. Os demais bits de mcountinhibit são do Zihpm.
 * O mcounteren não existe no núcleo (só há o modo M) e não é escrito. O time é
 * somente leitura e pertence à plataforma.
 *
 * Os dois contadores são inibidos durante a escrita das metades, para a metade
 * baixa não avançar entre uma escrita e a outra.
 *
 * Incluído por boot_core.S depois do fragmento do Zicsr, sempre, sem #if de
 * quem inclui. Sem RV32_HAS_ZICNTR não gera nenhuma instrução. Não usa
 * registrador, não define rótulo, dado nem pilha.
 * ============================================================================= */

#if RV32_HAS_ZICNTR
    csrsi   mcountinhibit, 5
    csrw    mcycle, zero
    csrw    mcycleh, zero
    csrw    minstret, zero
    csrw    minstreth, zero
    csrci   mcountinhibit, 5
#endif
