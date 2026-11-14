/* =============================================================================
 * Fragmento de boot da extensão Zifencei
 *
 * Executa fence.i, para a busca de instruções enxergar o que a inicialização e
 * o carregador gravaram. É a última instrução de inicialização da BOOT.
 *
 * Incluído por boot_core.S depois de todos os outros fragmentos, sempre, sem #if
 * de quem inclui. Sem RV32_HAS_ZIFENCEI não gera nenhuma instrução (num núcleo
 * sem a extensão o fence.i é instrução ilegal). Não usa registrador, não define
 * rótulo, dado nem pilha.
 * ============================================================================= */

#if RV32_HAS_ZIFENCEI
    fence.i
#endif
