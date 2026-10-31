-- =============================================================================
-- Constantes dos seletores de adiantamento (forwarding) de operandos
--
-- Códigos de 2 bits produzidos pela forwarding_unit e consumidos pelos muxes
-- de operandos do estágio EX, que escolhem de onde vem o valor de rs1 e rs2.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package fwd_consts is

	-- Seletor de fonte do operando adiantado (2 bits).
	subtype fwd_sel_t is std_logic_vector(1 downto 0);

	-- Sem conflito de dados: vale o valor lido no estágio ID.
	constant FWD_NONE  : fwd_sel_t := "00";
	-- Adiantamento do estágio MEM/WB (instrução duas posições à frente).
	constant FWD_MEMWB : fwd_sel_t := "01";
	-- Adiantamento do estágio EX/MEM (instrução imediatamente anterior).
	constant FWD_EXMEM : fwd_sel_t := "10";
	-- Adiantamento do estágio WB2 (instrução três posições à frente).
	constant FWD_WB2   : fwd_sel_t := "11";

end package fwd_consts;
