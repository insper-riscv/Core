-- =============================================================================
-- Constantes de seleção da fonte do próximo PC (pc_src_t)
--
-- Define os códigos de 2 bits (PC_SRC_*) utilizados no estágio IF (pc_fetch)
-- para selecionar o próximo endereço do Program Counter.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package pc_src_consts is

	-- Fluxo sequencial normal (PC + 4).
	constant PC_SRC_PC4      : pc_src_t := "00";
	-- Desvio condicional tomado ou salto JAL (PC_ID + imm).
	constant PC_SRC_BRANCH   : pc_src_t := "01";
	-- Salto indireto JALR ((rs1 + imm) & ~1).
	constant PC_SRC_JALR     : pc_src_t := "10";
	-- Redirecionamento prioritário por trap, MRET ou FENCE.I.
	constant PC_SRC_REDIRECT : pc_src_t := "11";

end package pc_src_consts;
