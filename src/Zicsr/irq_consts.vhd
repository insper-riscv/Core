-- =============================================================================
-- Constantes das interrupções de máquina (mip, mie e mcause)
--
-- Posição de cada bit de interrupção de máquina em mip e mie, máscara dos bits
-- implementados e código de cada causa de interrupção gravado em mcause (bit 31
-- em '1'), conforme o volume II da especificação do RISC-V (The RISC-V
-- Instruction Set Manual, Volume II: Privileged Architecture).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package irq_consts is

	-- Posição do bit de interrupção de software de máquina (MSIP em mip, MSIE em mie).
	constant IRQ_BIT_SOFTWARE : natural := 3;
	-- Posição do bit de interrupção de timer de máquina (MTIP em mip, MTIE em mie).
	constant IRQ_BIT_TIMER    : natural := 7;
	-- Posição do bit de interrupção externa de máquina (MEIP em mip, MEIE em mie).
	constant IRQ_BIT_EXTERNAL : natural := 11;

	-- Índice de cada interrupção no vetor interno de 3 bits (software).
	constant IRQ_IDX_SOFTWARE : natural := 0;
	-- Índice de cada interrupção no vetor interno de 3 bits (timer).
	constant IRQ_IDX_TIMER    : natural := 1;
	-- Índice de cada interrupção no vetor interno de 3 bits (externa).
	constant IRQ_IDX_EXTERNAL : natural := 2;

	-- Largura do vetor interno de interrupções (software, timer e externa).
	constant IRQ_COUNT        : natural := 3;

	-- Código mcause da interrupção de software de máquina (0x80000003).
	constant CAUSE_IRQ_SOFTWARE : word_t := x"80000003";
	-- Código mcause da interrupção de timer de máquina (0x80000007).
	constant CAUSE_IRQ_TIMER    : word_t := x"80000007";
	-- Código mcause da interrupção externa de máquina (0x8000000B).
	constant CAUSE_IRQ_EXTERNAL : word_t := x"8000000B";

end package irq_consts;
