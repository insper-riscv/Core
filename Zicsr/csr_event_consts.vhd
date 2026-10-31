-- =============================================================================
-- Códigos dos eventos que os contadores de eventos (Zihpm) podem contar
--
-- O contrato do SoC: o código gravado em mhpmeventN escolhe um destes eventos, e
-- o contador soma 1 a cada ciclo em que o evento ocorre. O código 0 não conta
-- nada, e um código fora da tabela também não conta. Os eventos de 5 a 7 vêm das
-- caches e da FLASH, fora do núcleo.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package csr_event_consts is

	-- Largura do código de evento gravado em mhpmeventN.
	constant EVENT_CODE_WIDTH : natural := 4;
	-- Tamanho do vetor de eventos: um bit por código, o bit 0 sempre em zero.
	constant EVENT_VECTOR_WIDTH : natural := 16;

	-- Nenhum evento: o contador não soma.
	constant EVENT_NONE          : natural := 0;
	-- Ciclo de parada da multiplicação ou divisão.
	constant EVENT_MULDIV_STALL  : natural := 1;
	-- Ciclo de espera por memória externa.
	constant EVENT_EXT_WAIT      : natural := 2;
	-- Desvio ou salto tomado.
	constant EVENT_BRANCH_TAKEN  : natural := 3;
	-- Acesso desalinhado executado em duas palavras.
	constant EVENT_MISALIGNED    : natural := 4;
	-- Falha da cache de instruções.
	constant EVENT_ICACHE_MISS   : natural := 5;
	-- Falha da cache de dados.
	constant EVENT_DCACHE_MISS   : natural := 6;
	-- Ciclo de espera por FLASH.
	constant EVENT_FLASH_WAIT    : natural := 7;
	-- Ciclo de parada por dependência de load.
	constant EVENT_LOAD_USE      : natural := 8;

end package csr_event_consts;
